# ADR 005: Transaction Lifecycle Alignment

## Status

Accepted and Implemented

## Context

Prior to this work:
1. `cli.nim` (`transferFunds`) executed the VM (`node.vm.applyTransaction(tx)`) before submitting the transaction to the mempool (`node.mempool.addTransaction(tx)`).
2. If the mempool rejected the transaction, it only emitted a warning while leaving the VM state mutated.
3. Transactions were never included into blocks: `node.blockchainDB.getCurrentHeight()` remained 0, `showLatestBlock()` reported "No blocks found", and `node.indexDB` never indexed transactions.
4. Account state persistence was performed without tying updates to block confirmation or indexation.
5. In integration tests (`node_integration_tests.nim`), VM execution was performed prior to block creation and propagation.

## Decision

### 1. Canonical 5-Stage Transaction Lifecycle

We align all execution paths with the documented 5-stage lifecycle:
```text
submit -> mempool validation -> block inclusion -> VM execution -> storage/index update
```

1. **Submit**: The caller validates inputs, loads the keystore (if applicable), and constructs a signed `Transaction`.
2. **Mempool Validation**: The node admits the transaction via `node.mempool.addTransaction(tx)` which calls `authorizeTransaction`. Unsigned, malformed, sender-mismatched, or duplicate transactions are rejected immediately before touching VM state or creating candidate blocks.
3. **Block Inclusion & Propagation**: A candidate block for `nextHeight` is formed with `previousHash` linking to the current blockchain tip. The block is propagated across the injected peer network via `propagateBlock(node.network, blk)`.
4. **VM Execution**: The VM executes the transaction (`node.vm.applyTransaction(tx)`), verifying sender balance, nonce sequence, and gas limits. If VM execution fails, the transaction is evicted from the mempool and block storage is aborted without modifying account state.
5. **Storage & Index Update**: Upon successful VM execution:
   - The block is committed to `node.blockchainDB.addBlock(...)`.
   - The transaction is indexed in `node.indexDB.indexTransaction(...)`.
   - The confirmed transaction is evicted from `node.mempool.removeTransaction(...)`.
   - Account state snapshot is persisted via `node.persistAccountState()`.

### 2. Centralized Node Lifecycle Execution (`src/node.nim`)

- Implemented `submitAndExecuteTransaction(node: BlockchainNode, tx: Transaction): Result[TxExecutionSuccess, TxStageError]` directly on the composition root.
- Re-exported `block_propagation` from `src/node.nim`.
- Updated `cli.nim` `transferFunds` to delegate transaction processing to `node.submitAndExecuteTransaction(tx)`, mapping stage errors to existing CLI `TransferError` definitions without altering CLI commands or JSON output shapes.

### 3. Explicit Deferrals

1. **Full Block Production Loop**: Periodic validator proposal timers and multi-transaction mempool packaging loops are deferred. The current boundary performs synchronous block candidate creation upon transaction submission.
2. **Consensus Finality & Live BFT**: Consensus validation remains bookkeeping (`node.consensus.activeValidatorCount()`). No consensus finality rounds or live network voting loops are implemented.
3. **Durable Block/Index Storage**: Durable persistence of blocks and index records to disk is deferred to Milestone 5 (`BlockchainStore` and `IndexStore` facades).

## Consequences

- The transaction lifecycle strictly guarantees that VM execution occurs only after mempool admission and block inclusion.
- Invalid or unsigned transactions cannot mutate account balances or trigger block creation.
- CLI commands (`block latest`, `block height`, `account balance`) accurately reflect state changes following fund transfers.
- Full backwards compatibility with CLI commands and JSON output format is preserved.
