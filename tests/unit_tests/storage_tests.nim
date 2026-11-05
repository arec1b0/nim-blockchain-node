import unittest
import ../../src/storage/blockchain_db
import ../../src/storage/state_db
import ../../src/storage/index_db
import ../../src/storage/account_store
import ../../src/core_engine/state_management
import ../../src/common/config
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
