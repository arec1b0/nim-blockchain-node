import unittest
import ../../src/common/types
import ../../src/common/config
import ../../src/core_engine/consensus
import ../../src/core_engine/state_management
import ../../src/core_engine/vm
import ../../src/storage/blockchain_db
import ../../src/storage/state_db
import ../../src/storage/index_db
import ../../src/storage/blockchain_store
import ../../src/storage/index_store
import ../../src/network/mempool
import ../../src/network/p2p
import ../../src/network/block_propagation
import ../../src/cryptography/key_management
import ../../src/cryptography/signature_verification
import ../../src/node as composition
import std/options

suite "Blockchain Node Integration Tests":

  test "End-to-end block creation and propagation":
    # 1. Initialize Core Components
    var consensus = newConsensus()
    discard consensus.addValidator(1, 1000)
    discard consensus.addValidator(2, 1500)

    # Initialize Storage and Network Components
    let globalStateDB = newGlobalStateStore()
    var accountStateDB = newStateDB()
    let blockchainDB = newBlockchainDB()
    let indexDB = newIndexDB()
    let mempool = newMempool()
    let network = newNetwork()

    # Initialize account states. The sender address comes from the demo key.
    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    accountStateDB.setBalance(sender, 1000)
    accountStateDB.setBalance("Bob", 500)

    # Initialize VM
    var vm = newVM(accountStateDB, 100000)

    # Stage 1: Submit transaction
    let tx = signedTransaction(Transaction(
      id: "tx999", receiver: "Bob", amount: 100, fee: 10, nonce: 1), keys)

    # Stage 2: Mempool validation and admission
    check mempool.addTransaction(tx).ok
    check mempool.hasTransaction("tx999") == true

    # Stage 3: Block inclusion candidate and propagation via injected network
    let blk = newBlock("blk999", 1, "tx999 included")
    let status = propagateBlock(network, blk)
    check status.result == Success

    # Stage 4: VM execution
    check vm.applyTransaction(tx).ok

    # Stage 5: Storage & index update
    check blockchainDB.addBlock(1, blk.data, blk.id, blk.timestamp) == true
    check indexDB.indexTransaction("tx999", 1, 0) == true
    check mempool.removeTransaction("tx999") == true
    check mempool.hasTransaction("tx999") == false
    
    let storedBlock = blockchainDB.getBlock(1)
    check storedBlock.isSome
    check storedBlock.get.data == "tx999 included"

    let txLoc = indexDB.getTransactionLocation("tx999")
    check txLoc.isSome
    check txLoc.get.blockHeight == 1
    check txLoc.get.transactionIndex == 0

    # Update global state
    check globalStateDB.setState("accountA", 500)
    check globalStateDB.getState("accountA") == 500

    # Verify final states (StateDB is a value type; VM holds the mutated copy)
    check vm.state.getBalance(sender) == 890  # 1000 - 100 - 10
    check vm.state.getBalance("Bob") == 600    # 500 + 100
    check blockchainDB.getCurrentHeight() == 1
    check consensus.activeValidatorCount() == 2

  test "Canonical Transaction is accepted by both mempool and VM":
    ## One `common/types.Transaction` shape feeds both admission and execution.
    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    var state = newStateDB()
    state.setBalance(sender, 500)
    state.setBalance("Carol", 0)
    var vm = newVM(state, 100000)
    let pool = newMempool(100)
    let tx = signedTransaction(Transaction(
      id: "canonical-tx",
      receiver: "Carol",
      amount: 40,
      fee: 5,
      nonce: 1,
      size: 128
    ), keys)
    check authorizeTransaction(tx).ok
    check pool.addTransaction(tx).ok
    check pool.hasTransaction("canonical-tx")
    check vm.validateTransaction(tx).ok
    check vm.applyTransaction(tx).ok
    check vm.state.getBalance(sender) == 455
    check vm.state.getBalance("Carol") == 40
    check pool.getTransaction("canonical-tx").fee == 5
    check pool.getTransaction("canonical-tx").size == 128

  test "End-to-end transaction lifecycle via composition root (submit -> mempool -> block -> VM -> storage)":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    cfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(cfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)

    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    let receiver = "recipient_1"

    n.vm.state.setBalance(sender, 1000)
    discard n.persistAccountState()
    check n.accountState.getBalance(sender) == 1000

    let tx = signedTransaction(Transaction(
      id: "tx_lifecycle_001",
      receiver: receiver,
      amount: 250,
      fee: 10,
      nonce: 1
    ), keys)

    let result = n.submitAndExecuteTransaction(tx)
    check result.ok
    check result.value.blockHeight == 1
    check result.value.blockHash == "blk_1"
    check result.value.txId == tx.id

    # Verify storage updates
    check n.blockchainDB.getCurrentHeight() == 1
    let latest = n.blockchainDB.getLatestBlock()
    check latest.isSome
    check latest.get.height == 1
    check latest.get.hash == "blk_1"
    check latest.get.data == "tx:" & tx.id

    # Verify index updates
    check n.indexDB.hasTransaction(tx.id)
    let loc = n.indexDB.getTransactionLocation(tx.id)
    check loc.isSome
    check loc.get.blockHeight == 1
    check loc.get.transactionIndex == 0

    # Verify mempool is cleared of confirmed transaction
    check not n.mempool.hasTransaction(tx.id)
    check n.mempool.transactionCount() == 0

    # Verify balances updated in both vm.state and synchronized accountState
    check n.vm.state.getBalance(sender) == 740   # 1000 - 250 - 10
    check n.vm.state.getBalance(receiver) == 250
    check n.accountState.getBalance(sender) == 740
    check n.accountState.getBalance(receiver) == 250
    check n.accountState.getNonce(sender) == 1

  test "Invalid or unsigned transaction is rejected at mempool validation before VM execution":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    cfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(cfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)

    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    n.vm.state.setBalance(sender, 500)
    discard n.persistAccountState()

    # Case 1: Missing public key
    let missingPkTx = Transaction(
      id: "tx_missing_pk",
      sender: sender,
      receiver: "recipient_2",
      amount: 50,
      fee: 5,
      nonce: 1
    )
    let res1 = n.submitAndExecuteTransaction(missingPkTx)
    check not res1.ok
    check res1.error == composition.txStageMissingPublicKey

    # Case 2: Missing signature (public key present, signature empty)
    let missingSigTx = Transaction(
      id: "tx_missing_sig",
      sender: sender,
      receiver: "recipient_2",
      amount: 50,
      fee: 5,
      nonce: 1,
      publicKey: keys.publicKey
    )
    let res2 = n.submitAndExecuteTransaction(missingSigTx)
    check not res2.ok
    check res2.error == composition.txStageMissingSignature

    # Case 3: Invalid signature
    var badSigTx = missingSigTx
    badSigTx.id = "tx_bad_sig"
    badSigTx.signature = "invalid_signature_hex"
    let res3 = n.submitAndExecuteTransaction(badSigTx)
    check not res3.ok
    check res3.error == composition.txStageInvalidSignature

    # Storage and VM state must remain completely untouched
    check n.blockchainDB.getCurrentHeight() == 0
    check not n.blockchainDB.getLatestBlock().isSome
    check not n.indexDB.hasTransaction("tx_missing_pk")
    check not n.indexDB.hasTransaction("tx_missing_sig")
    check not n.indexDB.hasTransaction("tx_bad_sig")
    check not n.mempool.hasTransaction("tx_missing_pk")
    check not n.mempool.hasTransaction("tx_missing_sig")
    check not n.mempool.hasTransaction("tx_bad_sig")
    check n.vm.state.getBalance(sender) == 500
    check n.accountState.getBalance(sender) == 500

  test "VM execution failure evicts transaction from mempool and preserves storage":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    cfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(cfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)

    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)

    # Sender has only 50 balance, attempts to transfer 100
    n.vm.state.setBalance(sender, 50)
    discard n.persistAccountState()

    let tx = signedTransaction(Transaction(
      id: "tx_overdraft",
      receiver: "recipient_3",
      amount: 100,
      fee: 10,
      nonce: 1
    ), keys)

    let result = n.submitAndExecuteTransaction(tx)
    check not result.ok
    check result.error == composition.txStageInsufficientBalance

    # Transaction must be evicted from mempool on VM failure
    check not n.mempool.hasTransaction(tx.id)
    check n.mempool.transactionCount() == 0

    # No block should be committed and no index added
    check n.blockchainDB.getCurrentHeight() == 0
    check not n.indexDB.hasTransaction(tx.id)

    # Balance must remain unchanged
    check n.vm.state.getBalance(sender) == 50
    check n.accountState.getBalance(sender) == 50

  test "Duplicate transaction is rejected before block inclusion or VM execution":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    cfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(cfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)

    let keys = generateKeyPair()
    let tx = signedTransaction(Transaction(
      id: "tx_duplicate_test",
      receiver: "recipient_4",
      amount: 10,
      fee: 5,
      nonce: 1
    ), keys)

    # Add directly to mempool first
    check n.mempool.addTransaction(tx).ok

    # Now attempt submitAndExecuteTransaction with the same transaction
    let result = n.submitAndExecuteTransaction(tx)
    check not result.ok
    check result.error == composition.txStageMempoolDuplicate

    # Block height must remain 0
    check n.blockchainDB.getCurrentHeight() == 0


  test "Canonical Block and BlockHeight are unambiguous across all subsystem imports":
    # Proves no ambiguity between blockchain_db, index_db, block_propagation, and common/types
    let h: BlockHeight = 10
    let hId: BlockId = "blk_unified_10"
    let d: BlockData = "unified block data"
    let prev: BlockHash = "prev_blk_09"
    
    let blk: Block = newBlock(hId, h, d, prev)
    check blk.id == hId
    check blk.height == h
    check blk.data == d
    check blk.previousHash == prev
    
    let net = newNetwork()
    let status = propagateBlock(net, blk)
    check status.result == Success
    
    let chainDB = newBlockchainDB()
    check chainDB.addBlock(blk) == true
    check chainDB.getCurrentHeight() == h
    
    let idxDB = newIndexDB()
    let txId: TransactionId = "tx_unified_101"
    check idxDB.indexTransaction(txId, h, 0) == true
    check idxDB.getBlockTransactions(h) == @[txId]

  test "Storage facade boundary integration with canonical lifecycle and backward compatibility":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    cfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(cfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)

    # Initial facade state
    check n.blockchainStore != nil
    check n.indexStore != nil
    check n.blockchainStore.getCurrentHeight() == 0
    check n.blockchainStore.getBlockCount() == 0
    check n.indexStore.getTransactionCount() == 0

    # Backward compatibility accessors expose the facade
    check n.blockchainDB.getCurrentHeight() == 0
    check n.indexDB.getTransactionCount() == 0

    let keys = generateKeyPair()
    let sender = addressFromPublicKey(keys.publicKey)
    let receiver = "facade_recipient"

    n.vm.state.setBalance(sender, 500)
    discard n.persistAccountState()

    let tx = signedTransaction(Transaction(
      id: "tx_store_facade_001",
      receiver: receiver,
      amount: 150,
      fee: 5,
      nonce: 1
    ), keys)

    # Execute lifecycle: submit -> mempool -> block -> VM -> storage/index
    let result = n.submitAndExecuteTransaction(tx)
    check result.ok
    check result.value.blockHeight == 1
    check result.value.blockHash == "blk_1"
    check result.value.txId == tx.id

    # Verify directly on BlockchainStore facade
    check n.blockchainStore.getCurrentHeight() == 1
    check n.blockchainStore.getBlockCount() == 1
    check n.blockchainStore.hasBlock(1)
    check n.blockchainStore.hasBlockWithHash("blk_1")

    let blkOpt = n.blockchainStore.getBlock(1)
    check blkOpt.isSome
    let blk = blkOpt.get
    check blk.height == 1
    check blk.id == "blk_1"
    check blk.hash == "blk_1"
    check blk.data == "tx:" & tx.id

    let latestOpt = n.blockchainStore.getLatestBlock()
    check latestOpt.isSome
    check latestOpt.get.height == 1
    check latestOpt.get.hash == "blk_1"

    # Verify directly on IndexStore facade
    check n.indexStore.hasTransaction(tx.id)
    check n.indexStore.isBlockIndexed(1)
    check n.indexStore.getTransactionCount() == 1
    check n.indexStore.getIndexedBlockCount() == 1

    let locOpt = n.indexStore.getTransactionLocation(tx.id)
    check locOpt.isSome
    check locOpt.get.blockHeight == 1
    check locOpt.get.transactionIndex == 0

    let txs = n.indexStore.getBlockTransactions(1)
    check txs == @[tx.id]

    # Verify backward compatibility accessors see identical state
    check n.blockchainDB.getCurrentHeight() == 1
    check n.blockchainDB.getLatestBlock().isSome
    check n.blockchainDB.getLatestBlock().get.hash == "blk_1"
    check n.indexDB.hasTransaction(tx.id)
    check n.indexDB.getBlockTransactions(1) == @[tx.id]

    # Verify swappable boundary: replace with a wrapped facade tracking invocations
    var customAddBlockCalled = false
    var customIndexCalled = false
    let baseMemStore = newMemoryBlockchainStore()
    let baseIdxStore = newMemoryIndexStore()

    let customChainStore = BlockchainStore(
      name: "CustomTrackingBlockchainStore",
      addBlockImpl: proc(b: Block): bool =
        customAddBlockCalled = true
        baseMemStore.addBlock(b),
      getBlockImpl: proc(h: BlockHeight): Option[Block] = baseMemStore.getBlock(h),
      getBlockByHashImpl: proc(h: BlockHash): Option[Block] = baseMemStore.getBlockByHash(h),
      hasBlockImpl: proc(h: BlockHeight): bool = baseMemStore.hasBlock(h),
      hasBlockWithHashImpl: proc(h: BlockHash): bool = baseMemStore.hasBlockWithHash(h),
      getCurrentHeightImpl: proc(): BlockHeight = baseMemStore.getCurrentHeight(),
      getLatestBlockImpl: proc(): Option[Block] = baseMemStore.getLatestBlock(),
      getBlockCountImpl: proc(): int = baseMemStore.getBlockCount(),
      getBlockRangeImpl: proc(s, e: BlockHeight): seq[Block] = baseMemStore.getBlockRange(s, e),
      rawDBImpl: proc(): BlockchainDB = baseMemStore.rawDB()
    )

    let customIndexStore = IndexStore(
      name: "CustomTrackingIndexStore",
      indexTxImpl: proc(t: TransactionId, h: BlockHeight, i: int): bool =
        customIndexCalled = true
        baseIdxStore.indexTransaction(t, h, i),
      getTxLocImpl: proc(t: TransactionId): Option[TransactionLocation] = baseIdxStore.getTransactionLocation(t),
      getBlockTxsImpl: proc(h: BlockHeight): seq[TransactionId] = baseIdxStore.getBlockTransactions(h),
      hasTxImpl: proc(t: TransactionId): bool = baseIdxStore.hasTransaction(t),
      removeTxImpl: proc(t: TransactionId): bool = baseIdxStore.removeTransaction(t),
      isBlockIndexedImpl: proc(h: BlockHeight): bool = baseIdxStore.isBlockIndexed(h),
      getIndexedBlockCountImpl: proc(): int = baseIdxStore.getIndexedBlockCount(),
      getTxCountImpl: proc(): int = baseIdxStore.getTransactionCount(),
      clearImpl: proc() = baseIdxStore.clear(),
      rawDBImpl: proc(): IndexDB = baseIdxStore.rawDB()
    )

    n.blockchainStore = customChainStore
    n.indexStore = customIndexStore

    let tx2 = signedTransaction(Transaction(
      id: "tx_store_facade_002",
      receiver: receiver,
      amount: 50,
      fee: 5,
      nonce: 2
    ), keys)

    let result2 = n.submitAndExecuteTransaction(tx2)
    check result2.ok
    check customAddBlockCalled == true
    check customIndexCalled == true
    check n.blockchainStore.getCurrentHeight() == 1
    check n.indexStore.hasTransaction(tx2.id)
