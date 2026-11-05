## Shared composition root for the Nim blockchain node.
## Centralizes component construction, runtime configuration, and default parameters.
## Both `main.nim` and `cli.nim` compose the node through this module.

import std/[os, logging, options]
import core_engine/[consensus, state_management, vm]
import storage/[blockchain_store, index_store, blockchain_db, state_db, index_db, account_store]
import network/[mempool, p2p, block_propagation]
import common/[result, config, types]

export consensus, state_management, vm
export blockchain_store, index_store
export blockchain_db, state_db, index_db, account_store
export mempool, p2p, block_propagation
export types

type
  NodeInitError* = enum
    nodeInitNone
    nodeInitDataDir
    nodeInitStorage
    nodeInitPropagation
    nodeInitUnexpected

  TxStageError* = enum
    txStageNone
    txStageMempoolDuplicate
    txStageMempoolFull
    txStageMissingPublicKey
    txStageMissingSignature
    txStageSenderKeyMismatch
    txStageInvalidSignature
    txStageInsufficientBalance
    txStageBadNonce
    txStageEmptyReceiver
    txStageGasLimitExceeded
    txStageZeroAmount
    txStageDebitFailed
    txStagePropagationFailed
    txStageStorageError

  TxExecutionSuccess* = object
    blockHeight*: BlockHeight
    blockHash*: BlockHash
    txId*: TransactionId

  BlockchainNode* = ref object
    config*: NodeConfig
    consensus*: Consensus
    accountState*: StateDB
    globalState*: GlobalStateStore
    blockchainStore*: BlockchainStore
    indexStore*: IndexStore
    mempool*: Mempool
    network*: Network
    vm*: VM
    accounts*: AccountStore

proc blockchainDB*(node: BlockchainNode): BlockchainStore {.inline.} =
  ## Backward-compatible accessor exposing blockchainStore through blockchainDB name.
  node.blockchainStore

proc `blockchainDB=`*(node: BlockchainNode, store: BlockchainStore) {.inline.} =
  node.blockchainStore = store

proc indexDB*(node: BlockchainNode): IndexStore {.inline.} =
  ## Backward-compatible accessor exposing indexStore through indexDB name.
  node.indexStore

proc `indexDB=`*(node: BlockchainNode, store: IndexStore) {.inline.} =
  node.indexStore = store

proc newBlockchainNode*(cfg: NodeConfig): Result[BlockchainNode, NodeInitError] =
  ## Initializes all components of the blockchain node from configuration.
  debug("initializing blockchain node dataDir=" & cfg.dataDir)
  if not isMemoryDataDir(cfg.dataDir):
    try:
      createDir(cfg.dataDir)
    except CatchableError as e:
      error("cannot create data directory: " & $e.name)
      return errResult(BlockchainNode, nodeInitDataDir)

  var preparedLedger: PreparedLedger
  try:
    let prepared = prepareAccountLedger(cfg.dataDir)
    if not prepared.ok:
      error("account store initialization failed path=" & cfg.dataDir &
        " reason=" & accountStoreFailure(prepared.error))
      return errResult(BlockchainNode, nodeInitStorage)
    preparedLedger = prepared.value
  except CatchableError as e:
    error("account store setup failed: " & $e.name)
    return errResult(BlockchainNode, nodeInitStorage)

  var consensus = newConsensus()
  for v in cfg.validators:
    if not consensus.addValidator(v.id, v.stake):
      warn("validator could not be added id=" & $v.id & " stake=" & $v.stake)

  let globalState = newGlobalStateStore()
  let blockchainStore = newBlockchainStore()
  let indexStore = newIndexStore()
  let vm = newVM(preparedLedger.state, cfg.gasLimit)
  let mempool = newMempool(cfg.mempoolCapacity)
  let network = newNetwork(cfg.maxPeers)

  let node = BlockchainNode(
    config: cfg,
    consensus: consensus,
    accountState: preparedLedger.state,
    globalState: globalState,
    blockchainStore: blockchainStore,
    indexStore: indexStore,
    mempool: mempool,
    network: network,
    vm: vm,
    accounts: preparedLedger.store
  )
  info("blockchain node initialized")
  okResult(node, NodeInitError)

proc close*(node: BlockchainNode): Status[AccountStoreError] =
  ## Closes the account store and any resources held by the node.
  if node.isNil or node.accounts.isNil:
    return okStatus(AccountStoreError)
  let closed = node.accounts.closeAccountStore()
  if not closed.ok:
    error("account store close failed reason=" & accountStoreFailure(closed.error))
  closed

proc persistAccountState*(node: BlockchainNode): Status[AccountStoreError] =
  ## Flushes `node.vm.state` to the account store and synchronizes `node.accountState`.
  if node.isNil or node.accounts.isNil:
    return errStatus(asIo)
  let saved = node.accounts.saveAccounts(node.vm.state)
  if saved.ok:
    node.accountState = node.vm.state
  else:
    error("account store save failed path=" & node.config.dataDir &
      " reason=" & accountStoreFailure(saved.error))
  saved

proc submitAndExecuteTransaction*(node: BlockchainNode, tx: Transaction): Result[TxExecutionSuccess, TxStageError] =
  ## Orchestrates the canonical 5-stage transaction lifecycle:
  ## 1. Submit: Caller creates & signs the transaction.
  ## 2. Mempool validation & admission: Authorize signature and admit to mempool.
  ##    If admission fails, abort immediately before touching VM or storage.
  ## 3. Block inclusion & propagation: Form candidate block containing the transaction,
  ##    link previousHash, and propagate via injected network.
  ## 4. VM execution: Apply transaction to VM state.
  ##    If VM execution fails, evict transaction from mempool, abort block commit.
  ## 5. Storage & index update: Store block in blockchainDB, index tx in indexDB,
  ##    evict confirmed tx from mempool, and persist account state snapshot.
  if node.isNil:
    return errResult(TxExecutionSuccess, txStageStorageError)

  # Stage 2: Mempool validation and admission
  let admitted = node.mempool.addTransaction(tx)
  if not admitted.ok:
    case admitted.error
    of maNone: discard
    of maDuplicate: return errResult(TxExecutionSuccess, txStageMempoolDuplicate)
    of maFull: return errResult(TxExecutionSuccess, txStageMempoolFull)
    of maMissingPublicKey: return errResult(TxExecutionSuccess, txStageMissingPublicKey)
    of maMissingSignature: return errResult(TxExecutionSuccess, txStageMissingSignature)
    of maSenderKeyMismatch: return errResult(TxExecutionSuccess, txStageSenderKeyMismatch)
    of maInvalidSignature: return errResult(TxExecutionSuccess, txStageInvalidSignature)

  # Stage 3: Block inclusion candidate and propagation
  let currentHeight = node.blockchainStore.getCurrentHeight()
  let nextHeight = currentHeight + 1
  let prevHash = if currentHeight > 0:
                   let prevOpt = node.blockchainStore.getBlock(currentHeight)
                   if prevOpt.isSome: prevOpt.get.hash else: "00000000000000000000000000000000"
                 else:
                   "00000000000000000000000000000000"

  let blockId = "blk_" & $nextHeight
  let blk = newBlock(blockId, nextHeight, "tx:" & tx.id, prevHash)
  let propStatus = propagateBlock(node.network, blk)
  if propStatus.result != Success:
    warn("block propagation status was not Success: " & $propStatus.result)

  # Stage 4: VM execution
  let applied = node.vm.applyTransaction(tx)
  if not applied.ok:
    # Evict failed transaction from mempool so invalid tx does not linger
    discard node.mempool.removeTransaction(tx.id)
    case applied.error
    of txNone, txDebitFailed: return errResult(TxExecutionSuccess, txStageDebitFailed)
    of txZeroAmount: return errResult(TxExecutionSuccess, txStageZeroAmount)
    of txMissingPublicKey: return errResult(TxExecutionSuccess, txStageMissingPublicKey)
    of txMissingSignature: return errResult(TxExecutionSuccess, txStageMissingSignature)
    of txSenderKeyMismatch: return errResult(TxExecutionSuccess, txStageSenderKeyMismatch)
    of txInvalidSignature: return errResult(TxExecutionSuccess, txStageInvalidSignature)
    of txInsufficientBalance: return errResult(TxExecutionSuccess, txStageInsufficientBalance)
    of txBadNonce: return errResult(TxExecutionSuccess, txStageBadNonce)
    of txEmptyReceiver: return errResult(TxExecutionSuccess, txStageEmptyReceiver)
    of txGasLimitExceeded: return errResult(TxExecutionSuccess, txStageGasLimitExceeded)

  # Stage 5: Storage and index update
  let blockStored = node.blockchainStore.addBlock(blk)
  if not blockStored:
    error("failed to store block at height " & $nextHeight)
    return errResult(TxExecutionSuccess, txStageStorageError)

  discard node.indexStore.indexTransaction(tx.id, nextHeight, 0)
  discard node.mempool.removeTransaction(tx.id)

  let saved = node.persistAccountState()
  if not saved.ok:
    error("failed to persist account state after tx execution")
    return errResult(TxExecutionSuccess, txStageStorageError)

  okResult(TxExecutionSuccess(
    blockHeight: nextHeight,
    blockHash: blockId,
    txId: tx.id
  ), TxStageError)
