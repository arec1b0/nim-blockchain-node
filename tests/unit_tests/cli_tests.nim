import unittest
import ../../src/common/types
import ../../src/common/config
import ../../src/cli
import ../../src/cli/[cli_parser, cli_service, cli_handlers]
import ../../src/node as composition
import ../../src/core_engine/state_management
import ../../src/cryptography/key_management
import ../../src/cryptography/keystore
import ../../src/cryptography/signature_verification
import ../../src/network/mempool
import ../../src/storage/blockchain_db
import std/[os, json, options, strutils]

suite "CLI Tests":

  setup:
    cliConfig.dataDir = MemoryDataDir
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
      cliConfig.dataDir = MemoryDataDir
      cliConfig.jsonOutput = false
      if dirExists(dir):
        removeDir(dir)
      discard initializeBlockchainNode()

  test "createAccount writes no key file when the snapshot cannot be saved":
    let dir = getTempDir() / "nimnode-cli-orphan"
    if dirExists(dir):
      removeDir(dir)
    if fileExists(dir):
      removeFile(dir)
    createDir(dir)
    let previousJson = cliConfig.jsonOutput
    cliConfig.dataDir = dir
    cliConfig.jsonOutput = false
    try:
      check initializeBlockchainNode().ok
      removeDir(dir)
      writeFile(dir, "not-a-directory")
      let created = createAccount()
      check not created.ok
      check fileExists(dir)
      check not dirExists(dir)
    finally:
      cliConfig.dataDir = MemoryDataDir
      cliConfig.jsonOutput = previousJson
      if dirExists(dir):
        removeDir(dir)
      elif fileExists(dir):
        removeFile(dir)
      discard initializeBlockchainNode()

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

  test "composition root initializes node with centralized defaults":
    let defaults = defaultNodeConfig()
    check defaults.gasLimit == DefaultGasLimit
    check defaults.mempoolCapacity == DefaultMempoolCapacity
    check defaults.maxPeers == DefaultMaxPeers
    check defaults.validators.len == 2
    check defaults.storageBackend == backendFile

    var memCfg = defaultNodeConfig()
    memCfg.dataDir = MemoryDataDir
    memCfg.storageBackend = backendMemory
    let nodeRes = composition.newBlockchainNode(memCfg)
    check nodeRes.ok
    let n = nodeRes.value
    defer: discard composition.close(n)
    check n.config.gasLimit == DefaultGasLimit
    check n.vm.gasLimit == DefaultGasLimit
    check n.mempool.maxSize == DefaultMempoolCapacity
    check n.network.maxPeers == DefaultMaxPeers
    check n.consensus.activeValidatorCount() == 2

  test "equivalent inputs produce equivalent runtime configuration from both entry points":
    let overrides = CliOverrides(verbose: true, dataDir: MemoryDataDir, dataDirProvided: true)
    let cfgFromMain = resolveConfigFrom(overrides, "", "")
    let cfgFromCli = resolveConfigFrom(overrides, "", "")
    check cfgFromMain.dataDir == cfgFromCli.dataDir
    check cfgFromMain.verbose == cfgFromCli.verbose
    check cfgFromMain.gasLimit == cfgFromCli.gasLimit
    check cfgFromMain.mempoolCapacity == cfgFromCli.mempoolCapacity
    check cfgFromMain.maxPeers == cfgFromCli.maxPeers
    check cfgFromMain.storageBackend == cfgFromCli.storageBackend

    let mainNodeRes = composition.newBlockchainNode(cfgFromMain)
    let cliNodeRes = composition.newBlockchainNode(cfgFromCli)
    check mainNodeRes.ok
    check cliNodeRes.ok
    let mainNode = mainNodeRes.value
    let cliNode = cliNodeRes.value
    defer:
      discard composition.close(mainNode)
      discard composition.close(cliNode)
    check mainNode.config.gasLimit == cliNode.config.gasLimit
    check mainNode.vm.gasLimit == cliNode.vm.gasLimit
    check mainNode.mempool.maxSize == cliNode.mempool.maxSize
    check mainNode.network.maxPeers == cliNode.network.maxPeers
    check mainNode.consensus.activeValidatorCount() == cliNode.consensus.activeValidatorCount()

  test "transferFunds executes full lifecycle: mempool admission, block creation, VM apply, and index update":
    let dir = getTempDir() / "nimnode-cli-transfer-lifecycle"
    if dirExists(dir):
      removeDir(dir)
    cliConfig.dataDir = dir
    cliConfig.jsonOutput = false
    try:
      check initializeBlockchainNode().ok
      let created = createAccount()
      check created.ok
      let sender = created.value.address

      # Fund sender
      node.vm.state.setBalance(sender, 1000)
      check persistAccountState().ok

      check node.blockchainDB.getCurrentHeight() == 0

      # Execute transfer
      let status = transferFunds(sender, "bob_recipient", 300, 10)
      check status.ok

      # Verify lifecycle outputs: block committed, index updated, mempool cleared
      check node.blockchainDB.getCurrentHeight() == 1
      let latestBlock = node.blockchainDB.getLatestBlock()
      check latestBlock.isSome
      check latestBlock.get.height == 1

      check node.indexDB.getBlockTransactions(1).len == 1
      check node.mempool.transactionCount() == 0

      # Verify balances
      check node.vm.state.getBalance(sender) == 690   # 1000 - 300 - 10
      check node.vm.state.getBalance("bob_recipient") == 300
      check node.accountState.getBalance(sender) == 690
      check node.accountState.getBalance("bob_recipient") == 300
    finally:
      cliConfig.dataDir = MemoryDataDir
      if dirExists(dir):
        removeDir(dir)
      discard initializeBlockchainNode()

  test "transferFunds rejects transactions with insufficient balance and preserves storage":
    let dir = getTempDir() / "nimnode-cli-transfer-overdraft"
    if dirExists(dir):
      removeDir(dir)
    cliConfig.dataDir = dir
    cliConfig.jsonOutput = false
    try:
      check initializeBlockchainNode().ok
      let created = createAccount()
      check created.ok
      let sender = created.value.address

      # Sender has 0 balance, attempts to transfer 100
      let status = transferFunds(sender, "bob_recipient", 100, 10)
      check not status.ok
      check status.error == trInsufficientBalance

      # Block and index must be untouched, mempool must be empty
      check node.blockchainDB.getCurrentHeight() == 0
      check node.mempool.transactionCount() == 0
      check node.vm.state.getBalance(sender) == 0
    finally:
      cliConfig.dataDir = MemoryDataDir
      if dirExists(dir):
        removeDir(dir)
      discard initializeBlockchainNode()

  test "transferFunds rejects missing keystore before VM execution":
    let dir = getTempDir() / "nimnode-cli-transfer-nokeys"
    if dirExists(dir):
      removeDir(dir)
    cliConfig.dataDir = dir
    cliConfig.jsonOutput = false
    try:
      check initializeBlockchainNode().ok
      let status = transferFunds("A1B2C3D4", "bob_recipient", 100, 10)
      check not status.ok
      check status.error == trKeystoreMissing
      check node.blockchainDB.getCurrentHeight() == 0
      check node.mempool.transactionCount() == 0
    finally:
      cliConfig.dataDir = MemoryDataDir
      if dirExists(dir):
        removeDir(dir)
      discard initializeBlockchainNode()

  test "cli_parser: commandArguments filters options and captures positional arguments":
    let params1 = @["-j", "-v", "--data-dir", "custom_dir", "account", "transfer", "alice", "bob", "50", "5"]
    check commandArguments(params1) == @["account", "transfer", "alice", "bob", "50", "5"]

    let params2 = @["--data-dir=custom_dir", "-j", "node", "status"]
    check commandArguments(params2) == @["node", "status"]

    let params3 = @["-h", "help"]
    check commandArguments(params3) == @["help"]

    let emptyParams: seq[string] = @[]
    check commandArguments(emptyParams).len == 0

  test "cli_parser: parseNonNegative validates transfer amount and fee tokens":
    let validBoth = parseNonNegative(@["account", "transfer", "alice", "bob", "250", "15"])
    check validBoth.ok
    check validBoth.value.amount == 250
    check validBoth.value.fee == 15

    let validDefaultFee = parseNonNegative(@["account", "transfer", "alice", "bob", "300"])
    check validDefaultFee.ok
    check validDefaultFee.value.amount == 300
    check validDefaultFee.value.fee == 10

    let badAmount = parseNonNegative(@["account", "transfer", "alice", "bob", "not-a-number"])
    check not badAmount.ok
    check "amount and fee must be integers" in badAmount.error

    let badFee = parseNonNegative(@["account", "transfer", "alice", "bob", "100", "not-a-fee"])
    check not badFee.ok
    check "amount and fee must be integers" in badFee.error

    let tooFew = parseNonNegative(@["account", "transfer", "alice"])
    check not tooFew.ok

  test "cli_parser: parseBlockHeight parses valid and rejects invalid heights":
    let validZero = parseBlockHeight("0")
    check validZero.ok
    check validZero.value == 0

    let validHigh = parseBlockHeight("42")
    check validHigh.ok
    check validHigh.value == 42

    let negative = parseBlockHeight("-5")
    check not negative.ok
    check "non-negative" in negative.error

    let nonInt = parseBlockHeight("abc")
    check not nonInt.ok
    check "must be an integer" in nonInt.error

  test "cli_parser: parseCliOptions parses options and detects missing or invalid values":
    let opts1 = parseCliOptions(@["-v", "-j", "-d", "custom_dir", "account", "list"])
    check opts1.verbose == true
    check opts1.jsonOutput == true
    check opts1.dataDirProvided == true
    check opts1.dataDir == "custom_dir"
    check opts1.errorMessage.len == 0

    let opts2 = parseCliOptions(@["--data-dir=my_dir", "--verbose", "node", "status"])
    check opts2.verbose == true
    check opts2.dataDirProvided == true
    check opts2.dataDir == "my_dir"

    let missingDir = parseCliOptions(@["-d"])
    check missingDir.errorMessage.len > 0
    check "data-dir requires a path" in missingDir.errorMessage

    let unknownOpt = parseCliOptions(@["--unknown-flag", "node"])
    check unknownOpt.errorMessage.len > 0
    check "unknown option" in unknownOpt.errorMessage

  test "cli_service: initCliServiceContext creates isolated context without global state":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    let ctxRes = initCliServiceContext(cfg)
    check ctxRes.ok
    let ctx = ctxRes.value
    defer: ctx.close()

    check not ctx.node.isNil
    check ctx.config.storageBackend == backendMemory

    let status = ctx.getNodeStatus()
    check status.height == 0
    check status.validators == 2
    check status.pendingTransactions == 0
    check status.peers == 0
    check status.gasLimit == DefaultGasLimit
    check status.gasUsed == 0

    let bal = ctx.getAccountBalance("genesis")
    check bal.balance == 1000000
    check bal.nonce == 0

    let accounts = ctx.listAccounts()
    check accounts.len == 1
    check accounts[0].address == "genesis"
    check accounts[0].hasKeystore == false

  test "cli_service: isolated context executes full canonical lifecycle independently of globals":
    let dir = getTempDir() / "nimnode-cli-service-lifecycle"
    if dirExists(dir):
      removeDir(dir)
    var cfg = defaultNodeConfig()
    cfg.dataDir = dir
    let ctxRes = initCliServiceContext(cfg)
    check ctxRes.ok
    let ctx = ctxRes.value
    defer:
      ctx.close()
      if dirExists(dir):
        removeDir(dir)

    # 1. Create account via service
    let created = ctx.createAccount()
    check created.ok
    let sender = created.value.address
    check fileExists(created.value.keystorePath)

    # 2. Fund sender and persist via service
    ctx.node.vm.state.setBalance(sender, 2000)
    check ctx.persistAccountState().ok
    check ctx.getAccountBalance(sender).balance == 2000

    # 3. Transfer funds via service wrapper (pure Result, no stdout requirement)
    check ctx.getCurrentHeight() == 0
    let txRes = ctx.transferFunds(sender, "isolated_recipient", 500, 20)
    check txRes.ok
    let txResult = txRes.value
    check txResult.fromBalance == 1480 # 2000 - 500 - 20
    check txResult.toBalance == 500
    check txResult.tx.sender == sender
    check txResult.tx.receiver == "isolated_recipient"

    # 4. Storage and lifecycle validation
    check ctx.getCurrentHeight() == 1
    let latest = ctx.getLatestBlock()
    check latest.isSome
    check latest.get.height == 1

    let blk1 = ctx.getBlock(1)
    check blk1.isSome
    check blk1.get.height == 1

    check ctx.getPendingTransactions().len == 0

  test "cli_handlers: describeTransfer formats distinct error messages":
    check "insufficient balance" in describeTransfer(trInsufficientBalance)
    check "no keystore file" in describeTransfer(trKeystoreMissing)
    check "fee cannot be negative" in describeTransfer(trNegativeFee)
    check "greater than zero" in describeTransfer(trZeroAmount)
    check "recipient address is empty" in describeTransfer(trEmptyReceiver)
    check "invalid signature" in describeTransfer(trInvalidSignature)

  test "cli_handlers: createdAccountJson produces compliant JSON schema omitting private keys":
    let created = CreatedAccount(
      address: "TEST_ADDR_123",
      publicKey: "TEST_PUB_KEY_456",
      keystorePath: "path/to/keystore"
    )
    let jsonNode = createdAccountJson(created, 500)
    check jsonNode["address"].getStr() == "TEST_ADDR_123"
    check jsonNode["public_key"].getStr() == "TEST_PUB_KEY_456"
    check jsonNode["balance"].getInt() == 500
    check jsonNode["keystore"].getStr() == "path/to/keystore"
    check jsonNode["keystore_format"].getStr() == "plaintext-educational"
    check jsonNode["signature_scheme"].getStr() == DemoSignatureScheme
    check not jsonNode.hasKey("private_key")
    check not jsonNode.hasKey("secret")

  test "cli_handlers: processCommand dispatches valid commands and rejects invalid ones":
    var cfg = defaultNodeConfig()
    cfg.dataDir = MemoryDataDir
    let ctxRes = initCliServiceContext(cfg)
    check ctxRes.ok
    let ctx = ctxRes.value
    defer: ctx.close()

    # Empty and help commands succeed
    check processCommand(ctx, @[]) == true
    check processCommand(ctx, @["help"]) == true
    check processCommand(ctx, @["--help"]) == true

    # Valid status and read-only commands succeed
    check processCommand(ctx, @["node", "status"]) == true
    check processCommand(ctx, @["node", "info"]) == true
    check processCommand(ctx, @["account", "balance", "genesis"]) == true
    check processCommand(ctx, @["account", "list"]) == true
    check processCommand(ctx, @["block", "latest"]) == true
    check processCommand(ctx, @["block", "height"]) == true
    check processCommand(ctx, @["transaction", "list"]) == true

    # Invalid commands and subcommands return false
    check processCommand(ctx, @["unknown_cmd"]) == false
    check processCommand(ctx, @["node", "unknown_subcmd"]) == false
    check processCommand(ctx, @["account", "unknown_subcmd"]) == false
    check processCommand(ctx, @["block", "unknown_subcmd"]) == false
    check processCommand(ctx, @["transaction", "unknown_subcmd"]) == false

    # Incomplete arguments return false
    check processCommand(ctx, @["account", "balance"]) == false
    check processCommand(ctx, @["block", "get"]) == false
    check processCommand(ctx, @["block", "get", "not_a_height"]) == false
    check processCommand(ctx, @["account", "transfer", "alice"]) == false
