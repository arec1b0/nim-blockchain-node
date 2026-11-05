# Nim Blockchain Node Architecture

## 🔍 Introduction

This document describes the module layout of an **educational prototype**. The node is not production-ready: signatures are a SHA-256 teaching scheme, zero-knowledge proofs are string placeholders, and networking is simulated. Account balances and nonces can be reloaded from a JSON snapshot. Blocks, the transaction index, the mempool, and peers are currently in memory.

It is not a claim of production consensus, cryptography, networking, or durable storage.

## 🧱 Architectural Layers
The architecture is composed of distinct modules so each layer has a readable boundary. Several modules are placeholders; those limits are stated in the sections below.

### 0. Common Domain Types (`src/common/types.nim`)

Canonical shared domain types for cross-layer use:

- `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`
- `BlockHeight`, `BlockHash`, `BlockData`, `BlockId`, `Block`, `newBlock`, `hash`

This module is a strict leaf dependency and must not import higher-level layers. The VM and mempool both use the same canonical `Transaction` type, including `publicKey` and `signature`. All subsystems use the same canonical `Block` and `BlockHeight` types. Storage-specific DTOs (`StoredBlock`, `TransactionLocation`) remain separate. See [ADR 001](adr/001-canonical-domain-types.md) and [ADR 006](adr/006-consolidated-block-domain-types.md).

### 1. Core Engine Layer

#### **Consensus Module**
- In-memory validator set, stake numbers, and a quorum helper.
- Not a Byzantine fault tolerant protocol and not a live finality gadget.

#### **Virtual Machine (VM) Module**
- Applies value transfers with a fixed gas cost.
- `validateTransaction` rejects unsigned and invalid `demo-sha256` signatures before it checks amount, balance, or nonce.
- Does not execute general smart contracts.

#### **State Management Module**
- Account balances and nonces in a `StateDB` value. The VM mutates its own copy.
- `AccountStore` snapshots that value. See [ADR 003](adr/003-account-store.md).
- No concurrency control and no state pruning.

### 2. Cryptography Layer

#### **Key Management Module**
- Generates a random 32-byte seed and a SHA-256 public key.
- Signs with the demo scheme. It does not export `verifySignature`.
- Does not store keys. The CLI keystore module does that, in plaintext.

#### **Signature Verification Module**
- The only verification API (`verifySignature`, `authorizeTransaction`).
- Scheme name: `demo-sha256`. Signature = hex(SHA-256(public key bytes || message bytes)).
- Not Ed25519 or secp256k1. Anyone who knows the public key can forge a signature.
- The signed payload is `id|sender|receiver|amount|fee|nonce`. The sender must match the first 8 hex characters of the public key. See [ADR 002](adr/002-signature-authorization.md).

#### **Zero-Knowledge Proof Module**
- String prefix placeholder (`zk_proof_` + data). Not a zk-SNARK or zk-STARK.
- Left unchanged by the signature work. Do not treat it as a privacy system.

### 3. Network Layer

#### **P2P Communication Module**
- In-memory peer list (`Network` / `SimulatedNetwork`). No sockets, no NAT traversal, and no peer authentication.
- Enforces `maxPeers` limit in `addPeer`, returning `Result[PeerId, PeerAddError]` (`peerAddMaxPeersReached` upon exceeding capacity). See [ADR 004](adr/004-composition-root-and-network-boundary.md).

#### **Mempool Module**
- Stores pending transactions and orders them by fee.
- `addTransaction` calls the same `authorizeTransaction` API as the VM and rejects unsigned or invalid demo signatures.
- It does not check balance, nonce, amount, or gas. Those checks stay in the VM.

#### **Block Propagation Module**
- Simulated block distribution across the network.
- `propagateBlock` receives an injected `Network` or `Broadcaster` dependency.
- `peersReached` reflects the count of currently connected peers (`network.connectedPeerCount()`), with deterministic simulated latency.
- Validates block payload and network existence before reporting propagation status.

### 4. Storage Layer

#### **BlockchainStore Facade & Memory Adapter** (`src/storage/blockchain_store.nim`)
- Procedural closure facade `BlockchainStore` defining the block persistence contract using canonical `Block` domain types.
- `MemoryBlockchainStore` wraps `BlockchainDB` in-memory table.
- Converts between canonical `Block` domain objects and `StoredBlock` persistence DTOs. See [ADR 007](adr/007-storage-facades.md).

#### **IndexStore Facade & Memory Adapter** (`src/storage/index_store.nim`)
- Procedural closure facade `IndexStore` defining the transaction indexing contract using canonical `TransactionId` and `BlockHeight`.
- `MemoryIndexStore` wraps `IndexDB` in-memory table. See [ADR 007](adr/007-storage-facades.md).

#### **Global State Store Module** (`GlobalStateStore`, `src/storage/state_db.nim`)
- In-memory key-value map, separate from the account-ledger `StateDB`.
- Not a historical state database.

#### **Account Store** (`src/storage/account_store.nim`)
- Facade in `storage/account_store.nim`. `openAccountStore` selects the backend from `dataDir`.
- `MemoryAccountStore` keeps one `StateDB` in the process. `--data-dir=:memory:` selects it and does not create a directory.
- `FileAccountStore` writes `<dataDir>/accounts.json` (format `nim-node-accounts`, version 1) by flushing a temp file and replacing the destination in the same directory.
- A checksum detects accidental edits. A failed load leaves the existing file in place. This is not a database and not crash-proof beyond that replace. See [ADR 003](adr/003-account-store.md).

### 5. Node Composition Root (`src/node.nim`)
- Defines `BlockchainNode` (`ref object`) containing all node subsystems and runtime state.
- `newBlockchainNode(cfg: NodeConfig)` provides a shared composition root for both `main.nim` and `cli.nim`.
- Centralizes runtime defaults across entry points: gas limit (1,000,000), mempool capacity (5,000), max peers (50), and active validators (2).
- Provides lifecycle helpers `close(node)`, `persistAccountState(node)`, and `submitAndExecuteTransaction(node, tx)`. See [ADR 004](adr/004-composition-root-and-network-boundary.md) and [ADR 005](adr/005-transaction-lifecycle-alignment.md).

### 6. CLI Subsystem (`src/cli/`, `src/cli.nim`, `src/blockchain_cli.nim`)
- Decomposed into cohesive single-responsibility submodules:
  - `src/cli/cli_parser.nim`: Command line argument and option parsing (`parseCliOptions`, `commandArguments`, `parseNonNegative`, `parseBlockHeight`, help text).
  - `src/cli/cli_service.nim`: Runtime service layer wrapping `BlockchainNode` and `NodeConfig` via `CliServiceContext` without console side effects.
  - `src/cli/cli_handlers.nim`: Command routing (`processCommand`) and presentation rendering for plaintext and JSON outputs.
  - `src/cli.nim`: Thin facade orchestrator providing `runCLI*()` and isolating backward-compatible test adapters. See [ADR 008](adr/008-cli-decomposition.md).

## 📐 Component Interactions
- **Transactions** use one canonical `Transaction` type shared by mempool and VM, including `publicKey` and `signature`.
- **Blocks** use one canonical `Block` type across domain, network propagation, and storage facades.
- **Transaction Lifecycle:** Aligns with the 5-stage flow: `submit -> mempool validation -> block inclusion -> VM execution -> storage/index update`. Transactions are validated by mempool admission first; candidate blocks are formed and propagated across the injected network; VM execution checks balance, nonce, and gas; and upon VM success, blocks are stored in BlockchainStore, transactions indexed in IndexStore, confirmed transactions evicted from the mempool, and account snapshots persisted. A continuous block production loop and live BFT consensus remain deferred (see [ADR 005](adr/005-transaction-lifecycle-alignment.md)).
- **Account ledger** (`StateDB` in state management) tracks balances and nonces. The VM keeps a value copy. After a successful account create or transfer, the CLI saves `vm.state` through `AccountStore`. **GlobalStateStore** holds unrelated KV state and is still unused by command behavior. `StateDB` is a value type. The CLI reads balances from `vm.state` after execution.
- **Keys** are written only to `<dataDir>/keystore/<address>.key` (plaintext). `:memory:` is rejected before a keystore directory is created. See ADR 002 for the format and the Windows permission limit. See ADR 003 for the account snapshot.
- **Configuration** is a typed `NodeConfig` value: CLI flags, then `NIM_NODE_DATA_DIR` and `NIM_NODE_VERBOSE`, then defaults. Centralized defaults cover gas limit, validators, mempool capacity, and network limits.
- **Consensus** in this tree is validator bookkeeping, not a Byzantine protocol implementation.

## 🔒 Security and Cryptographic Measures
- The signature check is real as a gate and fake as cryptography: mismatched demo signatures are rejected, and the scheme is forgeable with the public key.
- Private keys are not part of CLI JSON or log lines. The keystore file is plaintext.
- Zero-knowledge helpers do not hide data.
- Diagnostic logs use `std/logging` and must not include private keys, signatures, or keystore bodies.

## 🚧 Scalability and Performance
- The modules are separated so later replacements have a boundary.
- Nothing here is sized or measured as a production deployment.

## 🚀 Future Enhancements
- Replace `demo-sha256` with an audited Ed25519 or secp256k1 implementation.
- Replace the zero-knowledge placeholder.
- Implement pluggable durable disk storage backends (e.g. SQLite, LMDB, append-only logs) behind the `BlockchainStore` and `IndexStore` facades.
- Encrypt or otherwise protect the keystore.
- Continuous multi-transaction block production loop and mining timers.
- Live BFT consensus protocol and finality checkpoints.
- Run a long-lived server process. `main` and the CLI currently load, run, and exit.

---

This architecture is a teaching layout. It does not satisfy production requirements for consensus, cryptography, networking, or storage.
