# CLI Examples

This directory contains example scripts that demonstrate how to use the blockchain CLI for automation and scripting purposes.

## 🤖 Automation Scripts

### `cli_automation.ps1` (Windows PowerShell)

Demonstrates automated account creation, funding, and transactions.

**Usage:**

```powershell
# Default: 3 accounts, 1000 initial funding, 100 transfer amount
.\cli_automation.ps1

# Custom parameters
.\cli_automation.ps1 -NumAccounts 5 -InitialFunding 2000 -TransferAmount 250
```

### `cli_automation.sh` (Linux/macOS)

Same functionality as the PowerShell version for Unix-like systems.

**Usage:**

```bash
# Make executable
chmod +x cli_automation.sh

# Default: 3 accounts, 1000 initial funding, 100 transfer amount  
./cli_automation.sh

# Custom parameters
./cli_automation.sh 5 2000 250
```

## 📋 What These Scripts Do

1. **Build CLI** - Ensures the blockchain CLI is compiled
2. **Start Node** - Initializes the blockchain node
3. **Create Accounts** - Generates the specified number of accounts with keypairs
4. **Fund Accounts** - Transfers initial funding from genesis to each account
5. **Simulate Transactions** - Creates a chain of transactions between accounts
6. **Report Status** - Shows final balances and node statistics
7. **Save Results** - Exports account details to `accounts.json`

## 🎯 Example Output

```
🤖 Blockchain CLI Automation Example
Creating 3 accounts with 1000 tokens each

Starting blockchain node...
✅ Blockchain node initialized successfully

Creating 3 accounts...
  Account 1: addr_001
  Account 2: addr_002  
  Account 3: addr_003

Funding accounts from genesis...
  Funding addr_001 with 1000 tokens...
  Funding addr_002 with 1000 tokens...
  Funding addr_003 with 1000 tokens...

Account balances after funding:
  Account 1: 1000 tokens
  Account 2: 1000 tokens
  Account 3: 1000 tokens

Simulating transactions...
  addr_001 -> addr_002 (100 tokens)
  addr_002 -> addr_003 (100 tokens)

Final account balances:
  Account 1: 885 tokens  # 1000 - 100 - 15 (fees)
  Account 2: 1085 tokens # 1000 + 100 - 100 - 15 (fees)
  Account 3: 1095 tokens # 1000 + 100 - 5 (fees)

✅ Automation example completed!
```

## 🔧 Prerequisites

- Blockchain CLI built (`nimble cli`)
- PowerShell 5.1+ (Windows) or Bash (Linux/macOS)
- `jq` command-line JSON processor (Linux/macOS only)

### Installing jq (Linux/macOS)

```bash
# Ubuntu/Debian
sudo apt install jq

# macOS with Homebrew
brew install jq

# CentOS/RHEL
sudo yum install jq
```

## 📊 Output Files

Both scripts generate an `accounts.json` file containing:

```json
{
  "accounts": [
    {
      "id": 1,
      "address": "addr_001",
      "balance": 885
    },
    ...
  ]
}
```

## 💡 Customization Ideas

You can modify these scripts to:

- **Load testing**: Create many accounts and transactions
- **Network simulation**: Test different transaction patterns
- **Monitoring**: Continuously check node status
- **Backup**: Export blockchain state
- **Analysis**: Generate transaction reports

## 🔗 Integration

These examples show how to integrate the blockchain CLI into:

- **CI/CD pipelines** - Automated testing
- **Monitoring systems** - Health checks
- **Administrative scripts** - Bulk operations
- **Development workflows** - Test data generation

## 🛠️ Troubleshooting

**PowerShell Execution Policy (Windows):**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Script not executable (Linux/macOS):**

```bash
chmod +x *.sh
```

**jq not found (Linux/macOS):**
Install jq as shown in the prerequisites section above.
