#!/bin/bash

# Deploy Counter contract to Passet Hub
# Run this script from the project root directory

set -e

# Configuration
RPC_URL="https://testnet-passet-hub-eth-rpc.polkadot.io"

# Load environment variables
if [ -f ".env" ]; then
    source .env
else
    echo "❌ Error: .env file not found"
    echo "Create a .env file with: PRIVATE_KEY=your_private_key_here"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not set in .env"
    exit 1
fi

echo ""
echo "========================================="
echo "  Deploying Counter to Passet Hub"
echo "========================================="
echo ""

# Get deployer address
DEPLOYER=$(cast wallet address --private-key $PRIVATE_KEY)
echo "Deployer: $DEPLOYER"
echo ""

# Check balance
echo "Checking balance..."
BALANCE=$(cast balance $DEPLOYER --rpc-url $RPC_URL)
BALANCE_ETH=$(cast --from-wei $BALANCE)
echo "Balance: $BALANCE_ETH ETH"

if [ "$BALANCE" = "0" ]; then
    echo "⚠️  Warning: Balance is 0. Get testnet tokens from: https://faucet.polkadot.io/"
    exit 1
fi
echo ""

# Build contracts
echo "Building contracts with Resolc..."
forge build
echo ""

# Deploy using forge create
echo "Deploying Counter contract..."
forge create src/Counter.sol:Counter \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

echo ""
echo "✓ Deployment complete!"
echo ""
echo "To verify the deployment, update CONTRACT_ADDRESS in verify-deployment.sh"
echo "and run: ./verify-deployment.sh"
echo ""
