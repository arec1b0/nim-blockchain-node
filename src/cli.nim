## Command-line interface for the Nim blockchain node.
## Provides interactive commands for node management and blockchain operations.

import std/[strutils, os, parseopt, json, tables, times]
import core_engine/[consensus, state_management, vm]
import storage/[blockchain_db, state_db, index_db]
import network/[mempool, block_propagation, p2p]
import cryptography/key_management

type
  CliConfig* = object
    verbose*: bool
    jsonOutput*: bool
    dataDir*: string

  BlockchainNode* = object
    consensus*: Consensus
    accountState*: StateDB
    globalState*: StateDB
    blockchainDB*: BlockchainDB
    indexDB*: IndexDB
    mempool*: Mempool
    network*: Network
    vm*: VM

var 
  config = CliConfig(verbose: false, jsonOutput: false, dataDir: "data")
  node: BlockchainNode

proc initializeBlockchainNode*(): bool =
  ## Initialize all blockchain components
  try:
    # Initialize core components
    node.consensus = newConsensus()
    node.accountState = newStateDB()
    node.globalState = newStateDB()
    node.blockchainDB = newBlockchainDB()
    node.indexDB = newIndexDB()
    node.mempool = newMempool()
    node.network = newNetwork()
    node.vm = newVM(node.accountState, 1000000)
    
    # Add genesis validator
    discard node.consensus.addValidator(1, 10000)
    
    # Create genesis account
    node.accountState.setBalance("genesis", 1000000)
    
    echo "✅ Blockchain node initialized successfully"
    return true
  except:
    echo "❌ Failed to initialize blockchain node: ", getCurrentExceptionMsg()
    return false

proc printHelp() =
  echo """
Nim Blockchain Node CLI

USAGE:
    blockchain-cli [OPTIONS] COMMAND [ARGS]

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Enable verbose output
    -j, --json        Output in JSON format
    -d, --data-dir    Data directory (default: data)

COMMANDS:
    node              Node operations
    account           Account management
    transaction       Transaction operations  
    block             Block operations
    network           Network operations
    consensus         Consensus operations

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
    create            Create a new account
    balance ADDRESS   Show account balance
    list              List all accounts
    transfer FROM TO AMOUNT [FEE]  Transfer funds between accounts
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
    list [START] [END]           List blocks in range
    height                        Show current blockchain height
"""

proc nodeStatus() =
  if config.jsonOutput:
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
    echo "📊 Node Status:"
    echo "   Blockchain Height: ", node.blockchainDB.getCurrentHeight()
    echo "   Active Validators: ", node.consensus.activeValidatorCount()
    echo "   Pending Transactions: ", node.mempool.transactionCount()
    echo "   Connected Peers: ", node.network.connectedPeerCount()
    echo "   Gas Limit: ", node.vm.gasLimit
    echo "   Gas Used: ", node.vm.gasUsed

proc createAccount(): string =
  let keyPair = generateKeyPair()
  let address = keyPair.publicKey[0..7]  # Use first 8 chars as address
  node.accountState.setBalance(address, 0)
  
  if config.jsonOutput:
    let account = %*{
      "address": address,
      "public_key": keyPair.publicKey,
      "private_key": keyPair.privateKey,
      "balance": 0
    }
    echo account.pretty()
  else:
    echo "✅ Account created:"
    echo "   Address: ", address
    echo "   Public Key: ", keyPair.publicKey
    echo "   ⚠️  Save your private key: ", keyPair.privateKey
  
  return address

proc showBalance(address: string) =
  let balance = node.accountState.getBalance(address)
  let nonce = node.accountState.getNonce(address)
  
  if config.jsonOutput:
    let info = %*{
      "address": address,
      "balance": balance,
      "nonce": nonce
    }
    echo info.pretty()
  else:
    echo "💰 Account Balance:"
    echo "   Address: ", address
    echo "   Balance: ", balance
    echo "   Nonce: ", nonce

proc listAccounts() =
  echo "📋 All Accounts:"
  var count = 0
  for address in ["genesis"]:  # We'd need to track created accounts in real implementation
    let balance = node.accountState.getBalance(address)
    echo "   ", address, " - Balance: ", balance
    inc count
  
  if count == 0:
    echo "   No accounts found"

proc transferFunds(fromAddr, toAddr: string, amount: int, fee: int = 10): bool =
  let senderNonce = node.accountState.getNonce(fromAddr) + 1
  let tx = Transaction(
    id: "tx_" & $getTime().toUnix(),
    sender: fromAddr,
    receiver: toAddr,
    amount: amount.Balance,
    fee: fee.Balance,
    nonce: senderNonce.Nonce
  )
  
  if node.vm.applyTransaction(tx):
    discard node.mempool.addTransaction(tx)
    
    if config.jsonOutput:
      let result = %*{
        "success": true,
        "transaction_id": tx.id,
        "from": fromAddr,
        "to": toAddr,
        "amount": amount,
        "fee": fee
      }
      echo result.pretty()
    else:
      echo "✅ Transfer successful:"
      echo "   Transaction ID: ", tx.id
      echo "   From: ", fromAddr, " (New balance: ", node.accountState.getBalance(fromAddr), ")"
      echo "   To: ", toAddr, " (New balance: ", node.accountState.getBalance(toAddr), ")"
    
    return true
  else:
    echo "❌ Transfer failed: Insufficient balance or invalid transaction"
    return false

proc showLatestBlock() =
  let latestBlock = node.blockchainDB.getLatestBlock()
  if latestBlock.isSome:
    let blk = latestBlock.get
    if config.jsonOutput:
      let blockInfo = %*{
        "height": blk.height,
        "hash": blk.hash,
        "data": blk.data,
        "timestamp": blk.timestamp
      }
      echo blockInfo.pretty()
    else:
      echo "📦 Latest Block:"
      echo "   Height: ", blk.height
      echo "   Hash: ", blk.hash
      echo "   Data: ", blk.data
      echo "   Timestamp: ", blk.timestamp
  else:
    echo "No blocks found"

proc getBlock(height: int) =
  let blockOpt = node.blockchainDB.getBlock(height.BlockHeight)
  if blockOpt.isSome:
    let blk = blockOpt.get
    if config.jsonOutput:
      let blockInfo = %*{
        "height": blk.height,
        "hash": blk.hash,
        "data": blk.data,
        "timestamp": blk.timestamp
      }
      echo blockInfo.pretty()
    else:
      echo "📦 Block #", height, ":"
      echo "   Hash: ", blk.hash
      echo "   Data: ", blk.data
      echo "   Timestamp: ", blk.timestamp
  else:
    echo "❌ Block not found at height ", height

proc listPendingTransactions() =
  echo "📋 Pending Transactions:"
  let txs = node.mempool.getTransactionsByFee(10)
  if txs.len == 0:
    echo "   No pending transactions"
  else:
    for tx in txs:
      echo "   ", tx.id, " - Fee: ", tx.fee

proc processCommand(args: seq[string]): bool =
  if args.len == 0:
    printHelp()
    return true
    
  case args[0]:
  of "node":
    if args.len < 2:
      printNodeHelp()
      return true
    case args[1]:
    of "status":
      nodeStatus()
    of "info":
      nodeStatus()  # Same as status for now
    of "start":
      echo "🚀 Starting blockchain node..."
      discard initializeBlockchainNode()
    of "stop":
      echo "🛑 Stopping blockchain node..."
    else:
      echo "❌ Unknown node command: ", args[1]
      printNodeHelp()
      return false
      
  of "account":
    if args.len < 2:
      printAccountHelp()
      return true
    case args[1]:
    of "create":
      discard createAccount()
    of "balance":
      if args.len < 3:
        echo "❌ Usage: account balance ADDRESS"
        return false
      showBalance(args[2])
    of "list":
      listAccounts()
    of "transfer":
      if args.len < 5:
        echo "❌ Usage: account transfer FROM TO AMOUNT [FEE]"
        return false
      let fee = if args.len > 5: parseInt(args[5]) else: 10
      discard transferFunds(args[2], args[3], parseInt(args[4]), fee)
    else:
      echo "❌ Unknown account command: ", args[1]
      printAccountHelp()
      return false
      
  of "transaction", "tx":
    if args.len < 2:
      printTransactionHelp()
      return true
    case args[1]:
    of "list":
      listPendingTransactions()
    of "create":
      if args.len < 5:
        echo "❌ Usage: transaction create FROM TO AMOUNT [FEE]"
        return false
      let fee = if args.len > 5: parseInt(args[5]) else: 10
      discard transferFunds(args[2], args[3], parseInt(args[4]), fee)
    else:
      echo "❌ Unknown transaction command: ", args[1]
      printTransactionHelp()
      return false
      
  of "block":
    if args.len < 2:
      printBlockHelp()
      return true
    case args[1]:
    of "latest":
      showLatestBlock()
    of "get":
      if args.len < 3:
        echo "❌ Usage: block get HEIGHT"
        return false
      getBlock(parseInt(args[2]))
    of "height":
      echo "Current blockchain height: ", node.blockchainDB.getCurrentHeight()
    else:
      echo "❌ Unknown block command: ", args[1]
      printBlockHelp()
      return false
      
  of "help", "-h", "--help":
    printHelp()
    
  else:
    echo "❌ Unknown command: ", args[0]
    printHelp()
    return false
    
  return true

proc parseOptions() =
  var p = initOptParser()
  
  while true:
    p.next()
    case p.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key:
      of "h", "help":
        printHelp()
        quit(0)
      of "v", "verbose":
        config.verbose = true
      of "j", "json":
        config.jsonOutput = true
      of "d", "data-dir":
        config.dataDir = p.val
      else:
        echo "❌ Unknown option: ", p.key
        quit(1)
    of cmdArgument:
      # Arguments will be processed later
      break

proc runCLI*() =
  ## Main CLI entry point
  parseOptions()
  
  if not initializeBlockchainNode():
    quit(1)
  
  let args = commandLineParams()
  var cmdArgs: seq[string] = @[]
  
  # Filter out options to get just the commands
  var skipNext = false
  for i, arg in args:
    if skipNext:
      skipNext = false
      continue
    if arg.startsWith("-"):
      if arg in ["-d", "--data-dir"]:
        skipNext = true
      continue
    cmdArgs.add(arg)
  
  if not processCommand(cmdArgs):
    quit(1)

when isMainModule:
  runCLI()