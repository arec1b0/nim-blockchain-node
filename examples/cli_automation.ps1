# CLI Automation Example
# This script shows how to use the blockchain CLI for automation and scripting

param(
    [int]$NumAccounts = 3,
    [int]$InitialFunding = 1000,
    [int]$TransferAmount = 100
)

Write-Host "🤖 Blockchain CLI Automation Example" -ForegroundColor Green
Write-Host "Creating $NumAccounts accounts with $InitialFunding tokens each" -ForegroundColor Yellow
Write-Host ""

# Ensure CLI is built
if (-not (Test-Path "../blockchain_cli.exe")) {
    Write-Host "Building CLI..." -ForegroundColor Yellow
    Set-Location ..
    nimble cli
    Set-Location examples
}

$CLI = "../blockchain_cli.exe"

# Start the node
Write-Host "Starting blockchain node..." -ForegroundColor Cyan
& $CLI node start

# Function to create account and return address
function New-BlockchainAccount {
    $output = & $CLI --json account create | ConvertFrom-Json
    return @{
        Address = $output.address
        PublicKey = $output.public_key
        PrivateKey = $output.private_key
    }
}

# Function to get balance
function Get-AccountBalance {
    param([string]$Address)
    $output = & $CLI --json account balance $Address | ConvertFrom-Json
    return $output.balance
}

# Create accounts
Write-Host "Creating $NumAccounts accounts..." -ForegroundColor Cyan
$accounts = @()
for ($i = 1; $i -le $NumAccounts; $i++) {
    $account = New-BlockchainAccount
    $accounts += $account
    Write-Host "  Account $i`: $($account.Address)" -ForegroundColor Green
}

# Fund accounts from genesis
Write-Host "`nFunding accounts from genesis..." -ForegroundColor Cyan
foreach ($account in $accounts) {
    Write-Host "  Funding $($account.Address) with $InitialFunding tokens..."
    & $CLI account transfer genesis $($account.Address) $InitialFunding 10 | Out-Null
}

# Verify balances
Write-Host "`nAccount balances after funding:" -ForegroundColor Cyan
foreach ($i in 0..($accounts.Length - 1)) {
    $balance = Get-AccountBalance $accounts[$i].Address
    Write-Host "  Account $($i + 1): $balance tokens" -ForegroundColor Green
}

# Simulate some transactions
Write-Host "`nSimulating transactions..." -ForegroundColor Cyan
for ($i = 0; $i -lt ($accounts.Length - 1); $i++) {
    $from = $accounts[$i].Address
    $to = $accounts[$i + 1].Address
    Write-Host "  $from -> $to ($TransferAmount tokens)"
    & $CLI account transfer $from $to $TransferAmount 5 | Out-Null
}

# Final balances
Write-Host "`nFinal account balances:" -ForegroundColor Cyan
foreach ($i in 0..($accounts.Length - 1)) {
    $balance = Get-AccountBalance $accounts[$i].Address
    Write-Host "  Account $($i + 1): $balance tokens" -ForegroundColor Green
}

# Node statistics
Write-Host "`nNode Statistics:" -ForegroundColor Cyan
$nodeStatus = & $CLI --json node status | ConvertFrom-Json
Write-Host "  Blockchain Height: $($nodeStatus.height)"
Write-Host "  Pending Transactions: $($nodeStatus.pending_transactions)"
Write-Host "  Active Validators: $($nodeStatus.validators)"

# Transaction summary
Write-Host "`nPending Transactions:" -ForegroundColor Cyan
& $CLI transaction list

Write-Host "`n✅ Automation example completed!" -ForegroundColor Green
Write-Host "`n💾 Account details saved to accounts.json" -ForegroundColor Yellow

# Save account details to JSON file for later use
$accountsJson = $accounts | ConvertTo-Json -Depth 3
$accountsJson | Out-File -FilePath "accounts.json" -Encoding UTF8

Write-Host "`n📊 Summary:"
Write-Host "  - Created: $($accounts.Length) accounts"
Write-Host "  - Initial funding: $InitialFunding tokens each" 
Write-Host "  - Transactions: $($accounts.Length - 1) transfers of $TransferAmount tokens"
Write-Host "  - Account details saved to: accounts.json"