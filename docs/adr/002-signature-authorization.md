# ADR 002: Demo Signature Authorization and Keystore

## Status

Accepted

## Context

Path 1 made `Transaction` the single domain type shared by the VM and the mempool, but that object carried no signature. Two procedures named `verifySignature` disagreed with each other:

- `key_management.signMessage` hashed `SHA-256(privateKey || message)`.
- `key_management.verifySignature` hashed `SHA-256(publicKey || message)` and swallowed every exception.
- `signature_verification.verifySignature` accepted the prefix `signed_` plus the message.

The VM checked amount, balance, nonce, and gas only. The mempool checked duplicates and capacity only. Unsigned transactions could move balances. Account creation printed the private key in text and JSON output. Diagnostics used `echo`, and initialization used a bare `except`.

A real Ed25519 scheme was not introduced in this change. Replacing the signer with a curve, and replacing the zero-knowledge placeholders, would be a larger crypto rewrite than this authorization gate.

## Decision

### One verification API

`src/cryptography/signature_verification.nim` is the only verification API. `key_management` signs and generates keys. It no longer exports `verifySignature`.

The teaching scheme is named `demo-sha256`. It is not Ed25519 and not secp256k1:

- `publicKey = hex(SHA-256(privateKeyBytes))`
- `signature = hex(SHA-256(publicKeyBytes || messageBytes))`
- The signed message is `transactionSigningPayload`: `id|sender|receiver|amount|fee|nonce`.
- `timestamp`, `size`, `publicKey`, and `signature` are not part of that payload.
- The sender must equal the first 8 hex characters of the public key.

Anyone who knows the public key can forge a signature. The gate rejects missing and non-matching signatures. It does not provide unforgeability.

`authorizeTransaction` is the shared check. The VM calls it from `validateTransaction` before balance and nonce checks. The mempool calls it from `addTransaction` before duplicate and capacity checks. The mempool does not check balance, nonce, amount, or gas. The CLI still applies the VM and then admits the same transaction to the mempool.

### Transaction fields

`Transaction` in `src/common/types.nim` gains `publicKey` and `signature`. Those aliases live in the common module so the crypto layer does not redefine them.

### Keystore

`account create` writes the private key to `<dataDir>/keystore/<address>.key` and does not put `private_key` in text or JSON output. The file format is plaintext UTF-8 (`version`, `scheme`, `address`, `public_key`, `private_key`, `warning`). It is not encrypted.

On POSIX the file mode is owner read/write (0600) and the directory is owner-only (0700), via `setFilePermissions`. On Windows that API only toggles the read-only attribute and does not apply an owner-only ACL, so other local users may be able to read the file.

Private keys, full signatures, and keystore bodies are not written to logs or error text.

### Errors and logging

Transfer, transaction validation, mempool admission, and initialization return `Status` or `Result` from `src/common/result.nim` instead of a bare bool. Diagnostic `echo` calls in the node, CLI initialization, and block propagation use `std/logging`. `--verbose` selects debug; otherwise the level is info. Help text and command results stay on stdout. Logs go to stderr. Logging is configured once from `main` and `runCLI`.

### Configuration

`NodeConfig` is resolved as CLI flags, then `NIM_NODE_DATA_DIR` and `NIM_NODE_VERBOSE`, then defaults (`data`, verbose off). `--verbose` is a presence flag: omitting it does not clear an environment value. No new process-wide mutable configuration object was added. The CLI keeps one session value, `cliConfig`, set at startup.

`main` still initializes and exits. It is not a daemon.

### What this change does not do

Zero-knowledge proofs stay string placeholders. Consensus, networking, and storage stay in-memory prototypes. The demo signature is not production cryptography.

## Consequences

- Callers that build a `Transaction` without `publicKey` and `signature` are rejected by the VM and the mempool. Constructors still compile because the new fields default to empty strings.
- `validateTransaction`, `applyTransaction`, and `addTransaction` return `Status`, not `bool`.
- The genesis balance has no keystore, so the CLI cannot transfer from `genesis`.
- A leaked public key is enough to forge a demo signature for that account.
- The address is 8 hex characters and is not collision-resistant.
- Rollback is a revert of this change set. Keystore files under `data/keystore` are local plaintext and can be deleted; there is no on-disk chain format to migrate.
