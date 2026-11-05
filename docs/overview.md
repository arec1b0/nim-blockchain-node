# Nim Blockchain Node Project Overview

## Introduction

This document is a high-level map of an **educational prototype**. The code is organized in layers so the transaction path is readable. It is not a production node: the signature scheme is `demo-sha256`, zero-knowledge proofs are placeholders, and state is in memory. `main` initializes and exits.

## 🛠️ Architectural Overview
The node follows a modular, layered architecture, clearly divided into core components, each responsible for specific functionalities:

### 1. Core Engine Layer
- **Consensus**: In-memory validator bookkeeping and a quorum helper. Not a BFT implementation.
- **Virtual Machine (VM)**: Applies value transfers with a fixed gas cost. `validateTransaction` rejects unsigned and invalid demo signatures before balance and nonce checks.
- **State Management**: Account balances and nonces in an in-memory `StateDB` value.

### 2. Cryptography Layer
- **Key Management**: Random seed and `signMessage` for `demo-sha256`. It does not verify signatures.
- **Signature Verification**: The only verification API. `publicKey = hex(SHA-256(privateKey))`, `signature = hex(SHA-256(publicKey || message))`. Not Ed25519. Forgeable if the public key is known. See [ADR 002](adr/002-signature-authorization.md).
- **Zero-Knowledge Proofs**: The string prefix `zk_proof_`. Not a proof system.

### 3. Network Layer
- **P2P Communication**: In-memory peer table. No transport and no authentication.
- **Mempool Management**: Fee ordering plus the same `authorizeTransaction` check the VM uses. Balance and nonce are not checked here.
- **Block Propagation**: Placeholder that records a successful status. Diagnostics go through `std/logging`.

### 4. Storage Layer
In-memory maps only. Nothing is written to disk by the storage modules:
- **BlockchainDB**: Stores blocks by their height, ensuring quick retrieval.
- **IndexDB**: Facilitates rapid transaction lookup, indexing transactions by their ID.
- **GlobalStateStore** (`state_db.nim`): In-memory key-value map (not the account ledger, and not a versioned database).

### Common Domain Types
- `src/common/types.nim`: Canonical `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, and `Transaction` (with `publicKey` and `signature`).
- Account ledger state remains `StateDB` in `state_management.nim`.
- See [ADR 001](adr/001-canonical-domain-types.md) and [ADR 002](adr/002-signature-authorization.md).

## 🔒 Cryptographic Considerations
- One verification procedure serves the VM and the mempool. The scheme is `demo-sha256`, a SHA-256 teaching placeholder, not Ed25519 or secp256k1, and it is not unforgeable.
- Private keys are stored in a plaintext keystore under the configured data directory and are omitted from CLI JSON and logs. On Windows the file cannot be given a POSIX owner-only mode.
- Zero-knowledge code remains a string placeholder.

## 🚧 Module Breakdown
### Common
- `common/types.nim`: Canonical domain types (`Transaction`, including signature fields).
- `common/config.nim`: `NodeConfig`. Precedence is CLI flags, then `NIM_NODE_DATA_DIR` / `NIM_NODE_VERBOSE`, then defaults.
- `common/result.nim`: `Status` and `Result` for validation, admission, transfer, and init.
- `common/logsetup.nim`: one-time `std/logging` setup called from `main` and `runCLI`.

### Core Engine
- `consensus.nim`: Implements the consensus logic to manage validator quorum and blockchain finality.
- `state_management.nim`: Account-ledger `StateDB` (balances and nonces).
- `vm.nim`: Manages transaction execution, accounting for computational resources via gas metering.

### Cryptographic Security
- `key_management.nim`: Demo key generation and signing only.
- `signature_verification.nim`: The only `verifySignature` / `authorizeTransaction` implementation.
- `keystore.nim`: Plaintext educational keystore. Not encrypted.
- `zk_proofs.nim`: String-prefix placeholder. Not a real proof system.

### Network Communication
- `p2p.nim`: Manages peer-to-peer network connectivity.
- `mempool.nim`: Pending transactions. Admission verifies the demo signature, then enforces id uniqueness and capacity.
- `block_propagation.nim`: Explicitly handles broadcasting blocks to the network.

### Persistent Storage
- `blockchain_db.nim`: Efficient storage and retrieval of blockchain data.
- `index_db.nim`: Indexes transactions for rapid retrieval.
- `state_db.nim`: `GlobalStateStore` for versioned key-value state.

## 🚀 Node Initialization Sequence (main.nim / cli.nim)
Today, `main.nim` and `cli.nim` each wire components independently (defaults still diverge). A shared composition root is planned; see ADR 001.
- Both entry points resolve `NodeConfig`, call `configureLogging`, build in-memory components, and exit. There is no server loop.
- `main` adds one signed sample transaction to the mempool. The sample private key is not written or logged.
- The CLI copies the funded ledger into the VM. Later balances are read from `vm.state`.
- Account ledger (`StateDB`) and global KV store (`GlobalStateStore`) are constructed separately.

## 🔒 Security and Cryptographic Considerations
- Sign and verify now share `demo-sha256`. That stops empty and non-matching signatures from moving balances. It does not stop someone who knows the public key from forging one.
- Logging is `std/logging` with `--verbose` mapped to debug. Logs must not contain private keys or signatures.
- Initialization and the transfer path return `Status` / `Result` instead of a bare bool.

## 🚧 Potential Areas for Improvement
- Replace `demo-sha256` with Ed25519 or secp256k1.
- Replace the zero-knowledge placeholder.
- Persist data and protect the keystore.
- Add a real network and a long-running process.

---

This overview matches the educational prototype. It is not a production architecture.
