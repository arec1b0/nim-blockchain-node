## Command-line interface for the Nim blockchain node.
## Thin facade orchestrator delegating to specialized CLI submodules:
## - cli/cli_parser: argument parsing, help formatting, options handling
## - cli/cli_service: BlockchainNode runtime service operations and context
## - cli/cli_handlers: command dispatch and user-facing formatting

import std/[os, logging]
import common/[result, config, logsetup]
import storage/account_store
import cryptography/keystore
import node as runtime

import cli/[cli_parser, cli_service, cli_handlers]
export cli_parser, cli_service, cli_handlers
export runtime.BlockchainNode

var
  cliConfig* = defaultNodeConfig()
  node*: BlockchainNode

proc initializeBlockchainNode*(): Status[CliInitError] =
  ## Backward-compatible initialization using global cliConfig and node adapter.
  try:
    if not node.isNil:
      discard runtime.close(node)
    let prepared = initCliNode(cliConfig)
    if not prepared.ok:
      return errStatus(prepared.error)
    node = prepared.value
    okStatus(CliInitError)
  except CatchableError as e:
    error("blockchain node initialization failed: " & $e.name)
    errStatus(cliInitUnexpected)

proc persistAccountState*(): Status[AccountStoreError] =
  ## Backward-compatible account state persistence using global node adapter.
  if node.isNil:
    return errStatus(asIo)
  runtime.persistAccountState(node)

proc createAccount*(): Result[CreatedAccount, KeystoreError] =
  ## Backward-compatible account creation using global node and cliConfig adapter.
  if node.isNil:
    return errResult(CreatedAccount, ksIo)
  let ctx = newCliServiceContext(node, cliConfig)
  let res = ctx.createAccount()
  if res.ok:
    renderCreatedAccount(res.value, cliConfig.jsonOutput)
  else:
    renderAccountCreateError(res.error, isMemoryDataDir(cliConfig.dataDir), cliConfig.jsonOutput)
  res

proc transferFunds*(fromAddr, toAddr: string, amount: int, fee: int = 10): Status[TransferError] =
  ## Backward-compatible fund transfer using global node and cliConfig adapter.
  if node.isNil:
    return errStatus(trNone)
  let ctx = newCliServiceContext(node, cliConfig)
  let res = ctx.transferFunds(fromAddr, toAddr, amount, fee)
  discard renderTransferResult(res, isMemoryDataDir(cliConfig.dataDir), cliConfig.jsonOutput)
  if res.ok:
    okStatus(TransferError)
  else:
    if res.error == trNegativeFee:
      errStatus(trZeroAmount)
    else:
      errStatus(res.error)

proc runCLI*() =
  ## CLI composition root. Initializes logging, constructs context, executes command, and exits.
  let overrides = readCliOverrides()
  cliConfig = resolveConfig(overrides)
  configureLogging(cliConfig.verbose)
  if overrides.errorMessage.len > 0:
    error(overrides.errorMessage)
    quit(1)
  if overrides.helpRequested:
    printHelp()
    quit(0)
  if not isMemoryDataDir(cliConfig.dataDir):
    try:
      createDir(cliConfig.dataDir)
    except CatchableError as e:
      error("cannot create data directory: " & $e.name)
      quit(1)
  else:
    debug("memory-only account store")
  debug("data directory=" & cliConfig.dataDir)

  let initRes = initCliServiceContext(cliConfig)
  if not initRes.ok:
    quit(1)
  let ctx = initRes.value
  node = ctx.node # adapter sync for legacy callers
  let commandOk = processCommand(ctx, commandArguments())
  ctx.close()
  node = nil
  if not commandOk:
    quit(1)

when isMainModule:
  runCLI()
