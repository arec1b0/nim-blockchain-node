# Nim Blockchain Node

## Introduction

This repository is an **educational prototype** of a modular blockchain node written in Nim. It is a place to read layer boundaries, a transaction path, and a deliberately incomplete crypto stack.

It is **not production-ready**. It does not provide real unforgeability, encrypted key storage, persistent consensus, or a private network. Do not deploy it to hold value.

## What is actually implemented

- **Core engine:** in-memory consensus bookkeeping, a gas-metered transfer VM, and an account ledger.
- **Cryptography:** a SHA-256 teaching signature named `demo-sha256` (not Ed25519 or secp256k1) and a string-prefix zero-knowledge placeholder.
- **Network:** an in-memory mempool and placeholder peer and block propagation types.
- **Storage:** in-memory maps, not a durable database.
- **CLI:** account creation writes a plaintext keystore; transfers must carry a demo signature.

The signature formula, keystore format, configuration precedence, and CI workflow are documented below and in [ADR 002](docs/adr/002-signature-authorization.md).

## Quick start

### Prerequisites

- **Nim 2.2.2+** (CI uses 2.2.4): [nim-lang.org](https://nim-lang.org/install.html)
- **Git**

### Installation

```shell
git clone https://github.com/dkrizhanovskyi/nim-blockchain-node.git
cd nim-blockchain-node
nimble install -y
```

### Build

```shell
nimble build          # node executable
nimble cli            # CLI executable
nimble buildAll       # both
```

`main` initializes an in-memory node, logs to stderr, and **exits**. It is not a long-running server.

```shell
nimble buildAll
./main --help
./blockchain_cli --help
```

On Windows the executables are `main.exe` and `blockchain_cli.exe` (often under `src/` depending on the Nim version).

## Signature scheme

Authorization uses one API, `signature_verification.verifySignature`. The VM and the mempool both call `authorizeTransaction`.

`demo-sha256` is a teaching placeholder:

- `publicKey = hex(SHA-256(privateKeyBytes))`
- `signature = hex(SHA-256(publicKeyBytes || messageBytes))`
- The message is `id|sender|receiver|amount|fee|nonce`
- The sender must equal the first 8 hex characters of the public key

Anyone who knows the public key can forge a signature. Unsigned transactions and signatures that do not match this formula are rejected and do not move balances. This is not Ed25519.

## Keystore

`account create` writes the private key to `<data-dir>/keystore/<address>.key` and does not print it or put `private_key` in JSON output.

The file is plaintext UTF-8 (`version`, `scheme=demo-sha256`, `address`, `public_key`, `private_key`, `warning`). It is not encrypted. On POSIX the file is owner read/write (mode 0600). On Windows, Nim cannot set an owner-only ACL through `setFilePermissions`; other local users may be able to read the file.

The in-memory `genesis` account has a balance and no keystore, so it cannot authorize a transfer.

## Configuration

Precedence is **CLI flags > environment variables > defaults**.

| Setting | CLI | Environment | Default |
| --- | --- | --- | --- |
| Data directory | `--data-dir` / `-d` | `NIM_NODE_DATA_DIR` | `data` |
| Verbose logging | `--verbose` / `-v` | `NIM_NODE_VERBOSE` | off |

`--verbose` is a presence flag. If you omit it, `NIM_NODE_VERBOSE` (`1`, `true`, `yes`, `on`, or the false counterparts `0`, `false`, `no`, `off`) still applies. Options belong before the command. Verbose logging is debug on stderr; other diagnostics are info, warn, or error. Command results and help stay on stdout.

## Testing and CI

```shell
nimble test
```

GitHub Actions (`.github/workflows/ci.yml`) runs `nimble buildAll` and `nimble test` on push and pull requests, with Nim 2.2.4. Compiler warnings are not treated as errors, because this tree still has warnings outside the authorization work.

`nimcrypto` is a direct dependency pinned at `0.6.2` in `nim_blockchain_node.nimble`. Its own transitive dependencies are not redeclared here.

## Documentation

- [Architecture](docs/architecture.md)
- [Overview](docs/overview.md)
- [ADR 001: canonical types](docs/adr/001-canonical-domain-types.md)
- [ADR 002: signature authorization](docs/adr/002-signature-authorization.md)
- [CLI notes](CLI_README.md)
- [Setup](docs/setup_guide.md)

## Security

Read [security-report.md](security-report.md). The demo signature and plaintext keystore are known limits, not temporary wording. Zero-knowledge proofs are still the `zk_proof_` string prefix.

## Contributing

See [Contributing Guide](docs/contributing.md).
