## Main entry point for the Nim blockchain node.
## Initializes components via the shared composition root (`node.nim`), logs status, and exits.
## A long-running server loop is intentionally not started here.
## Diagnostics use std/logging. Command-style output is not required.

import std/[logging]
import node
import network/block_propagation
import common/[types, result, config, logsetup]
import cryptography/[key_management, signature_verification]

proc initializeNode(cfg: NodeConfig): Status[NodeInitError] =
  ## Initializes all blockchain node components via the shared composition root, then returns.
  info("starting nim blockchain node (educational prototype)")
  debug("signature scheme " & DemoSignatureScheme & " is not production cryptography")
  debug("data directory=" & cfg.dataDir)

  let nodeRes = newBlockchainNode(cfg)
  if not nodeRes.ok:
    return errStatus(nodeRes.error)
  let node = nodeRes.value

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
  let admitted = node.mempool.addTransaction(tx1)
  if admitted.ok:
    info("sample transaction added to mempool id=" & tx1.id)
  else:
    warn("sample transaction was not admitted id=" & shortId(tx1.id))

  let genesisBlock = newBlock("genesis_block", 0, "Genesis block data")
  let status = propagateBlock(node.network, genesisBlock)

  if status.result == Success:
    if node.blockchainDB.addBlock(0, genesisBlock.data, genesisBlock.id, genesisBlock.timestamp):
      info("genesis block stored at height 0")
      discard node.indexDB.indexTransaction("genesis_tx", 0, 0)
      info("genesis transaction indexed")
    else:
      warn("failed to store genesis block")
      discard node.close()
      return errStatus(nodeInitStorage)
  else:
    warn("genesis block propagation failed")
    discard node.close()
    return errStatus(nodeInitPropagation)

  info("blockchain node initialized")
  info("blockchain height=" & $node.blockchainDB.getCurrentHeight())
  info("active validators=" & $node.consensus.activeValidatorCount())
  info("mempool transactions=" & $node.mempool.transactionCount())
  info("network peers=" & $node.network.peerCount())

  let closed = node.close()
  if not closed.ok:
    return errStatus(nodeInitStorage)
  okStatus(NodeInitError)

proc main() =
  ## Entry point. Parses config, configures logging, initializes, and exits.
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
