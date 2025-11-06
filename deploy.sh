#!/bin/bash

# Deploy IPAsset contract to Passet Hub
# Run this script from the project root directory

set -e

# Configuration
RPC_URL="https://testnet-passet-hub-eth-rpc.polkadot.io"
SCRIPT_PATH="script/DeployIPAsset.s.sol:DeployIPAsset"
MAX_RETRIES=3
RETRY_DELAY=10

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
echo "  Deploying IPAsset to Passet Hub"
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

# Check nonce
echo "Checking nonce..."
NONCE=$(cast nonce $DEPLOYER --rpc-url $RPC_URL)
echo "Current nonce: $NONCE"
echo ""

# Build contracts
echo "Building contracts..."
forge build
echo ""

# Deploy with retry logic
echo "Deploying IPAsset contract..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES..."

    if forge script $SCRIPT_PATH \
        --rpc-url $RPC_URL \
        --broadcast \
        --legacy \
        --slow \
        -vv \
        --skip-simulation; then
        echo ""
        echo "✓ Deployment successful!"
        echo ""
        echo "Check broadcast/DeployIPAsset.s.sol/420420422/run-latest.json for contract addresses"
        exit 0
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "❌ Deployment failed. Waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
            # Increase delay for next retry
            RETRY_DELAY=$((RETRY_DELAY * 2))
        fi
    fi
done

echo ""
echo "❌ Deployment failed after $MAX_RETRIES attempts"
echo ""
echo "Possible solutions:"
echo "1. Wait a few minutes and try again (transaction pool may be temporarily restricted)"
echo "2. Check if the RPC endpoint is working: cast client --rpc-url $RPC_URL"
echo "3. Try with a different gas price configuration"
echo ""
exit 1
