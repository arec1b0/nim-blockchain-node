# ADR 007: Storage Facades with Memory-Backed Implementations

## Status

Accepted and Implemented

## Context

Prior to Milestone 5:
1. **Concrete Table Coupling**: Subsystems and the composition root (`src/node.nim`) directly referenced concrete database table types (`BlockchainDB` in `src/storage/blockchain_db.nim` and `IndexDB` in `src/storage/index_db.nim`).
2. **DTO Leakage into Business Logic**: Accessing blocks from `BlockchainDB` returned `Option[StoredBlock]` rather than canonical domain `Block` objects. Callers were forced to manually convert storage DTOs or work directly with storage-specific representations.
3. **Impediment to Swappable Storage Backends**: Direct coupling to concrete in-memory tables hindered introducing future persistent or alternative storage backends (e.g., SQLite, RocksDB/LMDB, or append-only file logs) without widespread refactoring of callers across the node, CLI, and integration tests.
4. **Architectural Consistency with Account Persistence**: The codebase already established a clean facade pattern for account storage (`AccountStore` in `src/storage/account_store.nim`), which uses a closure-based facade wrapping runtime swappable backends (`MemoryAccountStore` and `FileAccountStore`). Block and transaction index storage lacked equivalent boundaries.

## Decision

### 1. Introduction of `BlockchainStore` and `IndexStore` Facades

We introduced abstract facade boundaries in `src/storage/blockchain_store.nim` and `src/storage/index_store.nim`:

- **`BlockchainStore`**: A procedural closure-based facade defining the canonical contract for block storage:
  ```nim
  type
    BlockchainStore* = ref object
      name*: string
      addBlockImpl*: proc(blk: Block): bool {.closure.}
      getBlockImpl*: proc(height: BlockHeight): Option[Block] {.closure.}
      getBlockByHashImpl*: proc(hash: BlockHash): Option[Block] {.closure.}
      hasBlockImpl*: proc(height: BlockHeight): bool {.closure.}
      hasBlockWithHashImpl*: proc(hash: BlockHash): bool {.closure.}
      getCurrentHeightImpl*: proc(): BlockHeight {.closure.}
      getLatestBlockImpl*: proc(): Option[Block] {.closure.}
      getBlockCountImpl*: proc(): int {.closure.}
      getBlockRangeImpl*: proc(startHeight, endHeight: BlockHeight): seq[Block] {.closure.}
      rawDBImpl*: proc(): BlockchainDB {.closure.}
  ```
- **`IndexStore`**: A procedural closure-based facade defining the contract for transaction location indexing:
  ```nim
  type
    IndexStore* = ref object
      name*: string
      indexTxImpl*: proc(txId: TransactionId, blockHeight: BlockHeight, txIndex: int): bool {.closure.}
      getTxLocImpl*: proc(txId: TransactionId): Option[TransactionLocation] {.closure.}
      getBlockTxsImpl*: proc(blockHeight: BlockHeight): seq[TransactionId] {.closure.}
      hasTxImpl*: proc(txId: TransactionId): bool {.closure.}
      removeTxImpl*: proc(txId: TransactionId): bool {.closure.}
      isBlockIndexedImpl*: proc(blockHeight: BlockHeight): bool {.closure.}
      getIndexedBlockCountImpl*: proc(): int {.closure.}
      getTxCountImpl*: proc(): int {.closure.}
      clearImpl*: proc() {.closure.}
      rawDBImpl*: proc(): IndexDB {.closure.}
  ```
- All facade operations strictly consume and produce canonical domain types from `src/common/types.nim` (`Block`, `BlockHeight`, `BlockHash`, `BlockData`, `TransactionId`).

### 2. Memory-Backed Implementations (`MemoryBlockchainStore`, `MemoryIndexStore`)

Memory-backed storage implementations wrap the existing, proven in-memory table engines (`BlockchainDB` and `IndexDB`):

- **`MemoryBlockchainStore`**:
  - Instantiated via `newMemoryBlockchainStore(db: BlockchainDB = newBlockchainDB()): MemoryBlockchainStore`.
  - Exposes canonical operations: `addBlock`, `getBlock`, `getBlockByHash`, `hasBlock`, `hasBlockWithHash`, `getCurrentHeight`, `getLatestBlock`, `getBlockCount`, `getBlockRange`.
  - Returns `Option[Block]` containing canonical domain blocks, performing bidirectional conversions with `StoredBlock` DTO internally.
  - Can be exposed as `BlockchainStore` via explicit wrapper `toBlockchainStore(mem)` or implicit converter `toBlockchainStoreConv`.
  - Factory procedure `newBlockchainStore()` instantiates a `MemoryBlockchainStore` and returns its `BlockchainStore` facade.
- **`MemoryIndexStore`**:
  - Instantiated via `newMemoryIndexStore(db: IndexDB = newIndexDB()): MemoryIndexStore`.
  - Exposes operations: `indexTransaction`, `getTransactionLocation`, `getBlockTransactions`, `hasTransaction`, `removeTransaction`, `isBlockIndexed`, `getIndexedBlockCount`, `getTransactionCount`, `clear`.
  - Can be exposed as `IndexStore` via explicit wrapper `toIndexStore(mem)` or implicit converter `toIndexStoreConv`.
  - Factory procedure `newIndexStore()` instantiates a `MemoryIndexStore` and returns its `IndexStore` facade.

### 3. Integration into Composition Root and Subsystems

- **`BlockchainNode`**:
  - Subsystem fields are typed with the facades: `blockchainStore*: BlockchainStore` and `indexStore*: IndexStore`.
  - `newBlockchainNode(cfg)` initializes storage via `newBlockchainStore()` and `newIndexStore()`.
  - Backward compatibility accessors (both getter and setter) are provided for `blockchainDB` and `indexDB`:
    ```nim
    proc blockchainDB*(node: BlockchainNode): BlockchainStore {.inline.} =
      node.blockchainStore

    proc `blockchainDB=`*(node: BlockchainNode, store: BlockchainStore) {.inline.} =
      node.blockchainStore = store

    proc indexDB*(node: BlockchainNode): IndexStore {.inline.} =
      node.indexStore

    proc `indexDB=`*(node: BlockchainNode, store: IndexStore) {.inline.} =
      node.indexStore = store
    ```
- **Lifecycle Execution**:
  - In `node.nim`, `submitAndExecuteTransaction` reads height/previousHash and stores committed blocks via `node.blockchainStore`, and indexes transactions via `node.indexStore`.
- **Domain Property Uniformity**:
  - Added `hash*(blk: Block): BlockHash {.inline.} = blk.id` in `src/common/types.nim`, allowing callers expecting either domain `Block` or DTO `StoredBlock` to access `.hash` identically without ambiguity.
- **Account Persistence**:
  - Account persistence remains untouched via `AccountStore` / `prepareAccountLedger`.

## Consequences

- **Decoupled Architecture**: Subsystems and the composition root depend strictly on `BlockchainStore` and `IndexStore` facades rather than concrete in-memory tables.
- **Pluggability**: Alternate backends (such as disk-backed database engines) can be introduced by creating an adapter and wrapping it in `BlockchainStore` or `IndexStore`, with zero disruption to the transaction lifecycle or node coordination.
- **Complete Backward Compatibility**: Existing call sites using `node.blockchainDB` or `node.indexDB` continue working without modification. All CLI commands, entry points, unit tests, and integration tests remain valid without regression.
- **Clean Memory Management**: Closure-based facades provide reliable polymorphic dispatch under Nim's ORC memory management and multithreaded runtime configurations without runtime class hierarchy limitations.
