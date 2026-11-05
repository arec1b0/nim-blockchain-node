## Command-line interface for the Nim blockchain node.
## Educational prototype. Command results are written to stdout.
## Diagnostics use std/logging on stderr (`common/logsetup`).
## Private keys are written only to the keystore file and are never printed.

import std/[strutils, os, json, times, logging, options]
import common/[types, result, config, logsetup]
import core_engine/[consensus, state_management, vm]
import storage/[blockchain_db, state_db, index_db]
import network/[mempool, p2p]
import cryptography/[key_management, keystore, signature_verification]

type
  CliConfig* = NodeConfig

  BlockchainNode* = object
    consensus*: Consensus
    accountState*: StateDB
    globalState*: GlobalStateStore
    blockchainDB*: BlockchainDB
    indexDB*: IndexDB
    mempool*: Mempool
    network*: Network
    vm*: VM

  CliInitError* = enum
    cliInitNone
    cliInitUnexpected

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
    trGasLimitExceeded
    trDebitFailed

var
  cliConfig* = NodeConfig(verbose: false, jsonOutput: false, dataDir: DefaultDataDir)
  node*: BlockchainNode

proc emitText(message: string) =
  ## User-facing command output. The message must not contain key material.
  if cliConfig.jsonOutput:
    echo (%*{"success": false, "error": message}).pretty()
  else:
    echo message
  warn(message)

proc initializeBlockchainNode*(): Status[CliInitError] =
  ## Initialize in-memory components. Does not start a long-running process.
  try:
    node.consensus = newConsensus()
    node.accountState = newStateDB()
    node.globalState = newGlobalStateStore()
    node.blockchainDB = newBlockchainDB()
    node.indexDB = newIndexDB()
    node.mempool = newMempool()
    node.network = newNetwork()
    # Fund genesis before copying the value-type ledger into the VM.
    node.accountState.setBalance("genesis", 1000000)
    node.vm = newVM(node.accountState, 1000000)
    discard node.consensus.addValidator(1, 10000)
    debug("in-memory node initialized")
    info("blockchain node initialized")
    okStatus(CliInitError)
  except CatchableError as e:
    error("blockchain node initialization failed: " & $e.name)
    errStatus(cliInitUnexpected)

proc printHelp() =
  echo """
Nim Blockchain Node CLI (educational prototype)

USAGE:
    blockchain-cli [OPTIONS] COMMAND [ARGS]

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Debug logging on stderr. When omitted, NIM_NODE_VERBOSE is used.
    -j, --json        Output command results in JSON format
    -d, --data-dir    Data directory (default: data, or NIM_NODE_DATA_DIR)

Precedence: CLI flags, then NIM_NODE_DATA_DIR / NIM_NODE_VERBOSE, then defaults.
--verbose is a presence flag and does not turn an environment setting off.
Options must come before the command.

COMMANDS:
    node              Node operations
    account           Account management
    transaction       Transaction operations
    block             Block operations
    network           Network operations
    consensus         Consensus operations

Private keys are written under <data-dir>/keystore and are not printed.
The keystore is plaintext. The signature scheme is demo-sha256, not Ed25519.
This process initializes and exits; it is not a long-running server.

Use 'blockchain-cli COMMAND --help' for more information on a command.
"""

proc printNodeHelp() =
  echo """
Node Operations

USAGE:
    blockchain-cli node COMMAND

COMMANDS:
    status            Show node status
    start             Start the blockchain node
    stop              Stop the blockchain node
    info              Show detailed node information
"""

proc printAccountHelp() =
  echo """
Account Management

USAGE:
    blockchain-cli account COMMAND

COMMANDS:
    create            Create a new account (private key goes to the keystore only)
    balance ADDRESS   Show account balance
    list              List all accounts
    transfer FROM TO AMOUNT [FEE]  Transfer funds between accounts

The sender must have a keystore file in the data directory. The genesis
account is funded in memory and has no signing key, so it cannot transfer.
"""

proc printTransactionHelp() =
  echo """
Transaction Operations

USAGE:
    blockchain-cli transaction COMMAND

COMMANDS:
    create FROM TO AMOUNT [FEE]   Create a new transaction
    status TX_ID                  Show transaction status
    list                          List pending transactions
    history ADDRESS               Show transaction history for address
"""

proc printBlockHelp() =
  echo """
Block Operations

USAGE:
    blockchain-cli block COMMAND

COMMANDS:
    latest                        Show latest block
    get HEIGHT                    Get block by height
    list [START] [END]            List blocks in range
    height                        Show current blockchain height
"""

proc nodeStatus() =
  if cliConfig.jsonOutput:
    let status = %*{
      "height": node.blockchainDB.getCurrentHeight(),
      "validators": node.consensus.activeValidatorCount(),
      "pending_transactions": node.mempool.transactionCount(),
      "peers": node.network.connectedPeerCount(),
      "gas_limit": node.vm.gasLimit,
      "gas_used": node.vm.gasUsed
    }
    echo status.pretty()
  else:
    echo "Node Status:"
    echo "  Blockchain Height: ", node.blockchainDB.getCurrentHeight()
    echo "  Active Validators: ", node.consensus.activeValidatorCount()
    echo "  Pending Transactions: ", node.mempool.transactionCount()
    echo "  Connected Peers: ", node.network.connectedPeerCount()
    echo "  Gas Limit: ", node.vm.gasLimit
    echo "  Gas Used: ", node.vm.gasUsed

proc createdAccountJson*(account: CreatedAccount, balance: Balance): JsonNode =
  ## JSON command result. Intentionally has no private key field.
  %*{
    "address": account.address,
    "public_key": account.publicKey,
    "balance": balance,
    "keystore": account.keystorePath,
    "keystore_format": "plaintext-educational",
    "signature_scheme": DemoSignatureScheme,
    "warning": "plaintext educational keystore; demo-sha256 is not unforgeable"
  }

proc createAccount*(): Result[CreatedAccount, KeystoreError] =
  ## Creates a key, stores it in the keystore, and prints only public data.
  try:
    let keyPair = generateKeyPair()
    let address = addressFromPublicKey(keyPair.publicKey)
    let saved = saveKeystore(cliConfig.dataDir, address, keyPair.publicKey, keyPair.privateKey)
    if not saved.ok:
      emitText("Account creation failed: the keystore was not written.")
      return errResult(CreatedAccount, saved.error)
    node.vm.state.setBalance(address, 0)
    let created = CreatedAccount(
      address: address,
      publicKey: keyPair.publicKey,
      keystorePath: keystoreFile(cliConfig.dataDir, address)
    )
    if cliConfig.jsonOutput:
      echo createdAccountJson(created, 0).pretty()
    else:
      echo "Account created:"
      echo "  Address: ", created.address
      echo "  Public key: ", created.publicKey
      echo "  Keystore: ", created.keystorePath
      echo "  The private key was written only to that keystore file."
      echo "  The file is plaintext and is not encrypted."
      echo "  On Windows the file cannot be given a POSIX owner-only mode."
    info("account created address=" & created.address)
    okResult(created, KeystoreError)
  except CatchableError:
    emitText("Account creation failed.")
    errResult(CreatedAccount, ksIo)

proc showBalance(address: string) =
  let balance = node.vm.state.getBalance(address)
  let nonce = node.vm.state.getNonce(address)
  if cliConfig.jsonOutput:
    let infoNode = %*{
      "address": address,
      "balance": balance,
      "nonce": nonce
    }
    echo infoNode.pretty()
  else:
    echo "Account Balance:"
    echo "  Address: ", address
    echo "  Balance: ", balance
    echo "  Nonce: ", nonce

proc listAccounts() =
  echo "Accounts:"
  let balance = node.vm.state.getBalance("genesis")
  echo "  genesis - Balance: ", balance
  echo "  (genesis has no keystore and cannot authorize transfers)"

proc describeTransfer(err: TransferError): string =
  case err
  of trNone:
    "Transfer failed."
  of trKeystoreMissing:
    "Transfer failed: no keystore file for the sender. Create the account on this node first."
  of trKeystoreMalformed:
    "Transfer failed: the keystore file is malformed or uses an unsupported scheme."
  of trKeystoreUnsafePath:
    "Transfer failed: the sender address is not a safe keystore id."
  of trKeystoreIo:
    "Transfer failed: the keystore could not be read."
  of trZeroAmount:
    "Transfer failed: amount must be greater than zero."
  of trMissingPublicKey, trMissingSignature:
    "Transfer failed: the transaction is unsigned."
  of trSenderKeyMismatch:
    "Transfer failed: the sender does not match the keystore public key."
  of trInvalidSignature:
    "Transfer failed: invalid signature."
  of trInsufficientBalance:
    "Transfer failed: insufficient balance."
  of trBadNonce:
    "Transfer failed: the nonce does not match the account sequence."
  of trGasLimitExceeded:
    "Transfer failed: gas limit exceeded."
  of trDebitFailed:
    "Transfer failed: the sender balance could not be debited."

proc fromKeystore(err: KeystoreError): TransferError =
  case err
  of ksNone, ksMalformed, ksExists: trKeystoreMalformed
  of ksMissing: trKeystoreMissing
  of ksUnsafePath: trKeystoreUnsafePath
  of ksIo: trKeystoreIo

proc fromTx(err: TxError): TransferError =
  case err
  of txNone, txDebitFailed: trDebitFailed
  of txZeroAmount: trZeroAmount
  of txMissingPublicKey: trMissingPublicKey
  of txMissingSignature: trMissingSignature
  of txSenderKeyMismatch: trSenderKeyMismatch
  of txInvalidSignature: trInvalidSignature
  of txInsufficientBalance: trInsufficientBalance
  of txBadNonce: trBadNonce
  of txGasLimitExceeded: trGasLimitExceeded

proc transferFunds(fromAddr, toAddr: string, amount: int, fee: int = 10): Status[TransferError] =
  ## Signs with the sender's keystore key, then applies the VM and mempool gates.
  ## The VM runs first (existing CLI order). Both gates call authorizeTransaction.
  debug("transfer requested from=" & fromAddr & " to=" & toAddr)
  if amount <= 0:
    emitText(describeTransfer(trZeroAmount))
    return errStatus(trZeroAmount)
  if fee < 0:
    emitText("Transfer failed: fee cannot be negative.")
    return errStatus(trZeroAmount)
  var loaded = loadKeystore(cliConfig.dataDir, fromAddr)
  if not loaded.ok:
    let reason = fromKeystore(loaded.error)
    emitText(describeTransfer(reason))
    return errStatus(reason)
  var tx = Transaction(
    id: "tx_" & $getTime().toUnix(),
    sender: fromAddr,
    receiver: toAddr,
    amount: amount.Balance,
    fee: fee.Balance,
    nonce: Nonce(node.vm.state.getNonce(fromAddr) + 1),
    publicKey: loaded.value.publicKey
  )
  try:
    tx.signature = signMessage(loaded.value.privateKey, transactionSigningPayload(tx))
  except ValueError:
    loaded.value.privateKey = ""
    emitText(describeTransfer(trKeystoreMalformed))
    return errStatus(trKeystoreMalformed)
  loaded.value.privateKey = ""
  let applied = node.vm.applyTransaction(tx)
  if not applied.ok:
    let reason = fromTx(applied.error)
    emitText(describeTransfer(reason))
    return errStatus(reason)
  let admitted = node.mempool.addTransaction(tx)
  if not admitted.ok:
    warn("transaction applied but mempool rejected it id=" & shortId(tx.id))
  if cliConfig.jsonOutput:
    let payload = %*{
      "success": true,
      "transaction_id": tx.id,
      "from": fromAddr,
      "to": toAddr,
      "amount": amount,
      "fee": fee
    }
    echo payload.pretty()
  else:
    echo "Transfer successful:"
    echo "  Transaction ID: ", tx.id
    echo "  From: ", fromAddr, " (New balance: ", node.vm.state.getBalance(fromAddr), ")"
    echo "  To: ", toAddr, " (New balance: ", node.vm.state.getBalance(toAddr), ")"
  info("transfer applied id=" & shortId(tx.id))
  okStatus(TransferError)

proc showLatestBlock() =
  let latestBlock = node.blockchainDB.getLatestBlock()
  if latestBlock.isSome:
    let blk = latestBlock.get
    if cliConfig.jsonOutput:
      let blockInfo = %*{
        "height": blk.height,
        "hash": blk.hash,
        "data": blk.data,
        "timestamp": blk.timestamp
      }
      echo blockInfo.pretty()
    else:
      echo "Latest Block:"
      echo "  Height: ", blk.height
      echo "  Hash: ", blk.hash
      echo "  Data: ", blk.data
      echo "  Timestamp: ", blk.timestamp
  else:
    echo "No blocks found"

proc getBlock(height: int) =
  let blockOpt = node.blockchainDB.getBlock(blockchain_db.BlockHeight(height))
  if blockOpt.isSome:
    let blk = blockOpt.get
    if cliConfig.jsonOutput:
      let blockInfo = %*{
        "height": blk.height,
        "hash": blk.hash,
        "data": blk.data,
        "timestamp": blk.timestamp
      }
      echo blockInfo.pretty()
    else:
      echo "Block #", height, ":"
      echo "  Hash: ", blk.hash
      echo "  Data: ", blk.data
      echo "  Timestamp: ", blk.timestamp
  else:
    echo "Block not found at height ", height

proc listPendingTransactions() =
  echo "Pending Transactions:"
  let txs = node.mempool.getTransactionsByFee(10)
  if txs.len == 0:
    echo "  No pending transactions"
  else:
    for tx in txs:
      echo "  ", tx.id, " - Fee: ", tx.fee

proc parseNonNegative(args: seq[string]): Result[tuple[amount: int, fee: int], string] =
  try:
    let amount = parseInt(args[4])
    let fee = if args.len > 5: parseInt(args[5]) else: 10
    okResult((amount: amount, fee: fee), string)
  except ValueError:
    errResult(tuple[amount: int, fee: int], "amount and fee must be integers")

proc processCommand(args: seq[string]): bool =
  if args.len == 0:
    printHelp()
    return true

  case args[0]
  of "node":
    if args.len < 2:
      printNodeHelp()
      return true
    case args[1]
    of "status":
      nodeStatus()
    of "info":
      nodeStatus()
    of "start":
      info("start requested")
      if not initializeBlockchainNode().ok:
        return false
    of "stop":
      info("stop requested")
      echo "Stop requested. This prototype is not a long-running process."
    else:
      emitText("Unknown node command: " & args[1])
      printNodeHelp()
      return false

  of "account":
    if args.len < 2:
      printAccountHelp()
      return true
    case args[1]
    of "create":
      if not createAccount().ok:
        return false
    of "balance":
      if args.len < 3:
        emitText("Usage: account balance ADDRESS")
        return false
      showBalance(args[2])
    of "list":
      listAccounts()
    of "transfer":
      if args.len < 5:
        emitText("Usage: account transfer FROM TO AMOUNT [FEE]")
        return false
      let parsed = parseNonNegative(args)
      if not parsed.ok:
        emitText(parsed.error)
        return false
      if not transferFunds(args[2], args[3], parsed.value.amount, parsed.value.fee).ok:
        return false
    else:
      emitText("Unknown account command: " & args[1])
      printAccountHelp()
      return false

  of "transaction", "tx":
    if args.len < 2:
      printTransactionHelp()
      return true
    case args[1]
    of "list":
      listPendingTransactions()
    of "create":
      if args.len < 5:
        emitText("Usage: transaction create FROM TO AMOUNT [FEE]")
        return false
      let parsed = parseNonNegative(args)
      if not parsed.ok:
        emitText(parsed.error)
        return false
      if not transferFunds(args[2], args[3], parsed.value.amount, parsed.value.fee).ok:
        return false
    else:
      emitText("Unknown transaction command: " & args[1])
      printTransactionHelp()
      return false

  of "block":
    if args.len < 2:
      printBlockHelp()
      return true
    case args[1]
    of "latest":
      showLatestBlock()
    of "get":
      if args.len < 3:
        emitText("Usage: block get HEIGHT")
        return false
      try:
        getBlock(parseInt(args[2]))
      except ValueError:
        emitText("block height must be an integer")
        return false
    of "height":
      echo "Current blockchain height: ", node.blockchainDB.getCurrentHeight()
    else:
      emitText("Unknown block command: " & args[1])
      printBlockHelp()
      return false

  of "help", "-h", "--help":
    printHelp()

  else:
    emitText("Unknown command: " & args[0])
    printHelp()
    return false

  return true

proc commandArguments(): seq[string] =
  var skipNext = false
  for arg in commandLineParams():
    if skipNext:
      skipNext = false
      continue
    if arg in ["-d", "--data-dir"]:
      skipNext = true
      continue
    if arg.startsWith("--data-dir="):
      continue
    if arg.startsWith("-"):
      continue
    result.add(arg)

proc runCLI*() =
  ## CLI composition root. Initializes logging, then runs one command and exits.
  let overrides = readCliOverrides()
  cliConfig = resolveConfig(overrides)
  configureLogging(cliConfig.verbose)
  if overrides.errorMessage.len > 0:
    error(overrides.errorMessage)
    quit(1)
  if overrides.helpRequested:
    printHelp()
    quit(0)
  try:
    createDir(cliConfig.dataDir)
  except CatchableError as e:
    error("cannot create data directory: " & $e.name)
    quit(1)
  debug("data directory=" & cliConfig.dataDir)
  if not initializeBlockchainNode().ok:
    quit(1)
  if not processCommand(commandArguments()):
    quit(1)

when isMainModule:
  runCLI()
