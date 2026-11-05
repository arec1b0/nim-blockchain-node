## Node and runtime service wrappers for Nim blockchain node CLI.
## Encapsulates operations against BlockchainNode and NodeConfig with no global state.

import std/[times, logging, options]
import ../common/[types, result, config]
import ../core_engine/[consensus, state_management, vm]
import ../storage/[blockchain_store, index_store, blockchain_db, account_store]
import ../network/[mempool, p2p]
import ../cryptography/[key_management, keystore, signature_verification]
import ../node as runtime
export runtime.BlockchainNode

type
  CliConfig* = NodeConfig

  CliInitError* = enum
    cliInitNone
    cliInitUnexpected
    cliInitAccountStore

  CreatedAccount* = object
    address*: Address
    publicKey*: PublicKey
    keystorePath*: string

  TransferError* = enum
    trNone
    trKeystoreMissing
    trKeystoreMalformed
    trKeystoreUnsafePath
    trKeystoreIo
    trZeroAmount
    trMissingPublicKey
    trMissingSignature
    trSenderKeyMismatch
    trInvalidSignature
    trInsufficientBalance
    trBadNonce
    trEmptyReceiver
    trGasLimitExceeded
    trDebitFailed
    trAccountStore
    trMempoolDuplicate
    trMempoolFull
    trBlockPropagationFailed
    trBlockStorageFailed
    trNegativeFee

  TransferResult* = object
    tx*: Transaction
    fromBalance*: Balance
    toBalance*: Balance

  NodeStatusInfo* = object
    height*: BlockHeight
    validators*: int
    pendingTransactions*: int
    peers*: int
    gasLimit*: Natural
    gasUsed*: Natural

  AccountBalanceInfo* = object
    address*: string
    balance*: Balance
    nonce*: Nonce

  AccountEntry* = object
    address*: string
    balance*: Balance
    hasKeystore*: bool

  CliServiceContext* = ref object
    node*: BlockchainNode
    config*: NodeConfig

proc newCliServiceContext*(node: BlockchainNode, config: NodeConfig): CliServiceContext =
  CliServiceContext(node: node, config: config)

proc initCliNode*(cfg: NodeConfig): Result[BlockchainNode, CliInitError] =
  ## Initializes a BlockchainNode instance from NodeConfig using the composition root.
  try:
    var effectiveCfg = cfg
    if isMemoryDataDir(effectiveCfg.dataDir):
      effectiveCfg.storageBackend = backendMemory
    let prepared = runtime.newBlockchainNode(effectiveCfg)
    if not prepared.ok:
      case prepared.error
      of runtime.nodeInitStorage:
        return errResult(BlockchainNode, cliInitAccountStore)
      else:
        return errResult(BlockchainNode, cliInitUnexpected)
    debug("node initialized dataDir=" & cfg.dataDir)
    info("blockchain node initialized")
    okResult(prepared.value, CliInitError)
  except CatchableError as e:
    error("blockchain node initialization failed: " & $e.name)
    errResult(BlockchainNode, cliInitUnexpected)

proc initCliServiceContext*(cfg: NodeConfig): Result[CliServiceContext, CliInitError] =
  ## Constructs and initializes a new CliServiceContext with an active BlockchainNode.
  var effectiveCfg = cfg
  if isMemoryDataDir(effectiveCfg.dataDir):
    effectiveCfg.storageBackend = backendMemory
  let prepared = initCliNode(effectiveCfg)
  if not prepared.ok:
    return errResult(CliServiceContext, prepared.error)
  okResult(newCliServiceContext(prepared.value, effectiveCfg), CliInitError)

proc close*(ctx: CliServiceContext) =
  ## Closes the runtime node and associated resources.
  if not ctx.isNil and not ctx.node.isNil:
    discard runtime.close(ctx.node)

proc persistAccountState*(ctx: CliServiceContext): Status[AccountStoreError] =
  ## Persists the VM ledger through the account store.
  if ctx.isNil or ctx.node.isNil:
    return errStatus(asIo)
  runtime.persistAccountState(ctx.node)

proc getNodeStatus*(ctx: CliServiceContext): NodeStatusInfo =
  ## Retrieves current node metrics and state indicators.
  if ctx.isNil or ctx.node.isNil:
    return NodeStatusInfo()
  NodeStatusInfo(
    height: ctx.node.blockchainStore.getCurrentHeight(),
    validators: ctx.node.consensus.activeValidatorCount(),
    pendingTransactions: ctx.node.mempool.transactionCount(),
    peers: ctx.node.network.connectedPeerCount(),
    gasLimit: ctx.node.vm.gasLimit,
    gasUsed: ctx.node.vm.gasUsed
  )

proc getAccountBalance*(ctx: CliServiceContext, address: string): AccountBalanceInfo =
  ## Inspects balance and nonce for a given address.
  if ctx.isNil or ctx.node.isNil:
    return AccountBalanceInfo(address: address, balance: 0, nonce: 0)
  AccountBalanceInfo(
    address: address,
    balance: ctx.node.vm.state.getBalance(address),
    nonce: ctx.node.vm.state.getNonce(address)
  )

proc listAccounts*(ctx: CliServiceContext): seq[AccountEntry] =
  ## Lists known system accounts and their balances.
  if ctx.isNil or ctx.node.isNil:
    return @[]
  let genesisBalance = ctx.node.vm.state.getBalance("genesis")
  @[AccountEntry(address: "genesis", balance: genesisBalance, hasKeystore: false)]

proc getLatestBlock*(ctx: CliServiceContext): Option[Block] =
  ## Retrieves the latest block committed to the blockchain store.
  if ctx.isNil or ctx.node.isNil:
    return none(Block)
  ctx.node.blockchainStore.getLatestBlock()

proc getBlock*(ctx: CliServiceContext, height: int): Option[Block] =
  ## Retrieves a block by height from the blockchain store.
  if ctx.isNil or ctx.node.isNil:
    return none(Block)
  ctx.node.blockchainStore.getBlock(BlockHeight(height))

proc getCurrentHeight*(ctx: CliServiceContext): BlockHeight =
  ## Returns current blockchain height.
  if ctx.isNil or ctx.node.isNil:
    return 0.BlockHeight
  ctx.node.blockchainStore.getCurrentHeight()

proc getPendingTransactions*(ctx: CliServiceContext, limit: int = 10): seq[Transaction] =
  ## Retrieves pending transactions ordered by fee from the mempool.
  if ctx.isNil or ctx.node.isNil:
    return @[]
  ctx.node.mempool.getTransactionsByFee(limit)

proc rollbackNewAccount(node: BlockchainNode, address: Address) =
  discard node.vm.state.deleteAccount(address)
  let rolled = runtime.persistAccountState(node)
  if not rolled.ok:
    error("account rollback failed address=" & address)

proc createAccount*(ctx: CliServiceContext): Result[CreatedAccount, KeystoreError] =
  ## Creates a new keypair, records the account in state and disk keystore.
  ## Does not write to stdout directly; returns typed result.
  if ctx.isNil or ctx.node.isNil:
    return errResult(CreatedAccount, ksIo)
  if isMemoryDataDir(ctx.config.dataDir):
    return errResult(CreatedAccount, ksUnsafePath)
  try:
    let keyPair = generateKeyPair()
    let address = addressFromPublicKey(keyPair.publicKey)
    let createdNew = not ctx.node.vm.state.hasAccount(address)
    if createdNew:
      ctx.node.vm.state.setBalance(address, 0)
    let persisted = runtime.persistAccountState(ctx.node)
    if not persisted.ok:
      if createdNew:
        discard ctx.node.vm.state.deleteAccount(address)
      return errResult(CreatedAccount, ksIo)
    let saved = saveKeystore(ctx.config.dataDir, address, keyPair.publicKey, keyPair.privateKey)
    if not saved.ok:
      if createdNew:
        rollbackNewAccount(ctx.node, address)
      return errResult(CreatedAccount, saved.error)
    let created = CreatedAccount(
      address: address,
      publicKey: keyPair.publicKey,
      keystorePath: keystoreFile(ctx.config.dataDir, address)
    )
    info("account created address=" & created.address)
    okResult(created, KeystoreError)
  except CatchableError:
    errResult(CreatedAccount, ksIo)

proc fromKeystore*(err: KeystoreError): TransferError =
  case err
  of ksNone, ksMalformed, ksExists: trKeystoreMalformed
  of ksMissing: trKeystoreMissing
  of ksUnsafePath: trKeystoreUnsafePath
  of ksIo: trKeystoreIo

proc fromStageError*(err: runtime.TxStageError): TransferError =
  case err
  of runtime.txStageNone: trNone
  of runtime.txStageMempoolDuplicate: trMempoolDuplicate
  of runtime.txStageMempoolFull: trMempoolFull
  of runtime.txStageMissingPublicKey: trMissingPublicKey
  of runtime.txStageMissingSignature: trMissingSignature
  of runtime.txStageSenderKeyMismatch: trSenderKeyMismatch
  of runtime.txStageInvalidSignature: trInvalidSignature
  of runtime.txStageInsufficientBalance: trInsufficientBalance
  of runtime.txStageBadNonce: trBadNonce
  of runtime.txStageEmptyReceiver: trEmptyReceiver
  of runtime.txStageGasLimitExceeded: trGasLimitExceeded
  of runtime.txStageZeroAmount: trZeroAmount
  of runtime.txStageDebitFailed: trDebitFailed
  of runtime.txStagePropagationFailed: trBlockPropagationFailed
  of runtime.txStageStorageError: trAccountStore

proc transferFunds*(ctx: CliServiceContext, fromAddr, toAddr: string, amount: int, fee: int = 10): Result[TransferResult, TransferError] =
  ## Signs with sender keystore key and executes through canonical 5-stage lifecycle.
  ## Returns TransferResult or typed TransferError with no stdout side-effects.
  debug("transfer requested from=" & fromAddr & " to=" & toAddr)
  if ctx.isNil or ctx.node.isNil:
    return errResult(TransferResult, trNone)
  if isMemoryDataDir(ctx.config.dataDir):
    return errResult(TransferResult, trKeystoreUnsafePath)
  if toAddr.len == 0:
    return errResult(TransferResult, trEmptyReceiver)
  if amount <= 0:
    return errResult(TransferResult, trZeroAmount)
  if fee < 0:
    return errResult(TransferResult, trNegativeFee)
  var loaded = loadKeystore(ctx.config.dataDir, fromAddr)
  if not loaded.ok:
    let reason = fromKeystore(loaded.error)
    return errResult(TransferResult, reason)
  let nextNonce = Nonce(ctx.node.vm.state.getNonce(fromAddr) + 1)
  var tx = Transaction(
    id: "tx_" & $getTime().toUnix() & "_" & $nextNonce,
    sender: fromAddr,
    receiver: toAddr,
    amount: amount.Balance,
    fee: fee.Balance,
    nonce: nextNonce,
    publicKey: loaded.value.publicKey
  )
  try:
    tx.signature = signMessage(loaded.value.privateKey, transactionSigningPayload(tx))
  except ValueError:
    loaded.value.privateKey = ""
    return errResult(TransferResult, trKeystoreMalformed)
  loaded.value.privateKey = ""

  let executed = ctx.node.submitAndExecuteTransaction(tx)
  if not executed.ok:
    let reason = fromStageError(executed.error)
    return errResult(TransferResult, reason)

  let res = TransferResult(
    tx: tx,
    fromBalance: ctx.node.vm.state.getBalance(fromAddr),
    toBalance: ctx.node.vm.state.getBalance(toAddr)
  )
  info("transfer applied id=" & shortId(tx.id))
  okResult(res, TransferError)
