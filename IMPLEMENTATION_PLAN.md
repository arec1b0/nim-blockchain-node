# Nim Blockchain Node — Implementation Plan and Progress Note

## Status Overview

The implementation continues the multi-agent improvement plan for the educational Nim blockchain node prototype.

| Milestone | Description | Status | Agent Owner |
|---|---|---|---|
| **Milestone 1** | Shared Node Composition Root & Centralized Defaults | **Completed** | `composition-agent` |
| **Milestone 2** | Network Boundary, Simulated Propagation & Peer Limits | **Completed** | `network-agent` |
| **Milestone 3** | Transaction Lifecycle Alignment | **Completed** | `lifecycle-agent` |
| **Milestone 4** | Type Consolidation (`Block` / `BlockHeight`) | **Completed** | `types-agent` |
| **Milestone 5** | Storage Facades (`BlockchainStore`, `IndexStore`) | **Completed** | `storage-agent` |
| **Milestone 6** | CLI Decomposition | **Completed** | `cli-agent` |
| **Milestone 7** | Documentation & Cursor Rules Refresh | **Completed** | Orchestrator |

---

## Completed Milestones

### Milestone 1 — Shared Composition Root
- Created `src/node.nim` defining `BlockchainNode` (`ref object`) containing all node subsystems (`config`, `consensus`, `accountState`, `globalState`, `blockchainDB`, `indexDB`, `mempool`, `network`, `vm`, `accounts`).
- Factory procedure `newBlockchainNode(cfg: NodeConfig): Result[BlockchainNode, NodeInitError]` centralizes node construction.
- Extended `NodeConfig` in `src/common/config.nim`:
  - `gasLimit`: Natural (`1_000_000`)
  - `mempoolCapacity`: int (`5_000`)
  - `maxPeers`: int (`50`)
  - `validators`: `seq[ValidatorConfig]` (default 2 validators: id 1 with 1000 stake, id 2 with 1500 stake)
  - `storageBackend`: `StorageBackend` enum (`backendFile`, `backendMemory`)
- Unified node construction across `src/main.nim` and `src/cli.nim`, completely eliminating divergent hardcoded defaults.
- Added lifecycle management procs in `src/node.nim`: `close(node)` and `persistAccountState(node)`.
- Re-exported clean component interfaces from `src/node.nim`.

### Milestone 2 — Network Boundary
- Injected `Network` / `Broadcaster` dependency into `propagateBlock(network: Network, blk: Block): PropagationStatus`.
- Removed hardcoded `peersReached: 5`. `peersReached` now dynamically reports `network.connectedPeerCount()`.
- Implemented deterministic simulated propagation latency: `if reached > 0: int64(20 + reached * 10) else: 0`.
- Defined `type Broadcaster* = Network` and `type SimulatedNetwork* = Network` in `src/network/p2p.nim`.
- Enforced `maxPeers` in `src/network/p2p.nim` `addPeer`:
  - Rejects new peers when `network.peers.len >= network.maxPeers` with typed `errResult(PeerId, peerAddMaxPeersReached)`.
  - Replaced silent replacement with explicit error return.
- Maintained backwards-compatible deprecated overload `propagateBlock(blk: Block)`.
- Replaced the placeholder test in `network_tests.nim` with comprehensive deterministic propagation and peer limit tests.

### Milestone 3 — Transaction Lifecycle Alignment
- Aligned transaction execution with the canonical 5-stage lifecycle:
  `submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`.
- Implemented `submitAndExecuteTransaction*(node: BlockchainNode, tx: Transaction): Result[TxExecutionSuccess, TxStageError]` in `src/node.nim`.
- Mempool admission runs first: invalid, unsigned, sender-mismatched, or duplicate transactions fail immediately before VM execution or storage mutation.
- Formed coherent block candidate and propagated via injected `Network` (`propagateBlock(node.network, blk)`).
- VM executes only after mempool admission and block candidate formation. If VM execution fails (e.g. overdraft), the transaction is evicted from the mempool and block commitment is aborted.
- Upon VM success, the block is stored in `node.blockchainDB`, the transaction is indexed in `node.indexDB`, the confirmed transaction is evicted from `node.mempool`, and account state snapshot is persisted.
- Updated `src/cli.nim` `transferFunds*` to delegate to `node.submitAndExecuteTransaction(tx)`, mapping `TxStageError` to CLI `TransferError` and preserving CLI output formatting and JSON shapes.
- Created `docs/adr/005-transaction-lifecycle-alignment.md`.

### Milestone 4 — Type Consolidation (`Block` / `BlockHeight`)
- Consolidated duplicate `Block`, `BlockHeight`, `BlockHash`, `BlockData`, and `BlockId` definitions into the canonical leaf domain types module (`src/common/types.nim`).
- Added canonical block constructor `newBlock*(id: BlockId, height: BlockHeight, data: BlockData, previousHash: BlockHash = "", timestamp: int64 = 0): Block` in `src/common/types.nim`.
- Decoupled storage DTOs: preserved `StoredBlock` in `src/storage/blockchain_db.nim` and `TransactionLocation` in `src/storage/index_db.nim`, typed strictly with canonical `BlockHeight`, `BlockHash`, `BlockData`, and `TransactionId`.
- Added bidirectional conversion procedures `toStoredBlock*(blk: Block): StoredBlock` and `toBlock*(stored: StoredBlock, previousHash: BlockHash = ""): Block` plus convenience overload `addBlock*(db: BlockchainDB, blk: Block): bool` in `src/storage/blockchain_db.nim`.
- Removed duplicate type definitions from `src/storage/blockchain_db.nim`, `src/storage/index_db.nim`, and `src/network/block_propagation.nim`, with clean re-exports for backwards compatibility.
- Cleaned up `src/cli.nim` by eliminating the `blockchain_db.BlockHeight(height)` qualification workaround in favor of canonical `BlockHeight(height)`.
- Updated `TxExecutionSuccess` in `src/node.nim` to use canonical domain types `BlockHeight`, `BlockHash`, and `TransactionId`.
- Created `docs/adr/006-consolidated-block-domain-types.md` and updated `docs/adr/001-canonical-domain-types.md`.

### Milestone 5 — Storage Facades (`BlockchainStore`, `IndexStore`)
- Introduced abstract storage facades `BlockchainStore` in `src/storage/blockchain_store.nim` and `IndexStore` in `src/storage/index_store.nim`.
- Implemented memory-backed adapters `MemoryBlockchainStore` and `MemoryIndexStore` wrapping validated in-memory table engines (`BlockchainDB` and `IndexDB`).
- Ensured all facade operations strictly consume and return canonical domain types from `src/common/types.nim` (`Block`, `BlockHeight`, `BlockHash`, `BlockData`, `TransactionId`) and `TransactionLocation` DTO.
- Added `hash*(blk: Block): BlockHash = blk.id` in `src/common/types.nim` enabling seamless field access across canonical domain `Block` and storage `StoredBlock`.
- Integrated facades into `BlockchainNode` in `src/node.nim` (`blockchainStore*: BlockchainStore`, `indexStore*: IndexStore`).
- Provided full backward compatibility accessors and mutators on `BlockchainNode`: `node.blockchainDB` and `node.indexDB`.
- Maintained canonical 5-stage transaction lifecycle order: `submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`.
- Kept account persistence format and behavior unchanged (`AccountStore` / `prepareAccountLedger`).
- Created ADR 007 (`docs/adr/007-storage-facades.md`).

### Milestone 6 — CLI Decomposition
- Decomposed monolithic `src/cli.nim` (649 lines) into clean, specialized submodules under `src/cli/`:
  - `src/cli/cli_parser.nim`: Argument extraction, CLI option parsing (`-v`, `-j`, `-d`, `-h`), positional routing token filtering (`commandArguments`), transfer parameter extraction (`parseNonNegative`), block height parsing (`parseBlockHeight`), option parsing (`parseCliOptions`), and help formatting.
  - `src/cli/cli_service.nim`: Runtime service layer wrapping `BlockchainNode` and `NodeConfig` via `CliServiceContext`. Exposes typed operations (`initCliNode`, `initCliServiceContext`, `getNodeStatus`, `getAccountBalance`, `listAccounts`, `createAccount`, `transferFunds`, `getLatestBlock`, `getBlock`, `getCurrentHeight`, `getPendingTransactions`, `persistAccountState`, `close`) without console `echo` side effects.
  - `src/cli/cli_handlers.nim`: Command dispatch and presentation layer. Dispatches CLI commands via `processCommand` and formats human-readable text and JSON output (`renderNodeStatus`, `renderCreatedAccount`, `renderAccountCreateError`, `renderBalance`, `renderAccountList`, `renderTransferResult`, `renderLatestBlock`, `renderBlock`, `renderBlockHeight`, `renderPendingTransactions`, `createdAccountJson`, `describeTransfer`, `emitText`).
- Maintained `src/cli.nim` as a thin facade and orchestrator:
  - Entry point `runCLI*()` for `src/blockchain_cli.nim`.
  - Re-exports all submodule symbols and `BlockchainNode`.
  - Isolates global mutable `node` and `cliConfig` as backward-compatibility adapters for legacy tests while internal CLI execution operates purely via `CliServiceContext`.
  - Backward-compatible wrappers for `initializeBlockchainNode()`, `persistAccountState()`, `createAccount()`, and `transferFunds()`.
- Preserved existing CLI syntax, flags, JSON shapes, error messages, and private key security (no private key printed or leaked in JSON).
- Created ADR 008 (`docs/adr/008-cli-decomposition.md`).

### Milestone 7 — Documentation & Cursor Rules Refresh
- Refreshed `.cursor/rules/development-workflow.mdc` to reference `nimble buildAll`, `main.exe` and `blockchain_cli.exe`, updated layer structure (`common`, `core_engine`, `cryptography`, `network`, `storage`, `cli`), and pinned `nimcrypto == 0.6.2`.
- Updated `docs/architecture.md` and `docs/overview.md` to match the implemented architecture, storage facades, canonical domain types, canonical transaction lifecycle, and ADR links (001-008).

---

## Files Changed

| File | Change Description |
|---|---|
| `src/storage/blockchain_store.nim` | Storage facade `BlockchainStore` and memory implementation `MemoryBlockchainStore`. Unified canonical domain block storage API (`getBlock`, `addBlock`, `getCurrentHeight`, `getLatestBlock`, `hasBlock`, `getBlockRange`). |
| `src/storage/index_store.nim` | Storage facade `IndexStore` and memory implementation `MemoryIndexStore`. Canonical transaction location indexing API (`indexTransaction`, `getTransactionLocation`, `getBlockTransactions`, `hasTransaction`, `removeTransaction`). |
| `src/common/types.nim` | Canonical block domain types (`BlockHeight`, `BlockHash`, `BlockData`, `BlockId`, `Block`, `newBlock`) and property accessor `hash*(blk: Block): BlockHash`. |
| `src/storage/blockchain_db.nim` | Removed duplicate `BlockHeight`, `BlockData`, `BlockHash`. Retained `StoredBlock` DTO. Added `toStoredBlock`, `toBlock`, `addBlock(blk)` overload, and re-exported canonical types. |
| `src/storage/index_db.nim` | Removed duplicate `TransactionId` and `BlockHeight`. Retained `TransactionLocation` DTO. Re-exported canonical types. |
| `src/network/block_propagation.nim` | Removed duplicate `BlockId`, `BlockData`, `BlockHeight`, `Block`, and `newBlock`. Re-exported canonical types from `common/types`. |
| `src/node.nim` | Integrated `BlockchainStore` and `IndexStore` into `BlockchainNode`. Added backward compatibility accessors for `blockchainDB` and `indexDB`. Adopted facades in `submitAndExecuteTransaction`. |
| `src/cli.nim` | Thin facade orchestrator delegating to `cli_parser`, `cli_service`, and `cli_handlers`. Re-exports symbols and isolates global `node` adapter. |
| `src/cli/cli_parser.nim` | Command line argument parsing, CLI option extraction, token filtering, parameter parsing, and help text. |
| `src/cli/cli_service.nim` | Runtime service wrappers encapsulating `BlockchainNode` and `NodeConfig` operations via `CliServiceContext` without console side-effects. |
| `src/cli/cli_handlers.nim` | Command dispatch (`processCommand`) and presentation rendering for plaintext and JSON outputs. |
| `src/common/config.nim` | Extended `NodeConfig` with `storageBackend`, `gasLimit`, `mempoolCapacity`, `maxPeers`, `validators`. Centralized defaults and synchronization with `:memory:`. |
| `src/main.nim` | Refactored to compose components via `newBlockchainNode(cfg)` and inject `node.network` into `propagateBlock`. |
| `src/network/p2p.nim` | Added `PeerAddError`, enforced `maxPeers` in `addPeer`, added `SimulatedNetwork` alias and `newSimulatedNetwork`. |
| `tests/unit_tests/storage_tests.nim` | Added tests for `MemoryBlockchainStore` (add, get, height, latest, range, DTO conversion) and `MemoryIndexStore` (index, query location, block txs, remove, clear) and their facades. |
| `tests/integration_tests/node_integration_tests.nim` | Added integration tests for storage facade boundary integration with the canonical lifecycle, backward compatibility accessors, and custom tracking facade substitution. |
| `tests/unit_tests/cli_tests.nim` | Tests verifying centralized defaults, equivalence of entry points, and end-to-end `transferFunds` lifecycle. |
| `tests/unit_tests/network_tests.nim` | Tests for peer management up to/beyond `maxPeers`, injected network propagation, deterministic latency, and boundary validation. |
| `docs/adr/001-canonical-domain-types.md` | Marked as fully implemented and linked to ADR 006. |
| `docs/adr/004-composition-root-and-network-boundary.md` | Architecture Decision Record for Milestones 1 and 2. |
| `docs/adr/005-transaction-lifecycle-alignment.md` | Architecture Decision Record for Milestone 3 (Transaction Lifecycle Alignment). |
| `docs/adr/006-consolidated-block-domain-types.md` | Architecture Decision Record for Milestone 4 (Consolidated Block Domain Types and Storage DTO Separation). |
| `docs/adr/007-storage-facades.md` | Architecture Decision Record for Milestone 5 (Storage Facades with Memory-Backed Implementations). |
| `docs/adr/008-cli-decomposition.md` | Architecture Decision Record for Milestone 6 (CLI Decomposition into Parser, Service, and Handler Layers). |
| `docs/architecture.md` | Updated layer descriptions, component interactions, and transaction lifecycle. |
| `docs/overview.md` | Updated architectural overview, network communication, and transaction flow. |

---

## Tests Added and Verified

All tests pass under `nimble test` and executables compile with `nimble buildAll`.

1. **MemoryBlockchainStore & Facade Interoperability** (`tests/unit_tests/storage_tests.nim`):
   - Proves `MemoryBlockchainStore` adds canonical blocks, rejects duplicate heights, queries by height and hash, tracks current height and latest block, and retrieves height ranges.
   - Proves `BlockchainStore` facade provides transparent polymorphic access across all operations.
2. **MemoryIndexStore & Facade Interoperability** (`tests/unit_tests/storage_tests.nim`):
   - Proves `MemoryIndexStore` indexes transactions, queries locations, lists block transactions, checks presence, removes transactions, and clears indexes.
   - Proves `IndexStore` facade provides transparent polymorphic access across all operations.
3. **Storage Facade Boundary Integration with Node Lifecycle** (`tests/integration_tests/node_integration_tests.nim`):
   - Proves `submitAndExecuteTransaction` writes committed blocks to `node.blockchainStore` and indexes transactions in `node.indexStore`.
   - Proves backward compatibility accessors `node.blockchainDB` and `node.indexDB` observe identical state.
   - Proves custom storage facade substitution (swappable tracking facade) integrates seamlessly into node execution.
4. **Canonical Block & Storage DTO Integration** (`tests/unit_tests/storage_tests.nim`):
   - Proves `BlockchainDB` stores and retrieves blocks using canonical `BlockHeight`, `BlockHash`, `BlockData`, and `Block`.
   - Proves bidirectional conversion between canonical `Block` and `StoredBlock` DTO (`toStoredBlock` and `toBlock`).
   - Proves `addBlock(canonicalBlk)` overload correctly tracks height, hash index, and payload.
5. **Canonical Types across IndexDB** (`tests/unit_tests/storage_tests.nim`):
   - Proves `IndexDB` indexes and retrieves using canonical `TransactionId` and `BlockHeight`.
   - Verifies transactions mapped to block heights without type casting or shadowing.
6. **Cross-Subsystem Unambiguous Import Test** (`tests/integration_tests/node_integration_tests.nim`):
   - Proves simultaneous import of `blockchain_db`, `index_db`, `block_propagation`, and `common/types` does not produce ambiguous identifier collisions.
   - Proves `Block`, `BlockHeight`, `BlockHash`, `BlockData`, and `TransactionId` operate interchangeably across network, storage, index, and composition layers.
7. **Shared Defaults Verification** (`tests/unit_tests/cli_tests.nim`):
   - Proves `defaultNodeConfig()` has `gasLimit = 1_000_000`, `mempoolCapacity = 5_000`, `maxPeers = 50`, `validators.len = 2`.
   - Proves `newBlockchainNode(memCfg)` reflects these defaults in submodules (`vm.gasLimit`, `mempool.maxSize`, `network.maxPeers`, `consensus.activeValidatorCount()`).
8. **Equivalence of Entry Point Runtime Configurations** (`tests/unit_tests/cli_tests.nim`):
   - Proves identical CLI overrides produce identical configuration for `main` and `cli`.
   - Proves `mainNode` and `cliNode` runtime states have identical gas limits, mempool capacities, max peers, and validator counts.
9. **Peer Limits Enforcement** (`tests/unit_tests/network_tests.nim`):
   - Adding peers up to `maxPeers`.
   - Rejecting peer additions beyond `maxPeers` with `peerAddMaxPeersReached`.
10. **Injected Network Propagation** (`tests/unit_tests/network_tests.nim`):
    - Propagating with 0 connected peers yields `peersReached == 0`.
    - Propagating with connected peers accurately reflects `connectedPeerCount()`.
    - Verifying simulated latency is deterministic.
    - Validating nil network rejection (`NetworkError`) and empty block rejection (`Failed`).
11. **Canonical Transaction Lifecycle via Node** (`tests/integration_tests/node_integration_tests.nim`):
    - Proves full lifecycle order: `submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`.
    - Proves block is committed at height 1, transaction indexed in `indexDB`, mempool cleared, and balances debited/credited.
    - Proves unsigned/missing-key transactions are rejected at mempool validation before VM execution.
    - Proves VM execution failure (e.g. overdraft) evicts transaction from mempool, aborts block commitment, and leaves state untouched.
    - Proves duplicate transaction submission is rejected at mempool admission.
12. **CLI `transferFunds` Integration** (`tests/unit_tests/cli_tests.nim`):
    - Proves `transferFunds` commits block, updates index, clears mempool, and synchronizes balances.
    - Proves overdraft transfers reject before block creation.
    - Proves missing keystores reject before VM execution.
13. **CLI Argument and Option Parsing** (`tests/unit_tests/cli_tests.nim`):
    - Proves `commandArguments` extracts command tokens and skips options (`-d`, `--data-dir`, `-v`, `-j`, `-h`).
    - Proves `parseNonNegative` validates transfer amount and fee integers and handles defaults.
    - Proves `parseBlockHeight` validates non-negative heights and rejects malformed values.
    - Proves `parseCliOptions` parses options in isolation and detects errors.
14. **Node Runtime Service Isolation** (`tests/unit_tests/cli_tests.nim`):
    - Proves `initCliServiceContext` instantiates isolated runtime context without global state.
    - Proves `getNodeStatus`, `getAccountBalance`, and `listAccounts` inspect state via `CliServiceContext`.
    - Proves `CliServiceContext` executes full canonical lifecycle independently of globals (`createAccount -> fund -> transfer -> block -> index`).
15. **CLI Command Dispatch and Presentation** (`tests/unit_tests/cli_tests.nim`):
    - Proves `processCommand` dispatches valid commands (`node`, `account`, `block`, `transaction`, `help`) and rejects invalid subcommands.
    - Proves `describeTransfer` provides distinct human-readable error descriptions.
    - Proves `createdAccountJson` produces compliant JSON schema without private keys.

---

## Open Deferrals (Remaining Workstreams)

The following areas are intentionally deferred to subsequent milestones:

1. **Full Block Production Loop & Periodic Mining**:
   - The current admission-and-execution boundary produces a block synchronously per submitted transaction. Continuous background mining and multi-transaction block assembly loops remain deferred.
2. **Consensus Finality & Live BFT Protocol**:
   - Consensus validators remain bookkeeping entities (`consensus.activeValidatorCount()`). Live consensus rounds, proposal voting, and finality checkpoints remain deferred.
3. **Durable Disk Storage Backends**:
   - Durable on-disk block and index storage implementations (e.g., SQLite, LMDB, or append-only flat-file storage) can now be implemented behind the `BlockchainStore` and `IndexStore` facades introduced in Milestone 5.

---

## Integration Risks & Rollback Strategy

### Identified Risks
- **Global mutable `node` adapter**: The global `node` and `cliConfig` in `src/cli.nim` remain as backward-compatibility adapters for legacy test suites. Any new code should strictly use `CliServiceContext` or inject `BlockchainNode`.
- **Synchronous single-transaction block creation**: In this educational prototype, each successful transfer creates a block candidate. Transition to a pooled multi-transaction block production loop is deferred to consensus enhancements.

### Rollback Strategy
- Every milestone has clean commit boundaries. If a rollback of Milestone 6 is required:
  - Restore `src/cli.nim` and delete `src/cli/` directory.
  - Revert `tests/unit_tests/cli_tests.nim` to previous commit.
  - Prior milestones (Milestones 1-5) remain fully intact and operational.
