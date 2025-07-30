# Installation Guide

This guide will help you set up the Nim blockchain node and CLI on your system.

## 📋 Prerequisites

### 1. Install Nim Programming Language

#### Windows

1. Download the Windows installer from [nim-lang.org](https://nim-lang.org/install_windows.html)
2. Run the installer and follow the setup wizard
3. The installer will automatically add Nim to your PATH

**Alternative: Using Chocolatey**

```powershell
choco install nim
```

#### macOS

```bash
# Using Homebrew
brew install nim

# Or download from the website
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

#### Linux (Ubuntu/Debian)

```bash
# Install via choosenim (recommended)
curl https://nim-lang.org/choosenim/init.sh -sSf | sh

# Or use package manager (may be older version)
sudo apt update
sudo apt install nim
```

### 2. Verify Installation

Open a new terminal/command prompt and run:

```bash
nim --version
nimble --version
```

You should see output like:

```
Nim Compiler Version 2.2.2 [Windows: amd64]
nimble v0.14.2
```

## 🚀 Installing the Blockchain Node

### 1. Clone the Repository

```bash
git clone https://github.com/dkrizhanovskyi/nim-blockchain-node.git
cd nim-blockchain-node
```

### 2. Install Dependencies

```bash
nimble install
```

### 3. Build the Project

```bash
# Build just the CLI
nimble cli

# Or build everything (node daemon + CLI)
nimble buildAll
```

### 4. Verify Installation

```bash
# Windows
.\blockchain_cli.exe --help

# Linux/macOS  
./blockchain_cli --help
```

You should see the CLI help message.

## 🔧 Troubleshooting

### Nim Not Found

If you get "nim: command not found" or similar:

**Windows:**

1. Restart your command prompt/PowerShell
2. Check if Nim is in PATH: `echo $env:PATH`
3. Manually add Nim to PATH if needed

**Linux/macOS:**

1. Restart your terminal
2. Check if Nim is in PATH: `echo $PATH`
3. Add to your shell profile:

   ```bash
   echo 'export PATH=$HOME/.nimble/bin:$PATH' >> ~/.bashrc
   source ~/.bashrc
   ```

### Build Errors

If you encounter build errors:

1. **Update Nim**: Make sure you have Nim 2.2.2 or later
2. **Clean build**: Delete any existing executables and rebuild
3. **Dependencies**: Run `nimble install` again
4. **Check logs**: Look for specific error messages

### Permission Issues (Linux/macOS)

If you get permission denied errors:

```bash
chmod +x blockchain_cli
chmod +x demo_cli.sh
```

## 🎯 Quick Test

Once installed, run this quick test:

```bash
# Windows
.\blockchain_cli.exe node start
.\blockchain_cli.exe account create
.\blockchain_cli.exe node status

# Linux/macOS
./blockchain_cli node start
./blockchain_cli account create  
./blockchain_cli node status
```

## 📖 Next Steps

- Read the [CLI_README.md](CLI_README.md) for detailed usage instructions
- Run the demo script: `demo_cli.ps1` (Windows) or `demo_cli.sh` (Linux/macOS)
- Explore the [architecture documentation](docs/architecture.md)

## 🆘 Getting Help

If you run into issues:

1. Check this troubleshooting section
2. Review the error messages carefully
3. Ensure you have the latest version of Nim
4. Try rebuilding with `nimble buildAll`

For Windows users specifically:

- Use PowerShell or Command Prompt (not WSL for this project)
- Make sure Windows Defender isn't blocking the executables
- Run PowerShell as Administrator if you encounter permission issues
