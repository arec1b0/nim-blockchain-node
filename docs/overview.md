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
- **P2P Communication**: In-memory peer table. No transport and no authentication.
- **Mempool Management**: Fee ordering plus the same `authorizeTransaction` check the VM uses. Balance and nonce are not checked here.
- **Block Propagation**: Placeholder that records a successful status and a fixed `peersReached` of 5. It does not take a `Network` and does not send bytes. Diagnostics go through `std/logging`.

### 4. Storage Layer
Blocks, the transaction index, and the global key-value map are in-memory. Account balances and nonces are the exception:
- **AccountStore**: Loads and saves the account ledger. `:memory:` keeps it in the process. Any other data directory uses `<dataDir>/accounts.json` (version 1). A failed load does not overwrite the file. See [ADR 003](adr/003-account-store.md).
- **BlockchainDB**: In-memory blocks by height. Not reloaded after a restart.
- **IndexDB**: In-memory transaction id to height and position. Not reloaded after a restart.
- **GlobalStateStore** (`state_db.nim`): In-memory key-value map (not the account ledger, and not a versioned database). `main` does not construct it.

### Common Domain Types
- `src/common/types.nim`: Canonical `Address`, `Balance`, `Nonce`, `TransactionId`, `PublicKey`, `PrivateKey`, `Signature`, and `Transaction` (with `publicKey` and `signature`).
- Account ledger state remains `StateDB` in `state_management.nim`. Persistence is the `AccountStore` snapshot, not a second account type.
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
- `consensus.nim`: In-memory validator set and a quorum count. Not block production and not finality.
- `state_management.nim`: Account-ledger `StateDB` (balances and nonces). The VM holds a value copy.
- `vm.nim`: Manages transaction execution, accounting for computational resources via gas metering.

### Cryptographic Security
- `key_management.nim`: Demo key generation and signing only.
- `signature_verification.nim`: The only `verifySignature` / `authorizeTransaction` implementation.
- `keystore.nim`: Plaintext educational keystore. Not encrypted.
- `zk_proofs.nim`: String-prefix placeholder. Not a real proof system.

### Network Communication
- `p2p.nim`: In-memory peer table. No sockets. `maxPeers` is stored and not enforced on `addPeer`.
- `mempool.nim`: Pending transactions. Admission verifies the demo signature, then enforces id uniqueness and capacity.
- `block_propagation.nim`: Placeholder broadcast. It does not use `Network` and reports `peersReached: 5`.

### Persistent Storage
- `account_store.nim`: Facade. `openAccountStore` binds memory or the JSON snapshot.
- `memory_account_store.nim`: In-process `StateDB`. Not durable.
- `file_account_store.nim`: Versioned `accounts.json` snapshot. Not a database engine.
- `blockchain_db.nim`: In-memory block map. Lost on exit.
- `index_db.nim`: In-memory transaction index. Lost on exit.
- `state_db.nim`: In-memory `GlobalStateStore`. Not the account ledger.

## 🚀 Node Initialization Sequence (main.nim / cli.nim)
Today, `main.nim` and `cli.nim` each wire components independently (defaults still diverge). A shared composition root is planned; see ADR 001.
- Both entry points resolve `NodeConfig`, call `configureLogging`, open the account store, and exit. There is no server loop.
- A missing `accounts.json` seeds genesis with balance 1000000 and saves that snapshot. An existing snapshot is loaded and genesis is not reset. `:memory:` seeds genesis in the process only.
- `main` adds one signed sample transaction to the mempool. The sample private key is not written or logged. That transaction does not change the account snapshot.
- The CLI copies the loaded ledger into the VM. Later balances are read from `vm.state`. Successful account creation and transfers save `vm.state` before reporting success.
- `GlobalStateStore` remains a separate in-memory KV map. The CLI still constructs it. `main` does not.

## 🔒 Security and Cryptographic Considerations
- Sign and verify now share `demo-sha256`. That stops empty and non-matching signatures from moving balances. It does not stop someone who knows the public key from forging one.
- Logging is `std/logging` with `--verbose` mapped to debug. Logs must not contain private keys or signatures.
- Initialization and the transfer path return `Status` / `Result` instead of a bare bool.

## 🚧 Potential Areas for Improvement
- Replace `demo-sha256` with Ed25519 or secp256k1.
- Replace the zero-knowledge placeholder.
- Persist blocks and the transaction index. The account snapshot is version 1 JSON, not a database.
- Protect the keystore.
- Add a real network and a long-running process. `propagateBlock` is still a placeholder.

---

This overview matches the educational prototype. It is not a production architecture.
