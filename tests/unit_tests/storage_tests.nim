import unittest
import ../../src/storage/blockchain_db
import ../../src/storage/state_db
import ../../src/storage/index_db
import ../../src/storage/blockchain_store
import ../../src/storage/index_store
import ../../src/storage/account_store
import ../../src/core_engine/state_management
import ../../src/common/[config, types]
import ../../src/cli
import ../../src/cryptography/keystore
import std/[options, os, strutils]

suite "Storage Layer Tests":

  test "BlockchainDB: block storage and retrieval":
    let chainDB = newBlockchainDB()
    check chainDB.addBlock(1, "BlockData1", "hash1", 1000) == true
    check chainDB.addBlock(1, "BlockDataDuplicate", "hash2", 2000) == false  # duplicates prevented
    
    let stored = chainDB.getBlock(1)
    check stored.isSome
    check stored.get.data == "BlockData1"
    
    let nonExistent = chainDB.getBlock(2)
    check nonExistent.isNone

  test "GlobalStateStore: state update and retrieval":
    let stateDB = newGlobalStateStore()
    check stateDB.setState("account1", 100)
    check stateDB.getState("account1") == 100
    check stateDB.getState("unknown") == 0  # default value when not found
    check stateDB.hasState("account1") == true
    check stateDB.deleteState("account1") == true
    check stateDB.hasState("account1") == false

  test "IndexDB: indexing transactions":
    let indexDB = newIndexDB()
    check indexDB.indexTransaction("tx123", 10, 0) == true
    
    let location = indexDB.getTransactionLocation("tx123")
    check location.isSome
    check location.get.blockHeight == 10
    
    let nonExistent = indexDB.getTransactionLocation("tx999")
    check nonExistent.isNone
    
    # Test block transaction listing
    discard indexDB.indexTransaction("tx124", 10, 1)
    let blockTxs = indexDB.getBlockTransactions(10)
    check blockTxs.len == 2

proc tempStoreDir(name: string): string =
  result = getTempDir() / "nimnode-account-store" / name
  if dirExists(result):
    removeDir(result)
  createDir(result)

proc removeStoreDir(dir: string) =
  if dirExists(dir):
    removeDir(dir)

suite "Account Store Tests":

  test "save and reload balances and nonces":
    let dir = tempStoreDir("reload")
    try:
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.fresh
      check not fileExists(dir / "accounts.json")
      var state = opened.value.store.loadAccounts().value
      state.setBalance("alice", 50)
      discard state.incrementNonce("alice")
      state.setBalance("bob", 7)
      check opened.value.store.saveAccounts(state).ok
      check fileExists(dir / "accounts.json")
      check not fileExists(dir / "accounts.json.tmp")
      let again = openAccountStore(dir)
      check again.ok
      check not again.value.fresh
      let loaded = again.value.store.loadAccounts().value
      check loaded.getBalance("alice") == 50
      check loaded.getNonce("alice") == 1
      check loaded.getBalance("bob") == 7
      discard again.value.store.closeAccountStore()
      discard opened.value.store.closeAccountStore()
    finally:
      removeStoreDir(dir)

  test "restart through initializeBlockchainNode keeps balances":
    let dir = tempStoreDir("restart")
    let previous = cliConfig
    try:
      cliConfig.dataDir = dir
      check initializeBlockchainNode().ok
      check node.vm.state.getBalance("genesis") == 1000000
      node.vm.state.setBalance("alice", 42)
      check persistAccountState().ok
      check initializeBlockchainNode().ok
      check node.vm.state.getBalance("alice") == 42
      check node.vm.state.getBalance("genesis") == 1000000
    finally:
      cliConfig = previous
      removeStoreDir(dir)

  test "existing genesis balance is not reseeded":
    let dir = tempStoreDir("genesis")
    let previous = cliConfig
    try:
      var state = newStateDB()
      state.setBalance("genesis", 7)
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.fresh
      check opened.value.store.saveAccounts(state).ok
      discard opened.value.store.closeAccountStore()
      cliConfig.dataDir = dir
      check initializeBlockchainNode().ok
      check node.vm.state.getBalance("genesis") == 7
    finally:
      cliConfig = previous
      removeStoreDir(dir)

  test "empty account list is not reseeded":
    let dir = tempStoreDir("empty-list")
    let previous = cliConfig
    try:
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.store.saveAccounts(newStateDB()).ok
      discard opened.value.store.closeAccountStore()
      cliConfig.dataDir = dir
      check initializeBlockchainNode().ok
      check node.vm.state.getBalance("genesis") == 0
      check node.vm.state.accountCount() == 0
    finally:
      cliConfig = previous
      removeStoreDir(dir)

  test "missing snapshot stays missing until save":
    let dir = tempStoreDir("missing")
    try:
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.fresh
      check not fileExists(dir / "accounts.json")
      discard opened.value.store.closeAccountStore()
    finally:
      removeStoreDir(dir)

  test "empty malformed version and checksum files are left unchanged":
    let dir = tempStoreDir("bad-files")
    try:
      let emptyPath = dir / "accounts.json"
      writeFile(emptyPath, " \n")
      let emptyBytes = readFile(emptyPath)
      let emptyOpen = openAccountStore(dir)
      check not emptyOpen.ok
      check emptyOpen.error == asEmpty
      check readFile(emptyPath) == emptyBytes

      writeFile(emptyPath, "{")
      let malformedBytes = readFile(emptyPath)
      let malformed = openAccountStore(dir)
      check not malformed.ok
      check malformed.error == asMalformed
      check readFile(emptyPath) == malformedBytes

      let wrongVersion = """{"format":"nim-node-accounts","version":99,"accounts":[],"checksum":"00"}"""
      writeFile(emptyPath, wrongVersion)
      let versionOpen = openAccountStore(dir)
      check not versionOpen.ok
      check versionOpen.error == asVersionMismatch
      check readFile(emptyPath) == wrongVersion
    finally:
      removeStoreDir(dir)

  test "checksum mismatch leaves the snapshot unchanged":
    let dir = tempStoreDir("checksum")
    try:
      var state = newStateDB()
      state.setBalance("alice", 3)
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.store.saveAccounts(state).ok
      discard opened.value.store.closeAccountStore()
      let path = dir / "accounts.json"
      let original = readFile(path)
      let marker = """"checksum":""""
      let start = original.find(marker)
      check start >= 0
      let valueStart = start + marker.len
      let valueEnd = original.find('"', valueStart)
      check valueEnd > valueStart
      let corrupted = original[0 ..< valueStart] & "00" & original[valueEnd .. ^1]
      writeFile(path, corrupted)
      let failed = openAccountStore(dir)
      check not failed.ok
      check failed.error == asChecksumMismatch
      check readFile(path) == corrupted
    finally:
      removeStoreDir(dir)

  test "duplicate address is malformed and is not overwritten":
    let dir = tempStoreDir("duplicate")
    try:
      let path = dir / "accounts.json"
      let body = """{"format":"nim-node-accounts","version":1,"accounts":[{"address":"a","balance":1,"nonce":0},{"address":"a","balance":2,"nonce":0}],"checksum":"00"}"""
      writeFile(path, body)
      let opened = openAccountStore(dir)
      check not opened.ok
      check opened.error == asMalformed
      check readFile(path) == body
    finally:
      removeStoreDir(dir)

  test "memory stores do not share state or create a snapshot":
    let snapshotBefore = fileExists("accounts.json")
    let first = openAccountStore(MemoryDataDir)
    let second = openAccountStore(MemoryDataDir)
    check first.ok
    check second.ok
    check first.value.fresh
    check second.value.fresh
    var state = first.value.store.loadAccounts().value
    state.setBalance("alice", 9)
    check first.value.store.saveAccounts(state).ok
    check first.value.store.loadAccounts().value.getBalance("alice") == 9
    check second.value.store.loadAccounts().value.getBalance("alice") == 0
    check fileExists("accounts.json") == snapshotBefore
    check not dirExists(MemoryDataDir)
    let saved = saveKeystore(MemoryDataDir, "abc", "pk", "sk")
    check not saved.ok
    check saved.error == ksUnsafePath
    check not dirExists(MemoryDataDir)
    let loaded = loadKeystore(MemoryDataDir, "abc")
    check not loaded.ok
    check loaded.error == ksUnsafePath

  test "save refuses an empty address without replacing the snapshot":
    let dir = tempStoreDir("empty-address")
    try:
      var good = newStateDB()
      good.setBalance("alice", 3)
      let opened = openAccountStore(dir)
      check opened.ok
      check opened.value.store.saveAccounts(good).ok
      let path = dir / "accounts.json"
      let original = readFile(path)
      var bad = good
      bad.setBalance("", 1)
      let saved = opened.value.store.saveAccounts(bad)
      check not saved.ok
      check saved.error == asMalformed
      check readFile(path) == original
      let again = openAccountStore(dir)
      check again.ok
      let loaded = again.value.store.loadAccounts().value
      check loaded.getBalance("alice") == 3
      check not loaded.hasAccount("")
      discard again.value.store.closeAccountStore()
      discard opened.value.store.closeAccountStore()
    finally:
      removeStoreDir(dir)

  test "failed initialization does not replace a bad snapshot":
    let dir = tempStoreDir("init-keeps-bad")
    let previous = cliConfig
    try:
      let path = dir / "accounts.json"
      writeFile(path, "{")
      cliConfig.dataDir = dir
      check not initializeBlockchainNode().ok
      check readFile(path) == "{"
    finally:
      cliConfig = previous
      removeStoreDir(dir)

  test "repeated saves leave a consistent reloadable snapshot":
    let dir = tempStoreDir("repeated-save")
    try:
      let opened = openAccountStore(dir)
      check opened.ok
      var state = opened.value.store.loadAccounts().value
      for i in 1..5:
        state.setBalance("alice", Balance(i * 10))
        discard state.incrementNonce("alice")
        check opened.value.store.saveAccounts(state).ok
        check not fileExists(dir / "accounts.json.tmp")
      discard opened.value.store.closeAccountStore()
      let again = openAccountStore(dir)
      check again.ok
      let loaded = again.value.store.loadAccounts().value
      check loaded.getBalance("alice") == 50
      check loaded.getNonce("alice") == 5
      discard again.value.store.closeAccountStore()
    finally:
      removeStoreDir(dir)


  test "canonical Block and BlockHeight domain types work seamlessly with BlockchainDB":
    let chainDB = newBlockchainDB()
    let h: BlockHeight = 5
    let canonicalBlk = newBlock("blk_canon_5", h, "canonical block payload", "prev_hash_4")
    
    # Store using canonical Block overload
    check chainDB.addBlock(canonicalBlk) == true
    check chainDB.getCurrentHeight() == h
    check chainDB.hasBlock(h)
    check chainDB.hasBlockWithHash("blk_canon_5")

    # Retrieve StoredBlock DTO
    let storedOpt = chainDB.getBlock(h)
    check storedOpt.isSome
    let stored = storedOpt.get
    check stored.height == h
    check stored.data == "canonical block payload"
    check stored.hash == "blk_canon_5"

    # Convert StoredBlock to canonical Block
    let reconverted = stored.toBlock("prev_hash_4")
    check reconverted.id == canonicalBlk.id
    check reconverted.height == canonicalBlk.height
    check reconverted.data == canonicalBlk.data
    check reconverted.timestamp == canonicalBlk.timestamp
    check reconverted.previousHash == "prev_hash_4"

    # Convert Block to StoredBlock DTO
    let dto = canonicalBlk.toStoredBlock()
    check dto.height == canonicalBlk.height
    check dto.data == canonicalBlk.data
    check dto.hash == canonicalBlk.id
    check dto.timestamp == canonicalBlk.timestamp

  test "canonical types work across IndexDB without type collisions":
    let indexDB = newIndexDB()
    let h: BlockHeight = 42
    let txId: TransactionId = "tx_canonical_42"
    check indexDB.indexTransaction(txId, h, 0) == true
    check indexDB.hasTransaction(txId)
    check indexDB.isBlockIndexed(h)
    
    let loc = indexDB.getTransactionLocation(txId)
    check loc.isSome
    check loc.get.blockHeight == h
    check loc.get.transactionIndex == 0
    
    let txs = indexDB.getBlockTransactions(h)
    check txs == @[txId]

  test "MemoryBlockchainStore: block addition, retrieval, height, and latest block":
    let memStore = newMemoryBlockchainStore()
    check memStore.getCurrentHeight() == 0
    check memStore.getBlockCount() == 0
    check memStore.getLatestBlock().isNone

    let b1 = newBlock("hash_1", 1, "block one data")
    check memStore.addBlock(b1) == true
    # Duplicate block at same height rejected
    check memStore.addBlock(b1) == false
    check memStore.getCurrentHeight() == 1
    check memStore.getBlockCount() == 1
    check memStore.hasBlock(1)
    check memStore.hasBlockWithHash("hash_1")
    check not memStore.hasBlock(2)
    check not memStore.hasBlockWithHash("unknown_hash")

    let b1Retrieved = memStore.getBlock(1)
    check b1Retrieved.isSome
    check b1Retrieved.get.id == "hash_1"
    check b1Retrieved.get.hash == "hash_1"
    check b1Retrieved.get.height == 1
    check b1Retrieved.get.data == "block one data"

    let b1ByHash = memStore.getBlockByHash("hash_1")
    check b1ByHash.isSome
    check b1ByHash.get.id == "hash_1"

    # Add second block using primitive overload
    check memStore.addBlock(2, "block two data", "hash_2", 1000) == true
    check memStore.getCurrentHeight() == 2
    check memStore.getBlockCount() == 2

    let latest = memStore.getLatestBlock()
    check latest.isSome
    check latest.get.height == 2
    check latest.get.hash == "hash_2"
    check latest.get.data == "block two data"

    # Range retrieval
    let rangeBlocks = memStore.getBlockRange(1, 2)
    check rangeBlocks.len == 2
    check rangeBlocks[0].height == 1
    check rangeBlocks[1].height == 2

    # Storage DTO access and rawDB
    let storedDto = memStore.getStoredBlock(1)
    check storedDto.isSome
    check storedDto.get.hash == "hash_1"
    check memStore.rawDB() != nil

    # Interoperability via BlockchainStore facade
    let facade: BlockchainStore = memStore
    check facade.getCurrentHeight() == 2
    check facade.getBlockCount() == 2
    let facadeLatest = facade.getLatestBlock()
    check facadeLatest.isSome
    check facadeLatest.get.height == 2
    check facade.hasBlock(1)
    check facade.hasBlockWithHash("hash_2")

    let b3 = newBlock("hash_3", 3, "block three via facade")
    check facade.addBlock(b3) == true
    check facade.getCurrentHeight() == 3
    check memStore.getCurrentHeight() == 3

  test "MemoryIndexStore: transaction indexing, query location, block txs, and removal":
    let memStore = newMemoryIndexStore()
    check memStore.getIndexedBlockCount() == 0
    check memStore.getTransactionCount() == 0

    let txA: TransactionId = "tx_alpha"
    let txB: TransactionId = "tx_beta"
    let h1: BlockHeight = 10
    let h2: BlockHeight = 20

    check memStore.indexTransaction(txA, h1, 0) == true
    # Duplicate transaction ID is rejected
    check memStore.indexTransaction(txA, h1, 1) == false
    check memStore.hasTransaction(txA)
    check not memStore.hasTransaction(txB)
    check memStore.isBlockIndexed(h1)
    check not memStore.isBlockIndexed(h2)

    let locA = memStore.getTransactionLocation(txA)
    check locA.isSome
    check locA.get.blockHeight == h1
    check locA.get.transactionIndex == 0

    check memStore.indexTransaction(txB, h1, 1) == true
    check memStore.getTransactionCount() == 2
    check memStore.getIndexedBlockCount() == 1

    let block10Txs = memStore.getBlockTransactions(h1)
    check block10Txs.len == 2
    check block10Txs == @[txA, txB]

    # Remove one transaction
    check memStore.removeTransaction(txA) == true
    check not memStore.hasTransaction(txA)
    check memStore.getTransactionLocation(txA).isNone
    check memStore.getBlockTransactions(h1) == @[txB]
    check memStore.isBlockIndexed(h1) # still has txB

    # Removing non-existent returns false
    check memStore.removeTransaction(txA) == false

    # Remove remaining transaction in block 10
    check memStore.removeTransaction(txB) == true
    check memStore.getBlockTransactions(h1).len == 0
    check not memStore.isBlockIndexed(h1)
    check memStore.getIndexedBlockCount() == 0

    # Interoperability via IndexStore facade
    let facade: IndexStore = memStore
    let txC: TransactionId = "tx_gamma"
    check facade.indexTransaction(txC, h2, 0) == true
    check facade.hasTransaction(txC)
    check facade.isBlockIndexed(h2)
    let locC = facade.getTransactionLocation(txC)
    check locC.isSome
    check locC.get.blockHeight == h2
    check facade.getBlockTransactions(h2) == @[txC]

    # Clear through facade
    facade.clear()
    check facade.getTransactionCount() == 0
    check facade.getIndexedBlockCount() == 0
    check not facade.hasTransaction(txC)
