# Nim Blockchain Node Architecture

## 🔍 Introduction

This document describes the module layout of an **educational prototype**. The node is not production-ready: signatures are a SHA-256 teaching scheme, zero-knowledge proofs are string placeholders, and networking is simulated. Account balances and nonces can be reloaded from a JSON snapshot. Blocks, the transaction index, the mempool, and peers are still in memory.

It is not a claim of production consensus, cryptography, networking, or durable storage.

## 🧱 Architectural Layers
The architecture is composed of distinct modules so each layer has a readable boundary. Several modules are placeholders; those limits are stated in the sections below.

### 0. Common Domain Types (`src/common/types.nim`)

Canonical shared types for cross-layer use:

- `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`

This module is a leaf dependency and must not import higher-level layers. The VM and mempool both use the same `Transaction` type, including `publicKey` and `signature`. See [ADR 001](adr/001-canonical-domain-types.md), [ADR 002](adr/002-signature-authorization.md), and [ADR 003](adr/003-account-store.md).

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
- The signed payload is `id|sender|receiver|amount|fee|nonce`. The sender must match the first 8 hex characters of the public key.

#### **Zero-Knowledge Proof Module**
- String prefix placeholder (`zk_proof_` + data). Not a zk-SNARK or zk-STARK.
- Left unchanged by the signature work. Do not treat it as a privacy system.

### 3. Network Layer

#### **P2P Communication Module**
- In-memory peer list. No sockets, no NAT traversal, and no peer authentication.

#### **Mempool Module**
- Stores pending transactions and orders them by fee.
- `addTransaction` calls the same `authorizeTransaction` API as the VM and rejects unsigned or invalid demo signatures.
- It does not check balance, nonce, amount, or gas. Those checks stay in the VM.

#### **Block Propagation Module**
- Placeholder that returns success without sending bytes to peers.
- `propagateBlock` does not take a `Network`. `peersReached` is fixed at 5.
- Logs the block id through `std/logging`. No latency or bandwidth optimization.

### 4. Storage Layer

#### **Blockchain Database Module**
- In-memory map of blocks by height. Not durable across process restarts.

#### **Index Database Module**
- In-memory index from transaction id to a height and position.

#### **Global State Store Module** (`GlobalStateStore`)
- In-memory key-value map, separate from the account-ledger `StateDB`.
- Not a historical state database.

#### **Account Store**
- Facade in `storage/account_store.nim`. `openAccountStore` selects the backend from `dataDir`.
- `MemoryAccountStore` keeps one `StateDB` in the process. `--data-dir=:memory:` selects it and does not create a directory.
- `FileAccountStore` writes `<dataDir>/accounts.json` (format `nim-node-accounts`, version 1) by flushing a temp file and replacing the destination in the same directory.
- A checksum detects accidental edits. A failed load leaves the existing file in place. This is not a database and not crash-proof beyond that replace.
- The default data directory remains `data`. An omitted `--data-dir` is not memory-only, because the keystore already uses `data`.

## 📐 Component Interactions
- **Transactions** use one canonical `Transaction` type shared by mempool and VM, including `publicKey` and `signature`.
- **Authorization:** mempool admission and `validateTransaction` both call `authorizeTransaction`. The CLI still applies the VM first and then admits the same transaction to the mempool. A long-running block producer is not implemented; `main` initializes and exits.
- **Account ledger** (`StateDB` in state management) tracks balances and nonces. The VM keeps a value copy. After a successful account create or transfer, the CLI saves `vm.state` through `AccountStore`. **GlobalStateStore** holds unrelated KV state and is still unused by command behavior. `StateDB` is a value type. The CLI reads balances from `vm.state` after execution.
- **Keys** are written only to `<dataDir>/keystore/<address>.key` (plaintext). `:memory:` is rejected before a keystore directory is created. See ADR 002 for the format and the Windows permission limit. See ADR 003 for the account snapshot.
- **Configuration** is a `NodeConfig` value: CLI flags, then `NIM_NODE_DATA_DIR` and `NIM_NODE_VERBOSE`, then defaults. Logging is configured from `main` and `runCLI`.
- **Consensus** in this tree is validator bookkeeping, not a Byzantine protocol implementation.
- A single composition root (`src/node.nim`) is still only planned. `main.nim` and `cli.nim` wire components separately (see ADR 001).

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
- Persist blocks and the transaction index. Account balances already have a versioned JSON snapshot, which is not a database engine.
- Encrypt or otherwise protect the keystore.
- Pass a network dependency into `propagateBlock`, enforce `maxPeers`, and replace the fixed `peersReached` placeholder.
- Split `cli.nim` into a runtime module, command rendering, and a thin `runCLI`. See ADR 003.
- Run a long-lived process. `main` and the CLI currently load, run, and exit.

---

This architecture is a teaching layout. It does not satisfy production requirements for consensus, cryptography, networking, or storage.
