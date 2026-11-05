# Blockchain CLI User Guide

A simple command-line interface for interacting with the Nim blockchain node.

## 🚀 Quick Start

### Build the CLI

```bash
nimble cli
# or build everything
nimble buildAll
```

### Basic Usage

```bash
# Show help
./blockchain_cli --help

# Start the node and show status
./blockchain_cli node start
./blockchain_cli node status

# Create a new account
./blockchain_cli account create

# Check account balance
./blockchain_cli account balance genesis

# Transfer funds
./blockchain_cli account transfer genesis [new_address] 100 10
```

## 📋 Available Commands

### Node Operations

```bash
# Check node status
./blockchain_cli node status

# Start the blockchain node
./blockchain_cli node start

# Show detailed node information  
./blockchain_cli node info
```

### Account Management

```bash
# Create a new account (generates keypair)
./blockchain_cli account create

# Check account balance
./blockchain_cli account balance <ADDRESS>

# List all accounts
./blockchain_cli account list

# Transfer funds between accounts
./blockchain_cli account transfer <FROM> <TO> <AMOUNT> [FEE]
```

### Transaction Operations

```bash
# Create a new transaction
./blockchain_cli transaction create <FROM> <TO> <AMOUNT> [FEE]

# List pending transactions
./blockchain_cli transaction list

# Show transaction status
./blockchain_cli transaction status <TX_ID>
```

### Block Operations

```bash
# Show latest block
./blockchain_cli block latest

# Get block by height
./blockchain_cli block get <HEIGHT>

# Show current blockchain height
./blockchain_cli block height

# List blocks in range
./blockchain_cli block list [START] [END]
```

## 🎛️ Options

- `-h, --help`: Show help message
- `-v, --verbose`: Enable verbose output
- `-j, --json`: Output in JSON format (great for scripting)
- `-d, --data-dir`: Specify data directory (default: data)

## 💡 Examples

### Creating and Funding Accounts

```bash
# Create two accounts
./blockchain_cli account create
# (save the addresses shown)

# Check genesis balance
./blockchain_cli account balance genesis

# Transfer from genesis to new account
./blockchain_cli account transfer genesis addr_12345678 1000 10

# Check new account balance
./blockchain_cli account balance addr_12345678
```

### JSON Output for Scripting

```bash
# Get node status in JSON
./blockchain_cli --json node status

# Create account and parse with jq
./blockchain_cli --json account create | jq '.address'

# Check balance in JSON format
./blockchain_cli --json account balance genesis
```

### Blockchain Exploration

```bash
# Check current height
./blockchain_cli block height

# View latest block
./blockchain_cli block latest

# View specific block
./blockchain_cli block get 0

# List pending transactions
./blockchain_cli transaction list
```

## 🔐 Security Notes

- **Private keys**: `account create` writes the private key to `<data-dir>/keystore/<address>.key` and does not print it. JSON output has no `private_key` field. The file is plaintext and is not encrypted. On Windows it cannot be given a POSIX 0600 ACL via Nim.
- **Signatures**: Transfers need a keystore for the sender and a `demo-sha256` signature. That scheme is not Ed25519 and is forgeable if the public key is known. The `genesis` account has a balance and no key, so it cannot send.
- **Genesis account**: The genesis account starts with 1,000,000 tokens in memory for tests. It is not a signing account.
- **Transaction fees**: Default fee is 10 tokens, but you can specify custom fees.
- **Logging**: `--verbose` turns on debug logs on stderr. `NIM_NODE_VERBOSE` and `NIM_NODE_DATA_DIR` apply when the matching CLI flag is absent. CLI flags win when they are set.

## 🛠️ Development

### Running Tests

```bash
nimble test
```

### Building for Release

```bash
nimble buildAll
```

### Verbose Mode

```bash
./blockchain_cli --verbose node status
```

## 📖 Architecture

The CLI is built on top of the refactored blockchain node components:

- **Core Engine**: Consensus, state management, virtual machine
- **Storage**: Blockchain database, state database, index database  
- **Network**: Mempool, block propagation, P2P networking
- **Cryptography**: Key management, signatures, zero-knowledge proofs

Each CLI command maps to one or more of these underlying components, providing a user-friendly interface to the blockchain functionality.

## 🎯 Common Workflows

### Setting up a Test Environment

```bash
# 1. Start the node
./blockchain_cli node start

# 2. Create test accounts (the private key is written under data/keystore and is not printed)
./blockchain_cli account create  # Alice
./blockchain_cli account create  # Bob

# 3. Genesis has a balance and no keystore, so this transfer is rejected.
./blockchain_cli account transfer genesis <alice_address> 5000

# 4. A signed transfer still needs a balance. New accounts start at 0,
#    and this prototype has no faucet, so this is rejected for insufficient balance
#    until something credits `vm.state` for that address.
./blockchain_cli account transfer <alice_address> <bob_address> 100

# 5. Check final balances
./blockchain_cli account balance <alice_address>
./blockchain_cli account balance <bob_address>
```

### Monitoring the Blockchain

```bash
# Check node status
./blockchain_cli node status

# Monitor pending transactions
./blockchain_cli transaction list

# Check blockchain height
./blockchain_cli block height

# View latest block
./blockchain_cli block latest
```

The CLI provides an intuitive way to interact with your blockchain node without needing to understand the underlying code architecture!
