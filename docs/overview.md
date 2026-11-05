# Nim Blockchain Node Project Overview

## Introduction

This document is a high-level map of an **educational prototype**. The code is organized in layers so the transaction path is readable. It is not a production node: the signature scheme is `demo-sha256`, zero-knowledge proofs are placeholders, and networking is simulated. Account balances and nonces can be reloaded from `accounts.json`. Blocks, the index, the mempool, and peers are in memory. `main` initializes and exits.

## 🛠️ Architectural Overview
The node follows a modular, layered architecture, clearly divided into core components, each responsible for specific functionalities:

### 1. Core Engine Layer
- **Consensus**: In-memory validator bookkeeping and a quorum helper. Not a BFT implementation and not finality.
- **Virtual Machine (VM)**: Applies value transfers with a fixed gas cost. `validateTransaction` rejects unsigned and invalid demo signatures before balance and nonce checks.
- **State Management**: Account balances and nonces in a `StateDB` value. A file-backed `AccountStore` can snapshot that value. See [ADR 003](adr/003-account-store.md).

### 2. Cryptography Layer
- **Key Management**: Random seed and `signMessage` for `demo-sha256`. It does not verify signatures.
- **Signature Verification**: The only verification API. `publicKey = hex(SHA-256(privateKey))`, `signature = hex(SHA-256(publicKey || message))`. Not Ed25519. Forgeable if the public key is known. See [ADR 002](adr/002-signature-authorization.md).
- **Zero-Knowledge Proofs**: The string prefix `zk_proof_`. Not a proof system.

### 3. Network Layer
- **P2P Communication**: In-memory peer table (`Network` / `SimulatedNetwork`). Enforces `maxPeers` on `addPeer` with typed errors. See [ADR 004](adr/004-composition-root-and-network-boundary.md).
- **Mempool Management**: Fee ordering plus the same `authorizeTransaction` check the VM uses. Balance and nonce are not checked here.
- **Block Propagation**: Simulated broadcast using an injected `Network` or `Broadcaster` dependency. `peersReached` reflects the count of currently connected peers, with deterministic latency.

### 4. Storage Layer
Blocks, the transaction index, and the global key-value map are in-memory. Account balances and nonces can be persisted:
- **BlockchainStore** (`blockchain_store.nim`): Abstract facade and `MemoryBlockchainStore` implementation using canonical domain `Block` objects. See [ADR 007](adr/007-storage-facades.md).
- **IndexStore** (`index_store.nim`): Abstract facade and `MemoryIndexStore` implementation for transaction location indexing. See [ADR 007](adr/007-storage-facades.md).
- **AccountStore** (`account_store.nim`): Loads and saves the account ledger. `:memory:` keeps it in the process. Any other data directory uses `<dataDir>/accounts.json` (version 1). A failed load does not overwrite the file. See [ADR 003](adr/003-account-store.md).
- **GlobalStateStore** (`state_db.nim`): In-memory key-value map (not the account ledger, and not a versioned database).

### 5. Node Composition Root (`src/node.nim`)
- Shared composition factory `newBlockchainNode(cfg: NodeConfig)` constructs `BlockchainNode`.
- Unifies defaults: gas limit (`1,000,000`), mempool capacity (`5,000`), max peers (`50`), active validators (`2`).
- Both `main.nim` and `cli.nim` compose through this root. See [ADR 004](adr/004-composition-root-and-network-boundary.md).
- Implements `submitAndExecuteTransaction` enforcing the 5-stage lifecycle. See [ADR 005](adr/005-transaction-lifecycle-alignment.md).

### 6. CLI Subsystem (`src/cli/`, `src/cli.nim`)
- Decomposed into `cli_parser.nim`, `cli_service.nim`, `cli_handlers.nim`, and facade `cli.nim`.
- Pure parsing, isolated `CliServiceContext`, and clean presentation formatting without business logic coupling. See [ADR 008](adr/008-cli-decomposition.md).

### Common Domain Types
- `src/common/types.nim`: Canonical `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`, `BlockHeight`, `BlockHash`, `BlockData`, `BlockId`, `Block`, and constructor `newBlock`.
- See [ADR 001](adr/001-canonical-domain-types.md) and [ADR 006](adr/006-consolidated-block-domain-types.md).

## 🔒 Cryptographic Considerations
- One verification procedure serves the VM and the mempool. The scheme is `demo-sha256`, a SHA-256 teaching placeholder, not Ed25519 or secp256k1, and it is not unforgeable.
- Private keys are stored in a plaintext keystore under the configured data directory and are omitted from CLI JSON and logs. On Windows the file cannot be given a POSIX owner-only mode.
- Zero-knowledge code remains a string placeholder.

## 🚧 Module Breakdown
### Common
- `common/types.nim`: Canonical domain types (`Transaction`, `Block`, etc.).
- `common/config.nim`: `NodeConfig`. Precedence is CLI flags, then `NIM_NODE_DATA_DIR` / `NIM_NODE_VERBOSE`, then defaults. Centralized defaults for gas, validators, mempool, and peers.
- `common/result.nim`: `Status` and `Result` for validation, admission, transfer, and init.
- `common/logsetup.nim`: one-time `std/logging` setup called from `main` and `runCLI`.

### Core Engine
- `consensus.nim`: In-memory validator set and a quorum count. Not block production and not finality.
- `state_management.nim`: Account-ledger `StateDB` (balances and nonces). The VM holds a value copy.
- `vm.nim`: Manages transaction execution, accounting for computational resources via gas metering.

### Cryptographic Security
- `key_management.nim`: Demo key generation and signing only.
- `signature_verification.nim`: The only `verifySignature` / `authorizeTransaction` implementation.
- `keystore.nim`: Plaintext educational keystore. Not encrypted.
- `zk_proofs.nim`: String-prefix placeholder. Not a real proof system.

### Network Communication
- `p2p.nim`: In-memory peer table. `maxPeers` is strictly enforced on `addPeer`.
- `mempool.nim`: Pending transactions. Admission verifies the demo signature, then enforces id uniqueness and capacity.
- `block_propagation.nim`: Block propagation taking an injected `Network`/`Broadcaster` dependency.

### Persistent Storage
- `blockchain_store.nim`: `BlockchainStore` facade and `MemoryBlockchainStore` adapter.
- `index_store.nim`: `IndexStore` facade and `MemoryIndexStore` adapter.
- `account_store.nim`: Facade. `openAccountStore` binds memory or the JSON snapshot.
- `memory_account_store.nim`: In-process `StateDB`. Not durable.
- `file_account_store.nim`: Versioned `accounts.json` snapshot. Not a database engine.
- `blockchain_db.nim`: In-memory block map and `StoredBlock` DTO.
- `index_db.nim`: In-memory transaction index and `TransactionLocation` DTO.
- `state_db.nim`: In-memory `GlobalStateStore`. Not the account ledger.

### Composition Root & CLI
- `node.nim`: Centralized composition of `BlockchainNode`, lifecycle methods, and unified defaults.
- `cli/cli_parser.nim`, `cli/cli_service.nim`, `cli/cli_handlers.nim`, `cli.nim`: Decomposed CLI architecture.

## 🚀 Node Initialization Sequence (main.nim / cli.nim)
Both `main.nim` and `cli.nim` now construct the node through `newBlockchainNode(cfg)` in `src/node.nim`.
- Both entry points resolve `NodeConfig`, configure logging, initialize the shared node, execute their entry point task, and close the node.
- A missing `accounts.json` seeds genesis with balance 1000000 and saves that snapshot. An existing snapshot is loaded and genesis is not reset. `:memory:` seeds genesis in the process only.
- `main` adds one signed sample transaction to the mempool, creates and propagates the genesis block through the node's network, indexes it, and exits.
- The CLI passes commands through the shared node, executing transactions through the canonical 5-stage lifecycle (`submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`), and persists state after mutating operations.

## 🔒 Security and Cryptographic Considerations
- Sign and verify now share `demo-sha256`. That stops empty and non-matching signatures from moving balances. It does not stop someone who knows the public key from forging one.
- Logging is `std/logging` with `--verbose` mapped to debug. Logs must not contain private keys or signatures.
- Initialization, peer registration, and the transfer path return `Status` / `Result` instead of bare booleans.

## 🚧 Potential Areas for Improvement
- Replace `demo-sha256` with Ed25519 or secp256k1.
- Replace the zero-knowledge placeholder.
- Implement pluggable durable disk storage backends (e.g. SQLite, LMDB, append-only logs) behind `BlockchainStore` and `IndexStore`.
- Encrypt or otherwise protect the keystore.
- Continuous multi-transaction block production loop and mining timers.
- Live BFT consensus protocol and finality checkpoints.

---

This overview matches the educational prototype. It is not a production architecture.
