#!/bin/bash

# Blockchain CLI Demo Script
# This script demonstrates the basic functionality of the blockchain CLI

echo "🚀 Blockchain CLI Demo"
echo "====================="

# Build the CLI if it doesn't exist
if [ ! -f "./blockchain_cli" ]; then
    echo "📦 Building CLI..."
    nimble cli
fi

echo ""
echo "1️⃣ Starting the blockchain node..."
./blockchain_cli node start

echo ""
echo "2️⃣ Checking node status..."
./blockchain_cli node status

echo ""
echo "3️⃣ Creating a new account (Alice)..."
ALICE_OUTPUT=$(./blockchain_cli --json account create)
ALICE_ADDR=$(echo $ALICE_OUTPUT | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
echo "Alice's address: $ALICE_ADDR"

echo ""
echo "4️⃣ Creating another account (Bob)..."
BOB_OUTPUT=$(./blockchain_cli --json account create)
BOB_ADDR=$(echo $BOB_OUTPUT | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
echo "Bob's address: $BOB_ADDR"

echo ""
echo "5️⃣ Checking genesis account balance..."
./blockchain_cli account balance genesis

echo ""
echo "6️⃣ Transferring 1000 tokens from genesis to Alice..."
./blockchain_cli account transfer genesis $ALICE_ADDR 1000 10

echo ""
echo "7️⃣ Checking Alice's balance..."
./blockchain_cli account balance $ALICE_ADDR

echo ""
echo "8️⃣ Alice sends 200 tokens to Bob..."
./blockchain_cli account transfer $ALICE_ADDR $BOB_ADDR 200 5

echo ""
echo "9️⃣ Checking final balances..."
echo "Alice:"
./blockchain_cli account balance $ALICE_ADDR
echo "Bob:"
./blockchain_cli account balance $BOB_ADDR

echo ""
echo "🔟 Checking pending transactions..."
./blockchain_cli transaction list

echo ""
echo "1️⃣1️⃣ Checking blockchain height..."
./blockchain_cli block height

echo ""
echo "1️⃣2️⃣ Final node status..."
./blockchain_cli --json node status

echo ""
echo "✅ Demo completed!"
echo ""
echo "💡 Try these commands yourself:"
echo "   ./blockchain_cli --help"
echo "   ./blockchain_cli account create"
echo "   ./blockchain_cli block latest"
echo "   ./blockchain_cli --json node status | jq"