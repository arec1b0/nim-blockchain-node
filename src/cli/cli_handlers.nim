## Command dispatch and formatting handlers for Nim blockchain node CLI.
## Formats human-readable and JSON output without direct business logic coupling.

import std/[json, logging, options]
import ../common/[types, result, config]
import ../cryptography/[keystore, signature_verification]
export signature_verification.DemoSignatureScheme
import cli_parser
import cli_service

proc emitText*(message: string, jsonOutput: bool = false) =
  ## User-facing command output or error. Message must not contain key material.
  if jsonOutput:
    echo (%*{"success": false, "error": message}).pretty()
  else:
    echo message
  warn(message)

proc describeTransfer*(err: TransferError): string =
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
  of trNegativeFee:
    "Transfer failed: fee cannot be negative."
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
  of trEmptyReceiver:
    "Transfer failed: the recipient address is empty."
  of trGasLimitExceeded:
    "Transfer failed: gas limit exceeded."
  of trDebitFailed:
    "Transfer failed: the sender balance could not be debited."
  of trAccountStore:
    "Transfer failed: account state could not be saved."
  of trMempoolDuplicate:
    "Transfer failed: transaction is already in the mempool."
  of trMempoolFull:
    "Transfer failed: mempool is full."
  of trBlockPropagationFailed:
    "Transfer failed: block propagation failed."
  of trBlockStorageFailed:
    "Transfer failed: block could not be stored."

proc createdAccountJson*(account: CreatedAccount, balance: Balance): JsonNode =
  ## JSON command result for account creation. Private key is intentionally omitted.
  %*{
    "address": account.address,
    "public_key": account.publicKey,
    "balance": balance,
    "keystore": account.keystorePath,
    "keystore_format": "plaintext-educational",
    "signature_scheme": DemoSignatureScheme,
    "warning": "plaintext educational keystore; demo-sha256 is not unforgeable"
  }

proc renderNodeStatus*(ctx: CliServiceContext) =
  let status = ctx.getNodeStatus()
  if ctx.config.jsonOutput:
    let nodeJson = %*{
      "height": status.height,
      "validators": status.validators,
      "pending_transactions": status.pendingTransactions,
      "peers": status.peers,
      "gas_limit": status.gasLimit,
      "gas_used": status.gasUsed
    }
    echo nodeJson.pretty()
  else:
    echo "Node Status:"
    echo "  Blockchain Height: ", status.height
    echo "  Active Validators: ", status.validators
    echo "  Pending Transactions: ", status.pendingTransactions
    echo "  Connected Peers: ", status.peers
    echo "  Gas Limit: ", status.gasLimit
    echo "  Gas Used: ", status.gasUsed

proc renderCreatedAccount*(account: CreatedAccount, jsonOutput: bool) =
  if jsonOutput:
    echo createdAccountJson(account, 0).pretty()
  else:
    echo "Account created:"
    echo "  Address: ", account.address
    echo "  Public key: ", account.publicKey
    echo "  Keystore: ", account.keystorePath
    echo "  The private key was written only to that keystore file."
    echo "  The file is plaintext and is not encrypted."
    echo "  On Windows the file cannot be given a POSIX owner-only mode."

proc renderAccountCreateError*(err: KeystoreError, isMemoryDir: bool, jsonOutput: bool) =
  if isMemoryDir:
    emitText("Account creation failed: :memory: does not store keys. Pass a filesystem --data-dir.", jsonOutput)
  else:
    case err
    of ksIo:
      emitText("Account creation failed: account state was not saved.", jsonOutput)
    else:
      emitText("Account creation failed: the keystore was not written.", jsonOutput)

proc renderBalance*(ctx: CliServiceContext, address: string) =
  let info = ctx.getAccountBalance(address)
  if ctx.config.jsonOutput:
    let infoNode = %*{
      "address": info.address,
      "balance": info.balance,
      "nonce": info.nonce
    }
    echo infoNode.pretty()
  else:
    echo "Account Balance:"
    echo "  Address: ", info.address
    echo "  Balance: ", info.balance
    echo "  Nonce: ", info.nonce

proc renderAccountList*(ctx: CliServiceContext) =
  echo "Accounts:"
  let accounts = ctx.listAccounts()
  for acc in accounts:
    echo "  ", acc.address, " - Balance: ", acc.balance
    if not acc.hasKeystore:
      echo "  (", acc.address, " has no keystore and cannot authorize transfers)"

proc renderTransferResult*(res: Result[TransferResult, TransferError], isMemoryDir: bool, jsonOutput: bool): bool =
  if res.ok:
    let val = res.value
    if jsonOutput:
      let payload = %*{
        "success": true,
        "transaction_id": val.tx.id,
        "from": val.tx.sender,
        "to": val.tx.receiver,
        "amount": val.tx.amount.int,
        "fee": val.tx.fee.int
      }
      echo payload.pretty()
    else:
      echo "Transfer successful:"
      echo "  Transaction ID: ", val.tx.id
      echo "  From: ", val.tx.sender, " (New balance: ", val.fromBalance, ")"
      echo "  To: ", val.tx.receiver, " (New balance: ", val.toBalance, ")"
    return true
  else:
    if isMemoryDir and res.error == trKeystoreUnsafePath:
      emitText("Transfer failed: :memory: does not store keys. Pass a filesystem --data-dir.", jsonOutput)
    else:
      emitText(describeTransfer(res.error), jsonOutput)
    return false

proc renderLatestBlock*(ctx: CliServiceContext) =
  let latestBlock = ctx.getLatestBlock()
  if latestBlock.isSome:
    let blk = latestBlock.get
    if ctx.config.jsonOutput:
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

proc renderBlock*(ctx: CliServiceContext, height: int) =
  let blockOpt = ctx.getBlock(height)
  if blockOpt.isSome:
    let blk = blockOpt.get
    if ctx.config.jsonOutput:
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

proc renderBlockHeight*(ctx: CliServiceContext) =
  let h = ctx.getCurrentHeight()
  echo "Current blockchain height: ", h

proc renderPendingTransactions*(ctx: CliServiceContext) =
  echo "Pending Transactions:"
  let txs = ctx.getPendingTransactions(10)
  if txs.len == 0:
    echo "  No pending transactions"
  else:
    for tx in txs:
      echo "  ", tx.id, " - Fee: ", tx.fee

proc processCommand*(ctx: CliServiceContext, args: seq[string]): bool =
  if args.len == 0:
    printHelp()
    return true

  case args[0]
  of "node":
    if args.len < 2:
      printNodeHelp()
      return true
    case args[1]
    of "status", "info":
      renderNodeStatus(ctx)
    of "start":
      info("start requested")
      return true
    of "stop":
      info("stop requested")
      ctx.close()
      echo "Stop requested. This prototype is not a long-running process."
    else:
      emitText("Unknown node command: " & args[1], ctx.config.jsonOutput)
      printNodeHelp()
      return false

  of "account":
    if args.len < 2:
      printAccountHelp()
      return true
    case args[1]
    of "create":
      let created = ctx.createAccount()
      if not created.ok:
        renderAccountCreateError(created.error, isMemoryDataDir(ctx.config.dataDir), ctx.config.jsonOutput)
        return false
      renderCreatedAccount(created.value, ctx.config.jsonOutput)
    of "balance":
      if args.len < 3:
        emitText("Usage: account balance ADDRESS", ctx.config.jsonOutput)
        return false
      renderBalance(ctx, args[2])
    of "list":
      renderAccountList(ctx)
    of "transfer":
      if args.len < 5:
        emitText("Usage: account transfer FROM TO AMOUNT [FEE]", ctx.config.jsonOutput)
        return false
      let parsed = parseNonNegative(args)
      if not parsed.ok:
        emitText(parsed.error, ctx.config.jsonOutput)
        return false
      let res = ctx.transferFunds(args[2], args[3], parsed.value.amount, parsed.value.fee)
      return renderTransferResult(res, isMemoryDataDir(ctx.config.dataDir), ctx.config.jsonOutput)
    else:
      emitText("Unknown account command: " & args[1], ctx.config.jsonOutput)
      printAccountHelp()
      return false

  of "transaction", "tx":
    if args.len < 2:
      printTransactionHelp()
      return true
    case args[1]
    of "list":
      renderPendingTransactions(ctx)
    of "create":
      if args.len < 5:
        emitText("Usage: transaction create FROM TO AMOUNT [FEE]", ctx.config.jsonOutput)
        return false
      let parsed = parseNonNegative(args)
      if not parsed.ok:
        emitText(parsed.error, ctx.config.jsonOutput)
        return false
      let res = ctx.transferFunds(args[2], args[3], parsed.value.amount, parsed.value.fee)
      return renderTransferResult(res, isMemoryDataDir(ctx.config.dataDir), ctx.config.jsonOutput)
    else:
      emitText("Unknown transaction command: " & args[1], ctx.config.jsonOutput)
      printTransactionHelp()
      return false

  of "block":
    if args.len < 2:
      printBlockHelp()
      return true
    case args[1]
    of "latest":
      renderLatestBlock(ctx)
    of "get":
      if args.len < 3:
        emitText("Usage: block get HEIGHT", ctx.config.jsonOutput)
        return false
      let heightRes = parseBlockHeight(args[2])
      if not heightRes.ok:
        emitText("block height must be an integer", ctx.config.jsonOutput)
        return false
      renderBlock(ctx, heightRes.value)
    of "height":
      renderBlockHeight(ctx)
    else:
      emitText("Unknown block command: " & args[1], ctx.config.jsonOutput)
      printBlockHelp()
      return false

  of "help", "-h", "--help":
    printHelp()

  else:
    emitText("Unknown command: " & args[0], ctx.config.jsonOutput)
    printHelp()
    return false

  return true
