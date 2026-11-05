# ADR 006: Consolidated Block Domain Types and Storage DTO Separation

## Status

Accepted and Implemented

## Context

Prior to Milestone 4, the codebase suffered from duplicate and misplaced block domain definitions:

1. **Layer Inversion & Misplaced Ownership**: `Block` was defined inside `src/network/block_propagation.nim`, a network transport module. Modules requiring the fundamental domain abstraction of a block (such as the composition root `src/node.nim` or entry points) had to depend on network propagation simply to construct or reference a block.
2. **Redundant Primitive Aliases**:
   - `BlockHeight* = Natural` was defined independently in `src/network/block_propagation.nim`, `src/storage/blockchain_db.nim`, and `src/storage/index_db.nim`.
   - `BlockData* = string` was defined in both `block_propagation.nim` and `blockchain_db.nim`.
   - `BlockHash* = string` and `BlockId* = string` were declared redundantly.
   - `TransactionId* = string` was defined in `src/storage/index_db.nim` despite already existing canonically in `src/common/types.nim`.
3. **Ambiguity and Qualification Workarounds**: Importing storage and network modules together resulted in compiler collisions on `BlockHeight`, forcing workarounds like explicit module qualification in `src/cli.nim` (`blockchain_db.BlockHeight(height)`).
4. **Unclear Storage DTO Boundary**: The relationship between transient network/domain blocks and stored database blocks was implicit rather than cleanly decoupled.

## Decision

### 1. Canonical Domain Types in Leaf Module (`src/common/types.nim`)

All core block-related domain types are consolidated into `src/common/types.nim`, which serves as a leaf module with zero inward dependencies on core engine, network, storage, or cryptography:

- `BlockHeight* = Natural`: Authoritative blockchain height index.
- `BlockHash* = string`: Cryptographic hash / tip pointer string.
- `BlockData* = string`: Block payload data.
- `BlockId* = string`: Canonical block identifier.
- `Block* = object`: Authoritative domain representation of a blockchain block:
  - `id*: BlockId`
  - `height*: BlockHeight`
  - `data*: BlockData`
  - `timestamp*: int64`
  - `previousHash*: BlockHash`
- `newBlock*(id: BlockId, height: BlockHeight, data: BlockData, previousHash: BlockHash = "", timestamp: int64 = 0): Block`: Universal constructor for canonical domain blocks.

### 2. Separation and Typing of Storage DTOs

Storage-specific data transfer objects remain owned by their respective storage modules, but their fields are strictly typed with the canonical domain types:

- **`StoredBlock*`** remains defined in `src/storage/blockchain_db.nim`:
  ```nim
  StoredBlock* = object
    height*: BlockHeight
    data*: BlockData
    hash*: BlockHash
    timestamp*: int64
  ```
- **Bidirectional Mappings**: `src/storage/blockchain_db.nim` provides explicit conversion procedures:
  - `toStoredBlock*(blk: Block): StoredBlock`
  - `toBlock*(stored: StoredBlock, previousHash: BlockHash = ""): Block`
  - `addBlock*(db: BlockchainDB, blk: Block): bool`: Convenience overload for storing domain blocks directly.
- **`TransactionLocation*`** remains in `src/storage/index_db.nim`, using canonical `BlockHeight` and `TransactionId`:
  ```nim
  TransactionLocation* = object
    blockHeight*: BlockHeight
    transactionIndex*: int
  ```

### 3. Removal of Duplicates & Clean Re-Exports

- Removed duplicate type definitions from:
  - `src/storage/blockchain_db.nim` (`BlockHeight`, `BlockData`, `BlockHash`)
  - `src/storage/index_db.nim` (`TransactionId`, `BlockHeight`)
  - `src/network/block_propagation.nim` (`BlockId`, `BlockData`, `BlockHeight`, `Block`, `newBlock`)
- Storage and network modules re-export canonical types via `export types.<Symbol>` so consumers depending on these modules preserve backward compatibility without type shadowing.
- `src/cli.nim` eliminated the `blockchain_db.BlockHeight` qualification in favor of canonical `BlockHeight(height)`.
- `src/node.nim` updated `TxExecutionSuccess` fields to use canonical `BlockHeight`, `BlockHash`, and `TransactionId`.

## Consequences

- **Strict Layering**: Subsystems depend downward on `common/types`. No layer-inversion or network coupling is required to work with `Block`.
- **Zero Ambiguity**: Simultaneous imports of `blockchain_db`, `index_db`, `block_propagation`, and `types` compile cleanly without identifier collisions or required module qualification.
- **Domain vs Storage Decoupling**: Domain models and storage DTOs have explicit boundaries and bidirectional converters, preparing the codebase for Milestone 5 storage facades (`BlockchainStore`, `IndexStore`).
- **Complete Test Verification**: All unit and integration test suites pass, with targeted unit tests validating type uniformity and storage DTO roundtrips.
