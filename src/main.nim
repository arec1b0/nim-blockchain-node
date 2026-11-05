## Main entry point for the Nim blockchain node.
## Initializes components, logs status, and exits.
## A long-running server loop is intentionally not started here.
## Diagnostics use std/logging. Command-style output is not required.

import std/[os, logging]
import core_engine/[consensus, state_management, vm]
import storage/[blockchain_db, index_db, account_store]
import network/[mempool, block_propagation, p2p]
import common/[types, result, config, logsetup]
import cryptography/[key_management, signature_verification]

type
  NodeInitError = enum
    nodeInitNone
    nodeInitDataDir
    nodeInitStorage
    nodeInitPropagation
    nodeInitUnexpected

proc initializeNode(cfg: NodeConfig): Status[NodeInitError] =
  ## Initializes all blockchain node components, then returns.
  info("starting nim blockchain node (educational prototype)")
  debug("signature scheme " & DemoSignatureScheme & " is not production cryptography")
  debug("data directory=" & cfg.dataDir)
  if not isMemoryDataDir(cfg.dataDir):
    try:
      createDir(cfg.dataDir)
    except CatchableError as e:
      error("cannot create data directory: " & $e.name)
      return errStatus(nodeInitDataDir)

  var accounts: AccountStore
  block startup:
    try:
      let prepared = prepareAccountLedger(cfg.dataDir)
      if not prepared.ok:
        error("account store initialization failed path=" & cfg.dataDir &
          " reason=" & accountStoreFailure(prepared.error))
        result = errStatus(nodeInitStorage)
        break startup
      accounts = prepared.value.store
      let stateManager = prepared.value.state
      info("account store loaded genesisBalance=" & $stateManager.getBalance("genesis"))

      var consensus = newConsensus()
      discard consensus.addValidator(1, 1000)
      discard consensus.addValidator(2, 1500)
      info("consensus engine initialized validators=" & $consensus.activeValidatorCount())

      let blockchainDB = newBlockchainDB()
      let indexDB = newIndexDB()
      info("storage systems initialized")

      let vm = newVM(stateManager, 100000)
      info("virtual machine initialized gasLimit=" & $vm.gasLimit)

      let mempool = newMempool(5000)
      let network = newNetwork(50)
      info("network systems initialized")

      # In-memory demo transaction. The private key is not stored or logged.
      let keys = generateKeyPair()
      var tx1 = Transaction(
        id: "tx_001",
        receiver: "user1",
        amount: 100,
        fee: 10,
        nonce: 1,
        publicKey: keys.publicKey
      )
      tx1.sender = addressFromPublicKey(keys.publicKey)
      tx1.signature = signMessage(keys.privateKey, transactionSigningPayload(tx1))
      let admitted = mempool.addTransaction(tx1)
      if admitted.ok:
        info("sample transaction added to mempool id=" & tx1.id)
      else:
        warn("sample transaction was not admitted id=" & shortId(tx1.id))

      let genesisBlock = newBlock("genesis_block", 0, "Genesis block data")
      let status = propagateBlock(genesisBlock)

      if status.result == Success:
        if blockchainDB.addBlock(0, genesisBlock.data, genesisBlock.id, genesisBlock.timestamp):
          info("genesis block stored at height 0")
          discard indexDB.indexTransaction("genesis_tx", 0, 0)
          info("genesis transaction indexed")
        else:
          warn("failed to store genesis block")
          result = errStatus(nodeInitStorage)
          break startup
      else:
        warn("genesis block propagation failed")
        result = errStatus(nodeInitPropagation)
        break startup

      info("blockchain node initialized")
      info("blockchain height=" & $blockchainDB.getCurrentHeight())
      info("active validators=" & $consensus.activeValidatorCount())
      info("mempool transactions=" & $mempool.transactionCount())
      info("network peers=" & $network.peerCount())
      result = okStatus(NodeInitError)
    except CatchableError as e:
      error("blockchain node initialization failed: " & $e.name)
      result = errStatus(nodeInitUnexpected)

  if not accounts.isNil:
    let closed = accounts.closeAccountStore()
    if not closed.ok:
      error("account store close failed reason=" & accountStoreFailure(closed.error))
      if result.ok:
        result = errStatus(nodeInitStorage)

proc main() =
  ## Composition root. Parses config, configures logging, initializes, and exits.
  let overrides = readCliOverrides()
  let cfg = resolveConfig(overrides)
  configureLogging(cfg.verbose)
  if overrides.errorMessage.len > 0:
    error(overrides.errorMessage)
    quit(1)
  if overrides.helpRequested:
    echo """Educational prototype. Options: --verbose, --data-dir DIR.
Environment: NIM_NODE_VERBOSE, NIM_NODE_DATA_DIR (CLI flags win when set).
Account balances and nonces load from <data-dir>/accounts.json.
--data-dir=:memory: keeps them in memory. Blocks and peers are not saved.
The process initializes and exits. It is not a long-running server.
Signature scheme: demo-sha256 (not Ed25519)."""
    quit(0)
  if not initializeNode(cfg).ok:
    quit(1)
  info("blockchain node is operational")

when isMainModule:
  main()
