# Nim Blockchain Node Architecture

## 🔍 Introduction

This document describes the module layout of an **educational prototype**. The node is not production-ready: signatures are a SHA-256 teaching scheme, zero-knowledge proofs are string placeholders, and storage and networking are in memory.

It is not a claim of production consensus, cryptography, or persistence.

## 🧱 Architectural Layers
The architecture is composed of distinct modules so each layer has a readable boundary. Several modules are placeholders; those limits are stated in the sections below.

### 0. Common Domain Types (`src/common/types.nim`)

Canonical shared types for cross-layer use:

- `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, `Transaction`

This module is a leaf dependency and must not import higher-level layers. The VM and mempool both use the same `Transaction` type, including `publicKey` and `signature`. See [ADR 001](adr/001-canonical-domain-types.md) and [ADR 002](adr/002-signature-authorization.md).

### 1. Core Engine Layer

#### **Consensus Module**
- In-memory validator set, stake numbers, and a quorum helper.
- Not a Byzantine fault tolerant protocol and not a live finality gadget.

#### **Virtual Machine (VM) Module**
- Applies value transfers with a fixed gas cost.
- `validateTransaction` rejects unsigned and invalid `demo-sha256` signatures before it checks amount, balance, or nonce.
- Does not execute general smart contracts.

#### **State Management Module**
- In-memory account balances and nonces.
- No concurrency control and no state pruning. `StateDB` is a value type.

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
- Logs the block id through `std/logging`. No latency or bandwidth optimization.

### 4. Storage Layer

#### **Blockchain Database Module**
- In-memory map of blocks by height. Not durable across process restarts.

#### **Index Database Module**
- In-memory index from transaction id to a height and position.

#### **Global State Store Module** (`GlobalStateStore`)
- In-memory key-value map, separate from the account-ledger `StateDB`.
- Not a historical state database.

## 📐 Component Interactions
- **Transactions** use one canonical `Transaction` type shared by mempool and VM, including `publicKey` and `signature`.
- **Authorization:** mempool admission and `validateTransaction` both call `authorizeTransaction`. The CLI still applies the VM first and then admits the same transaction to the mempool. A long-running block producer is not implemented; `main` initializes and exits.
- **Account ledger** (`StateDB` in state management) tracks balances and nonces; **GlobalStateStore** holds unrelated KV state. `StateDB` is a value type. The CLI reads balances from `vm.state` after execution.
- **Keys** are written only to `<dataDir>/keystore/<address>.key` (plaintext). See ADR 002 for the format and the Windows permission limit.
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
- Persist blocks and state, and encrypt or otherwise protect the keystore.
- Run a long-lived process. `main` currently exits after initialization on purpose.

---

This architecture is a teaching layout. It does not satisfy production requirements for consensus, cryptography, networking, or storage.
