#!/bin/bash

# CLI Automation Example for Linux/macOS
# This script shows how to use the blockchain CLI for automation and scripting

NUM_ACCOUNTS=${1:-3}
INITIAL_FUNDING=${2:-1000}
TRANSFER_AMOUNT=${3:-100}

echo "🤖 Blockchain CLI Automation Example"
echo "Creating $NUM_ACCOUNTS accounts with $INITIAL_FUNDING tokens each"
echo ""

# Ensure CLI is built
if [ ! -f "../blockchain_cli" ]; then
    echo "Building CLI..."
    cd .. && nimble cli && cd examples
fi

CLI="../blockchain_cli"

# Start the node
echo "Starting blockchain node..."
$CLI node start

# Function to create account and extract address
create_account() {
    $CLI --json account create | jq -r '.address'
}

# Function to get balance
get_balance() {
    $CLI --json account balance $1 | jq -r '.balance'
}

# Create accounts
echo "Creating $NUM_ACCOUNTS accounts..."
accounts=()
for i in $(seq 1 $NUM_ACCOUNTS); do
    addr=$(create_account)
    accounts+=("$addr")
    echo "  Account $i: $addr"
done

# Fund accounts from genesis
echo ""
echo "Funding accounts from genesis..."
for addr in "${accounts[@]}"; do
    echo "  Funding $addr with $INITIAL_FUNDING tokens..."
    $CLI account transfer genesis $addr $INITIAL_FUNDING 10 > /dev/null
done

# Verify balances
echo ""
echo "Account balances after funding:"
for i in "${!accounts[@]}"; do
    balance=$(get_balance ${accounts[i]})
    echo "  Account $((i + 1)): $balance tokens"
done

# Simulate some transactions
echo ""
echo "Simulating transactions..."
for i in $(seq 0 $((${#accounts[@]} - 2))); do
    from=${accounts[i]}
    to=${accounts[$((i + 1))]}
    echo "  $from -> $to ($TRANSFER_AMOUNT tokens)"
    $CLI account transfer $from $to $TRANSFER_AMOUNT 5 > /dev/null
done

# Final balances
echo ""
echo "Final account balances:"
for i in "${!accounts[@]}"; do
    balance=$(get_balance ${accounts[i]})
    echo "  Account $((i + 1)): $balance tokens"
done

# Node statistics
echo ""
echo "Node Statistics:"
node_status=$($CLI --json node status)
echo "  Blockchain Height: $(echo $node_status | jq -r '.height')"
echo "  Pending Transactions: $(echo $node_status | jq -r '.pending_transactions')"
echo "  Active Validators: $(echo $node_status | jq -r '.validators')"

# Transaction summary
echo ""
echo "Pending Transactions:"
$CLI transaction list

echo ""
echo "✅ Automation example completed!"
echo ""
echo "💾 Account details saved to accounts.json"

# Save account details to JSON file
printf '{\n  "accounts": [\n'
for i in "${!accounts[@]}"; do
    printf '    {\n      "id": %d,\n      "address": "%s",\n      "balance": %s\n    }' \
        $((i + 1)) "${accounts[i]}" "$(get_balance ${accounts[i]})"
    if [ $i -lt $((${#accounts[@]} - 1)) ]; then
        printf ','
    fi
    printf '\n'
done
printf '  ]\n}\n' > accounts.json

echo ""
echo "📊 Summary:"
echo "  - Created: ${#accounts[@]} accounts"
echo "  - Initial funding: $INITIAL_FUNDING tokens each" 
echo "  - Transactions: $((${#accounts[@]} - 1)) transfers of $TRANSFER_AMOUNT tokens"
echo "  - Account details saved to: accounts.json"