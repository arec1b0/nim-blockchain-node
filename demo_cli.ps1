# Blockchain CLI Demo Script for PowerShell
# This script demonstrates the basic functionality of the blockchain CLI

Write-Host "🚀 Blockchain CLI Demo" -ForegroundColor Green
Write-Host "=====================" -ForegroundColor Green

# Build the CLI if it doesn't exist
if (-not (Test-Path "./blockchain_cli.exe")) {
    Write-Host "📦 Building CLI..." -ForegroundColor Yellow
    nimble cli
}

Write-Host ""
Write-Host "1️⃣ Starting the blockchain node..." -ForegroundColor Cyan
./blockchain_cli.exe node start

Write-Host ""
Write-Host "2️⃣ Checking node status..." -ForegroundColor Cyan
./blockchain_cli.exe node status

Write-Host ""
Write-Host "3️⃣ Creating a new account (Alice)..." -ForegroundColor Cyan
$aliceOutput = ./blockchain_cli.exe --json account create | ConvertFrom-Json
$aliceAddr = $aliceOutput.address
Write-Host "Alice's address: $aliceAddr" -ForegroundColor Green

Write-Host ""
Write-Host "4️⃣ Creating another account (Bob)..." -ForegroundColor Cyan
$bobOutput = ./blockchain_cli.exe --json account create | ConvertFrom-Json
$bobAddr = $bobOutput.address
Write-Host "Bob's address: $bobAddr" -ForegroundColor Green

Write-Host ""
Write-Host "5️⃣ Checking genesis account balance..." -ForegroundColor Cyan
./blockchain_cli.exe account balance genesis

Write-Host ""
Write-Host "6️⃣ Transferring 1000 tokens from genesis to Alice..." -ForegroundColor Cyan
./blockchain_cli.exe account transfer genesis $aliceAddr 1000 10

Write-Host ""
Write-Host "7️⃣ Checking Alice's balance..." -ForegroundColor Cyan
./blockchain_cli.exe account balance $aliceAddr

Write-Host ""
Write-Host "8️⃣ Alice sends 200 tokens to Bob..." -ForegroundColor Cyan
./blockchain_cli.exe account transfer $aliceAddr $bobAddr 200 5

Write-Host ""
Write-Host "9️⃣ Checking final balances..." -ForegroundColor Cyan
Write-Host "Alice:" -ForegroundColor Yellow
./blockchain_cli.exe account balance $aliceAddr
Write-Host "Bob:" -ForegroundColor Yellow
./blockchain_cli.exe account balance $bobAddr

Write-Host ""
Write-Host "🔟 Checking pending transactions..." -ForegroundColor Cyan
./blockchain_cli.exe transaction list

Write-Host ""
Write-Host "1️⃣1️⃣ Checking blockchain height..." -ForegroundColor Cyan
./blockchain_cli.exe block height

Write-Host ""
Write-Host "1️⃣2️⃣ Final node status..." -ForegroundColor Cyan
./blockchain_cli.exe --json node status

Write-Host ""
Write-Host "✅ Demo completed!" -ForegroundColor Green
Write-Host ""
Write-Host "💡 Try these commands yourself:" -ForegroundColor Yellow
Write-Host "   ./blockchain_cli.exe --help"
Write-Host "   ./blockchain_cli.exe account create"
Write-Host "   ./blockchain_cli.exe block latest" 
Write-Host "   ./blockchain_cli.exe --json node status"