import unittest
import ../../src/common/types
import ../../src/common/config
import ../../src/cli
import ../../src/core_engine/state_management
import ../../src/cryptography/key_management
import ../../src/cryptography/keystore
import ../../src/network/mempool
import ../../src/storage/blockchain_db
import std/[os, json, options, strutils]

suite "CLI Tests":

  setup:
    discard initializeBlockchainNode()

  test "Node initialization":
    check initializeBlockchainNode().ok

  test "Account creation and balance checking":
    let testAddress = "test_addr"
    node.accountState.setBalance(testAddress, 500)

    check node.accountState.getBalance(testAddress) == 500
    check node.accountState.getNonce(testAddress) == 0

  test "Transfer functionality":
    let fromAddr = "alice"
    let toAddr = "bob"

    node.accountState.setBalance(fromAddr, 1000)
    node.accountState.setBalance(toAddr, 100)

    let initialFromBalance = node.accountState.getBalance(fromAddr)
    let initialToBalance = node.accountState.getBalance(toAddr)

    let success = node.accountState.decreaseBalance(fromAddr, 200)
    check success == true
    node.accountState.increaseBalance(toAddr, 200)

    check node.accountState.getBalance(fromAddr) == initialFromBalance - 200
    check node.accountState.getBalance(toAddr) == initialToBalance + 200

  test "Block operations":
    let success = node.blockchainDB.addBlock(1, "test block data", "hash123", 1000)
    check success == true
    check node.blockchainDB.getCurrentHeight() == 1

    let stored = node.blockchainDB.getBlock(1)
    check stored.isSome
    check stored.get.data == "test block data"

  test "Mempool operations":
    let keys = generateKeyPair()
    let tx = signedTransaction(Transaction(
      id: "test_tx",
      receiver: "bob",
      amount: 100,
      fee: 10,
      nonce: 1
    ), keys)

    check node.mempool.addTransaction(tx).ok
    check node.mempool.hasTransaction("test_tx") == true
    check node.mempool.transactionCount() == 1

  test "createAccount writes the keystore and omits the private key from JSON":
    let dir = getTempDir() / "nimnode-cli-keystore"
    if dirExists(dir):
      removeDir(dir)
    cliConfig.dataDir = dir
    cliConfig.jsonOutput = false
    try:
      let created = createAccount()
      check created.ok
      let loaded = loadKeystore(dir, created.value.address)
      check loaded.ok
      let raw = $createdAccountJson(created.value, 0)
      check not createdAccountJson(created.value, 0).hasKey("private_key")
      check raw.find("private_key") == -1
      check raw.find(loaded.value.privateKey) == -1
      check loaded.value.privateKey.len > 0
      check "private_key=" in readFile(created.value.keystorePath)
    finally:
      cliConfig.dataDir = DefaultDataDir
      cliConfig.jsonOutput = false
      if dirExists(dir):
        removeDir(dir)

  test "config precedence is CLI over environment over defaults":
    let defaults = resolveConfigFrom(CliOverrides(), "", "")
    check defaults.dataDir == DefaultDataDir
    check defaults.verbose == false
    check defaults.jsonOutput == false

    let fromEnv = resolveConfigFrom(CliOverrides(), "env-data", "true")
    check fromEnv.dataDir == "env-data"
    check fromEnv.verbose == true

    let cliWins = resolveConfigFrom(
      CliOverrides(verbose: true, dataDir: "cli-data", dataDirProvided: true, jsonOutput: true),
      "env-data", "false")
    check cliWins.dataDir == "cli-data"
    check cliWins.verbose == true
    check cliWins.jsonOutput == true

    let envStands = resolveConfigFrom(CliOverrides(), "env-data", "on")
    check envStands.verbose == true

    let envOff = resolveConfigFrom(CliOverrides(), "", "0")
    check envOff.verbose == false
