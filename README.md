# Nim Blockchain Node

## 🚀 Introduction

The Nim Blockchain Node is a modular, high-performance blockchain node implementation written in the Nim programming language, designed for security, scalability, and maintainability. It provides a clear separation of concerns through distinct layers and leverages advanced cryptographic techniques.

## 🧱 Key Components

- **Core Engine Layer:** Handles consensus mechanisms, virtual machine execution, and state management.
- **Cryptography Layer:** Provides key management, signature verification, and zero-knowledge proofs.
- **Network Layer:** Manages peer-to-peer communication, mempool handling, and block propagation.
- **Storage Layer:** Offers efficient and reliable blockchain, index, and state data storage.

## 🚀 Quick Start

### Prerequisites

- **Nim 2.2.2+**: Download from [nim-lang.org](https://nim-lang.org/install.html)
- **Git**: For cloning the repository

### Installation

```shell
git clone https://github.com/dkrizhanovskyi/nim-blockchain-node.git 
cd nim-blockchain-node
nimble install
```

### Build Options

```shell
# Build the node daemon
nimble build

# Build the CLI tool
nimble cli

# Build everything
nimble buildAll
```

### Running the Node

```shell
# Run the blockchain node daemon
.\main.exe

# Or use the interactive CLI
.\blockchain_cli.exe --help
```

## 🖥️ Command Line Interface

The project includes a comprehensive CLI for easy blockchain interaction:

```shell
# Start and check node status
.\blockchain_cli.exe node start
.\blockchain_cli.exe node status

# Create accounts and transfer funds
.\blockchain_cli.exe account create
.\blockchain_cli.exe account transfer genesis [address] 1000

# View blockchain data
.\blockchain_cli.exe block latest
.\blockchain_cli.exe transaction list
```

See [CLI_README.md](CLI_README.md) for complete CLI documentation.

## 🎯 Demo

Run the interactive demo to see the CLI in action:

```powershell
# Windows PowerShell
.\demo_cli.ps1

# Linux/macOS
./demo_cli.sh
```

## 🧪 Testing

Run tests to ensure reliability:

```shell
nimble test
```

## 📚 Documentation

Explore more detailed documentation in the `docs` folder:

- [Architecture](docs/architecture.md)
- [Setup Guide](docs/setup_guide.md)
- [Getting Started](docs/getting_started.md)
- [Contributing](docs/contributing.md)

## 🔐 Security

Follow security best practices outlined in the documentation and regularly update cryptographic dependencies.

## 🙌 Contributing

We welcome contributions! See [Contributing Guide](docs/contributing.md) for more details.
