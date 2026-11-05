## Command-line argument parsing and help formatting for Nim blockchain node CLI.
## Pure parsing and token extraction without global mutable state.

import std/[strutils, os]
import ../common/[result, config]

proc printHelp*() =
  echo """
Nim Blockchain Node CLI (educational prototype)

USAGE:
    blockchain-cli [OPTIONS] COMMAND [ARGS]

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Debug logging on stderr. When omitted, NIM_NODE_VERBOSE is used.
    -j, --json        Output command results in JSON format
    -d, --data-dir    Data directory (default: data, or NIM_NODE_DATA_DIR)

Account balances and nonces are stored in <data-dir>/accounts.json.
Pass --data-dir=:memory: to keep those balances in process memory only.
Blocks, the mempool, and peers are not saved. :memory: does not store keys.

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

proc printNodeHelp*() =
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

proc printAccountHelp*() =
  echo """
Account Management

USAGE:
    blockchain-cli account COMMAND

COMMANDS:
    create            Create a new account (private key goes to the keystore only)
    balance ADDRESS   Show account balance
    list              List all accounts
    transfer FROM TO AMOUNT [FEE]  Transfer funds between accounts

The sender must have a keystore file in the data directory. A new account
store funds genesis with 1000000. An existing accounts.json is loaded and
genesis is not reset. genesis has no signing key, so it cannot transfer.
:memory: keeps balances for this process only and cannot store keys.
"""

proc printTransactionHelp*() =
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

proc printBlockHelp*() =
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

proc commandArguments*(params: seq[string] = commandLineParams()): seq[string] =
  ## Extracts positional command and argument tokens, skipping CLI options and option values.
  var skipNext = false
  for arg in params:
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

proc parseCliOptions*(params: seq[string]): CliOverrides =
  ## Parses CLI options from a parameter sequence up to the first positional argument.
  ## Pure helper allowing isolated unit testing of option parsing.
  var idx = 0
  while idx < params.len:
    let arg = params[idx]
    if arg in ["-h", "--help"]:
      result.helpRequested = true
    elif arg in ["-v", "--verbose"]:
      result.verbose = true
    elif arg in ["-j", "--json"]:
      result.jsonOutput = true
    elif arg in ["-d", "--data-dir"]:
      if idx + 1 >= params.len:
        result.errorMessage = "data-dir requires a path"
        break
      result.dataDirProvided = true
      result.dataDir = params[idx + 1]
      inc idx
    elif arg.startsWith("--data-dir="):
      let val = arg["--data-dir=".len .. ^1]
      if val.len == 0:
        result.errorMessage = "data-dir requires a path"
        break
      result.dataDirProvided = true
      result.dataDir = val
    elif arg.startsWith("-"):
      result.errorMessage = "unknown option: " & arg
      break
    else:
      # First positional argument marks the command boundary
      break
    inc idx

proc parseNonNegative*(args: seq[string]): Result[tuple[amount: int, fee: int], string] =
  ## Extracts amount and optional fee from transfer argument sequence.
  ## Expected format: @[..., "transfer", FROM, TO, AMOUNT, optional FEE].
  try:
    if args.len < 5:
      return errResult(tuple[amount: int, fee: int], "missing amount")
    let amount = parseInt(args[4])
    let fee = if args.len > 5: parseInt(args[5]) else: 10
    okResult((amount: amount, fee: fee), string)
  except ValueError:
    errResult(tuple[amount: int, fee: int], "amount and fee must be integers")

proc parseBlockHeight*(arg: string): Result[int, string] =
  ## Parses a block height argument string into an integer.
  try:
    let h = parseInt(arg)
    if h < 0:
      return errResult(int, "block height must be non-negative")
    okResult(h, string)
  except ValueError:
    errResult(int, "block height must be an integer")
