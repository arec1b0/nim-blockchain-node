# Nim Blockchain Node Setup Guide

## Introduction
This document outlines detailed, step-by-step instructions to set up your Nim Blockchain Node development environment on Windows 11. Follow these explicit steps to configure your system properly and efficiently.

## 🔧 Prerequisites

Before proceeding, ensure your system meets the following prerequisites:

- **Windows 11** (64-bit)
- [Nim Programming Language](https://nim-lang.org/install.html) (version 2.2.2 or higher)
- Git

## 📌 Installation Steps

### 1. Install Nim
- Download and install the latest Nim version from [Nim Official Site](https://nim-lang.org/install_windows.html).
- Confirm the installation in your terminal:
```powershell
nim --version
```

### 2. Install Nimble (Nim's Package Manager)
- Nimble comes bundled with Nim; ensure it's properly installed by running:
```powershell
nimble --version
```

### 2. Clone the Repository
```powershell
git clone https://github.com/dkrizhanovskyi/nim-blockchain-node.git
cd nim-blockchain-node
```

### 3. Install Project Dependencies
Run Nimble to install necessary dependencies:
```powershell
nimble install
```

## ⚙️ Project Structure

```
nim-blockchain-node/
├── config/
├── docs
├── scripts
├── src
│   ├── core_engine
│   ├── cryptography
│   ├── network
│   └── storage
└── tests
```

## 🚀 Building the Node
To build the blockchain node:
```powershell
nimble build
```

## 🧪 Running Tests
Execute all unit and integration tests:
```powershell
nimble test
```

## 🖥️ Running the Node
Run the node after building:
```powershell
.\main.exe
```

You should see initialization logs on stderr, then the process exits. A successful run looks like:

```text
INFO: starting nim blockchain node (educational prototype)
INFO: blockchain node is operational
```

The emoji status lines from earlier drafts are gone. `main` is not a long-running server.

## 🛡️ Security and Maintenance
- Regularly update Nim and dependencies.
- Monitor and integrate cryptographic library updates.
- Follow best practices for security audits and code reviews.

---

Your Nim Blockchain Node checkout is ready for local experiments. It is an educational prototype, not a deployment. See [overview.md](overview.md) and [architecture.md](architecture.md).
