# ADR 008: CLI Decomposition into Parser, Runtime Service, and Handler Layers

## Status

Accepted and Implemented

## Context

Prior to Milestone 6:
1. **Monolithic CLI Module**: `src/cli.nim` contained 649 lines mixing multiple responsibilities:
   - CLI option parsing (`-v`, `-j`, `-d`, `-h`) and positional argument slicing.
   - Command routing and command help text formatting.
   - Node runtime orchestration and account store management.
   - Business operations (account creation, fund transfers, transaction lifecycle execution).
   - Presentation rendering (plaintext human-readable tables vs. JSON formatting).
2. **Coupling to Global Mutable State**: Command dispatch and service execution relied on module-level globals (`var cliConfig`, `var node`). Unit tests were forced to mutate these globals, initialize the global node, and clean them up in `finally` blocks, precluding concurrent or isolated testing.
3. **Console Side Effects in Operational Logic**: Operational procedures (such as `createAccount` and `transferFunds`) directly emitted strings to `stdout` (`echo`) alongside executing transactions and mutating ledgers. This prevented callers from invoking service operations purely as typed operations without capturing console output.
4. **Architectural Inconsistency**: The node runtime had already been cleanly factored into a composition root (`src/node.nim`) and storage facades (`src/storage/blockchain_store.nim`, `src/storage/index_store.nim`), while the CLI remained a monolithic procedural script.

## Decision

### 1. Decompose CLI into Specialized Submodules under `src/cli/`

We decomposed `src/cli.nim` into three cohesive submodules:

- **`src/cli/cli_parser.nim` (Command Line & Option Parsing)**:
  - Responsible strictly for argument parsing, CLI option extraction, and help text rendering.
  - Pure functions without mutable state:
    - `commandArguments*(params: seq[string] = commandLineParams()): seq[string]`: Filters CLI flags (`-v`, `-j`, `-d`, `--data-dir`, `--data-dir=...`) and captures positional routing tokens.
    - `parseCliOptions*(params: seq[string]): CliOverrides`: Parses options from parameter sequences up to the first positional command, enabling isolated testing of CLI flags.
    - `parseNonNegative*(args: seq[string]): Result[tuple[amount: int, fee: int], string]`: Parses amount and fee arguments from transfer commands.
    - `parseBlockHeight*(arg: string): Result[int, string]`: Validates and parses block height arguments.
    - Help text procedures: `printHelp`, `printNodeHelp`, `printAccountHelp`, `printTransactionHelp`, `printBlockHelp`.

- **`src/cli/cli_service.nim` (Node Runtime Service Wrappers)**:
  - Encapsulates operations against `BlockchainNode` and `NodeConfig` with zero stdout side-effects.
  - Introduces `CliServiceContext* = ref object` holding `node: BlockchainNode` and `config: NodeConfig`.
  - Service procedures:
    - `initCliNode*(cfg: NodeConfig): Result[BlockchainNode, CliInitError]`: Shared node initialization using the composition root (`runtime.newBlockchainNode`).
    - `initCliServiceContext*(cfg: NodeConfig): Result[CliServiceContext, CliInitError]`: Factory for isolated service contexts.
    - `getNodeStatus*(ctx: CliServiceContext): NodeStatusInfo`: Inspects height, active validators, mempool transactions, peers, and gas usage.
    - `getAccountBalance*(ctx: CliServiceContext, address: string): AccountBalanceInfo`: Queries balance and nonce.
    - `listAccounts*(ctx: CliServiceContext): seq[AccountEntry]`: Queries known accounts.
    - `createAccount*(ctx: CliServiceContext): Result[CreatedAccount, KeystoreError]`: Generates keypair, updates VM state, persists ledger, writes keystore, and handles automatic rollback on disk failure without printing.
    - `transferFunds*(ctx: CliServiceContext, fromAddr, toAddr: string, amount: int, fee: int = 10): Result[TransferResult, TransferError]`: Loads keystore, signs transaction, executes canonical 5-stage lifecycle via `node.submitAndExecuteTransaction`, and returns `TransferResult` or typed `TransferError`.
    - `getLatestBlock`, `getBlock`, `getCurrentHeight`: Block retrieval via `node.blockchainStore`.
    - `getPendingTransactions`: Mempool inspection via `node.mempool`.
    - `persistAccountState`, `close`: Resource and persistence lifecycle.

- **`src/cli/cli_handlers.nim` (Command Dispatch and Formatting Handlers)**:
  - Responsible for command dispatch and presentation formatting (JSON vs. plaintext).
  - Handles command dispatch via `processCommand*(ctx: CliServiceContext, args: seq[string]): bool`.
  - Presentation rendering:
    - `renderNodeStatus*(ctx: CliServiceContext)`
    - `renderCreatedAccount*(account: CreatedAccount, jsonOutput: bool)`
    - `renderAccountCreateError*(err: KeystoreError, isMemoryDir: bool, jsonOutput: bool)`
    - `renderBalance*(ctx: CliServiceContext, address: string)`
    - `renderAccountList*(ctx: CliServiceContext)`
    - `renderTransferResult*(res: Result[TransferResult, TransferError], isMemoryDir: bool, jsonOutput: bool): bool`
    - `renderLatestBlock*(ctx: CliServiceContext)`
    - `renderBlock*(ctx: CliServiceContext, height: int)`
    - `renderBlockHeight*(ctx: CliServiceContext)`
    - `renderPendingTransactions*(ctx: CliServiceContext)`
    - `createdAccountJson*(account: CreatedAccount, balance: Balance): JsonNode`
    - `describeTransfer*(err: TransferError): string`
    - `emitText*(message: string, jsonOutput: bool = false)`

### 2. Retain `src/cli.nim` as a Thin Facade and Orchestrator

- Serves as the high-level composition entry point for `src/blockchain_cli.nim` via `runCLI*()`.
- Re-exports symbols from `cli_parser`, `cli_service`, and `cli_handlers`.
- Preserves backward-compatible adapters:
  - Global `var cliConfig*` and `var node*: BlockchainNode`.
  - Legacy procedure overloads `initializeBlockchainNode()`, `persistAccountState()`, `createAccount()`, and `transferFunds(fromAddr, toAddr, amount, fee)`.
  - These adapters instantiate transient `CliServiceContext` instances delegating directly to the decomposed service layer, ensuring existing test suites continue to function without modification.

### 3. Preservation of Invariants and Domain Boundaries

- **Canonical Transaction Lifecycle**: Unchanged order: `submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`.
- **Security & Keystore Hygiene**: Private keys are stored strictly in keystore files and never printed to stdout or included in JSON representations.
- **CLI Commands and JSON Compatibility**: Output formatting, command syntax, flag behavior, and JSON shapes remain identical.

## Consequences

- **Separation of Concerns**: Parsing, runtime interaction, and presentation rendering are decoupled into focused, single-responsibility modules.
- **Isolated Testing**: CLI parsing and service operations can be tested directly with custom inputs and contexts without mutating global variables or capturing stdout.
- **Zero Regressions**: All existing tests and entry points remain 100% compatible.
