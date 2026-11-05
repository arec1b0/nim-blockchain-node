## Typed runtime configuration.
## Precedence: CLI flags > environment variables > defaults.
## `--verbose` is a presence flag: when it is absent, `NIM_NODE_VERBOSE` stands.
## There is no global mutable config here; callers keep the resolved value.

import std/[os, strutils, parseopt]

const
  DefaultDataDir* = "data"
  ## Account state stays in the process. Not a directory path.
  MemoryDataDir* = ":memory:"
  EnvDataDir* = "NIM_NODE_DATA_DIR"
  EnvVerbose* = "NIM_NODE_VERBOSE"

  DefaultGasLimit*: Natural = 1_000_000
  DefaultMempoolCapacity*: int = 5000
  DefaultMaxPeers*: int = 50

proc isMemoryDataDir*(dataDir: string): bool =
  ## True for the explicit memory-only sentinel.
  ## An omitted `--data-dir` still resolves to `DefaultDataDir`.
  dataDir == MemoryDataDir

type
  StorageBackend* = enum
    backendMemory
    backendFile

  ValidatorConfig* = object
    id*: int
    stake*: int

  NodeConfig* = object
    verbose*: bool
    jsonOutput*: bool
    dataDir*: string
    storageBackend*: StorageBackend
    gasLimit*: Natural
    mempoolCapacity*: int
    maxPeers*: int
    validators*: seq[ValidatorConfig]

  CliOverrides* = object
    verbose*: bool
    jsonOutput*: bool
    dataDir*: string
    dataDirProvided*: bool
    helpRequested*: bool
    errorMessage*: string

proc defaultValidators*(): seq[ValidatorConfig] =
  @[
    ValidatorConfig(id: 1, stake: 1000),
    ValidatorConfig(id: 2, stake: 1500)
  ]

proc defaultNodeConfig*(): NodeConfig =
  NodeConfig(
    verbose: false,
    jsonOutput: false,
    dataDir: DefaultDataDir,
    storageBackend: backendFile,
    gasLimit: DefaultGasLimit,
    mempoolCapacity: DefaultMempoolCapacity,
    maxPeers: DefaultMaxPeers,
    validators: defaultValidators()
  )

proc readCliOverrides*(): CliOverrides =
  ## Options are recognized only before the first positional argument.
  var p = initOptParser(
    shortNoVal = {'h', 'v', 'j'},
    longNoVal = @["help", "verbose", "json"]
  )
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "h", "help":
        result.helpRequested = true
      of "v", "verbose":
        result.verbose = true
      of "j", "json":
        result.jsonOutput = true
      of "d", "data-dir":
        if p.val.len == 0:
          result.errorMessage = "data-dir requires a path"
        else:
          result.dataDirProvided = true
          result.dataDir = p.val
      else:
        result.errorMessage = "unknown option: " & p.key
    of cmdArgument:
      break

proc envVerboseEnabled(flag: string): bool =
  flag.toLowerAscii in ["1", "true", "yes", "on"]

proc envVerboseDisabled(flag: string): bool =
  flag.toLowerAscii in ["0", "false", "no", "off"]

proc resolveConfigFrom*(overrides: CliOverrides; envDataDir, envVerbose: string): NodeConfig =
  ## Pure resolver used by the CLI, `main`, and tests.
  result = defaultNodeConfig()
  if envDataDir.len > 0:
    result.dataDir = envDataDir
  if envVerboseEnabled(envVerbose):
    result.verbose = true
  elif envVerboseDisabled(envVerbose):
    result.verbose = false
  # CLI presence wins. Omitting --verbose does not force verbose off.
  if overrides.verbose:
    result.verbose = true
  if overrides.dataDirProvided:
    result.dataDir = overrides.dataDir
  result.jsonOutput = overrides.jsonOutput
  if isMemoryDataDir(result.dataDir):
    result.storageBackend = backendMemory
  else:
    result.storageBackend = backendFile

proc resolveConfig*(overrides: CliOverrides): NodeConfig =
  resolveConfigFrom(overrides, getEnv(EnvDataDir), getEnv(EnvVerbose))
