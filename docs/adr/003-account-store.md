# ADR 003: Account Store and JSON Snapshot

## Status

Accepted

## Context

Account balances lived only in an in-memory `StateDB`. `--data-dir` selected the keystore directory and did not reload balances. `main` and the CLI each built a fresh genesis ledger, so a restart discarded every transfer.

Blocks, the transaction index, the mempool, and peers are still process-local. This decision does not turn those into durable storage, and it does not add a database engine.

## Decision

### Boundary

Callers open an `AccountStore` from `dataDir`. The facade's `load`, `save`, and `close` closures are bound at runtime:

- `:memory:` binds `MemoryAccountStore`, which holds one `StateDB` and writes nothing.
- Any other path binds `FileAccountStore`.

A Nim concept is not used. Concepts are fixed at compile time, and the backend is chosen from a string. The VM keeps executing against a `StateDB` value. It does not import the store. After a successful account creation or transfer, the CLI saves `vm.state` through the facade. `StateDB` stays a value type.

`MemoryAccountStore` uses the existing ledger procedures. There is no second account type.

### Data directory

The default remains `data`. An omitted `--data-dir` is not memory-only, because the keystore already writes under `data`.

`:memory:` is a sentinel, not a directory. Startup does not call `createDir` on it. Keystore save and load reject it before creating a path.

### File format

Path: `<dataDir>/accounts.json`.

Version 1 fields:

- `format`: `nim-node-accounts`
- `version`: `1`
- `accounts`: array of `{address, balance, nonce}`, sorted by address, with no duplicate addresses
- `checksum`: lowercase hex SHA-256 of the compact JSON of `accounts` only

The checksum detects accidental edits. It is not authentication and it is not a crash-consistency proof.

Writes go to `accounts.json.tmp` in the same directory, are flushed, then replace the destination (POSIX `rename`, or Windows `MoveFileExW` with replace and write-through). On failure, only the temp file is removed. Startup does not read a leftover `.tmp`.

A missing file is a new store: genesis is funded with balance `1000000` and the snapshot is saved. A present file is loaded as-is, including a valid empty account list. Empty, malformed, unknown-version, and checksum-mismatched files return an error and are not overwritten. A ledger that contains an empty address is not written, because the reader rejects that file. The VM also rejects an empty recipient before it moves balances.

`close` does not write again. `save` already flushed.

### What this does not do

- Blocks, the transaction index, the mempool, validator votes, and peers still die with the process.
- `propagateBlock` still returns success with `peersReached` fixed at 5. It does not take a `Network`. `addPeer` still does not enforce `maxPeers`.
- Consensus is still a validator table and a quorum count. It does not produce blocks and it is not finality.
- There is no file lock. Two processes can overwrite one snapshot.
- A failed save after the VM has applied a transfer leaves that process's memory ahead of the file. The command fails and does not report success. This change does not roll the VM back.
- `getTransactionsByFee` still copies and sorts the mempool. `VM.getState` still returns the ledger by value. Those are follow-ups, not part of this snapshot.

### Deferred CLI split

`cli.nim` still parses arguments, runs commands, and owns node construction. The intended split is:

- `src/node_runtime.nim` — `BlockchainNode`, store open/load/save, and transfer application without stdout.
- `src/cli_commands.nim` — help text, command dispatch, and rendering.
- `src/cli.nim` — `runCLI` only.
- Argument definitions stay in `src/common/config.nim`.

Also deferred: `BlockchainStore` and `IndexStore`, a database engine, a long-running `node start` loop, and `proposeBlock`.

## Consequences

- `--data-dir` controls the account snapshot and the keystore. `:memory:` controls neither files.
- The first successful file-backed start creates version 1. No older account file exists to migrate. Existing keystore files are untouched.
- Deleting `accounts.json` makes the next start seed genesis again. Keystore files should not be deleted as part of that rollback.
- `main` no longer constructs the unused `GlobalStateStore`. The CLI object still has `globalState` and `indexDB` fields so current tests keep compiling. Command behavior does not read them.
- Each CLI invocation loads, runs one command, and exits. Restart safety is the snapshot, not a resident process.
