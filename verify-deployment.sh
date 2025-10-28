#!/bin/bash

# Verify deployment script for Counter contract on Passet Hub
# This script validates basic contract functionality by testing read and write operations

set -e

# Configuration
RPC_URL="https://testnet-passet-hub-eth-rpc.polkadot.io"
CONTRACT_ADDRESS="0x168b38D9947E5b62f2CBDe1c50DC9780B30daD44"

# Load environment variables
if [ -f ".env" ]; then
    source .env
else
    echo "❌ Error: .env file not found"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ Error: PRIVATE_KEY not set in .env"
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo "========================================="
echo "  Counter Contract Verification"
echo "========================================="
echo ""
echo "Contract: $CONTRACT_ADDRESS"
echo "Network:  Passet Hub (Polkadot Hub TestNet)"
echo ""

# Test 1: Verify contract exists
echo -e "${BLUE}[1/5] Verifying contract exists...${NC}"
CODE=$(cast code $CONTRACT_ADDRESS --rpc-url $RPC_URL)
if [ ${#CODE} -gt 10 ]; then
    echo -e "${GREEN}✓ Contract code found (${#CODE} bytes)${NC}"
else
    echo -e "${RED}✗ Contract not found or no code at address${NC}"
    exit 1
fi
echo ""

# Test 2: Read initial number
echo -e "${BLUE}[2/5] Reading initial number...${NC}"
INITIAL_NUMBER=$(cast call $CONTRACT_ADDRESS "number()" --rpc-url $RPC_URL)
INITIAL_NUMBER_DEC=$(cast --to-dec $INITIAL_NUMBER)
echo -e "${GREEN}✓ Initial number: $INITIAL_NUMBER_DEC${NC}"
echo ""

# Test 3: Increment the number
echo -e "${BLUE}[3/5] Calling increment()...${NC}"
TX_HASH=$(cast send $CONTRACT_ADDRESS "increment()" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --json | jq -r '.transactionHash')
echo -e "${GREEN}✓ Transaction sent: $TX_HASH${NC}"
echo "  Waiting for confirmation..."
sleep 5
echo ""

# Test 4: Verify number increased
echo -e "${BLUE}[4/5] Reading number after increment...${NC}"
NEW_NUMBER=$(cast call $CONTRACT_ADDRESS "number()" --rpc-url $RPC_URL)
NEW_NUMBER_DEC=$(cast --to-dec $NEW_NUMBER)
EXPECTED=$((INITIAL_NUMBER_DEC + 1))
echo -e "${GREEN}✓ New number: $NEW_NUMBER_DEC${NC}"

if [ $NEW_NUMBER_DEC -eq $EXPECTED ]; then
    echo -e "${GREEN}✓ Increment successful! ($INITIAL_NUMBER_DEC → $NEW_NUMBER_DEC)${NC}"
else
    echo -e "${RED}✗ Increment failed! Expected $EXPECTED, got $NEW_NUMBER_DEC${NC}"
    exit 1
fi
echo ""

# Test 5: Set a specific number
TEST_VALUE=42
echo -e "${BLUE}[5/5] Setting number to $TEST_VALUE...${NC}"
TX_HASH=$(cast send $CONTRACT_ADDRESS "setNumber(uint256)" $TEST_VALUE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --json | jq -r '.transactionHash')
echo -e "${GREEN}✓ Transaction sent: $TX_HASH${NC}"
echo "  Waiting for confirmation..."
sleep 5

FINAL_NUMBER=$(cast call $CONTRACT_ADDRESS "number()" --rpc-url $RPC_URL)
FINAL_NUMBER_DEC=$(cast --to-dec $FINAL_NUMBER)
echo -e "${GREEN}✓ Final number: $FINAL_NUMBER_DEC${NC}"

if [ $FINAL_NUMBER_DEC -eq $TEST_VALUE ]; then
    echo -e "${GREEN}✓ setNumber() successful!${NC}"
else
    echo -e "${RED}✗ setNumber() failed! Expected $TEST_VALUE, got $FINAL_NUMBER_DEC${NC}"
    exit 1
fi
echo ""

# Summary
echo "========================================="
echo -e "${GREEN}✓ All tests passed!${NC}"
echo "========================================="
echo ""
echo "Contract Summary:"
echo "  Address:  $CONTRACT_ADDRESS"
echo "  Network:  Passet Hub"
echo "  Final Value: $FINAL_NUMBER_DEC"
echo ""
echo "View on explorer:"
echo "  https://polkadot-hub-testnet.blockscout.com/address/$CONTRACT_ADDRESS"
echo ""
