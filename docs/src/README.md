# Softlaw Marketplace Contracts

Smart contracts for the Softlaw marketplace, built with Foundry for deployment on Polkadot's Asset Hub (Passet Hub TestNet).

## Development Environment

### Option 1: DevContainer (Recommended)

This project includes a pre-configured DevContainer with all tools installed:

**Requirements:**
- Docker
- VS Code with Remote-Containers extension

**Setup:**
1. Open project in VS Code
2. Click "Reopen in Container" when prompted
3. Add your `PRIVATE_KEY` to `.env` file
4. Start developing - Foundry and all dependencies are pre-installed

The DevContainer automatically:
- Installs Foundry and Solidity tools
- Loads your `.env` file
- Configures the development environment
- Sets up git and shell aliases

### Option 2: Manual Setup

**Install Foundry:**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

**Setup Environment:**
```bash
cp .env.example .env
# Add your PRIVATE_KEY to .env
```

**Get Testnet Tokens:**
[Polkadot Faucet](https://faucet.polkadot.io/?parachain=1111)

### Build & Test

```bash
forge build                    # Build contracts
forge test                     # Run all tests
forge test --gas-report        # With gas usage
forge coverage                 # Coverage report
```

## Deployment

**See [Deployment Guide](script/deployment-guide.md) for complete instructions.**

Quick deploy all contracts:
```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

## Network Information

### Passet Hub (Testnet)

- **Network**: Polkadot Asset Hub TestNet
- **Chain ID**: `420420422`
- **RPC**: `https://testnet-passet-hub-eth-rpc.polkadot.io`
- **Explorer**: https://blockscout-passet-hub.parity-testnet.parity.io
- **Faucet**: https://faucet.polkadot.io/?parachain=1111

RPC endpoint configured in `foundry.toml` as `passetHub`.

## Documentation

### Build and View

```bash
# Build documentation
./build-docs.sh

# View locally
open docs/book/index.html

# Or serve with live reload
cd docs && mdbook serve --open
```

### What's Included

- **Architecture Diagrams**: 16 Mermaid diagrams showing system flow, contract interactions, and state machines
- **Contract Reference**: Auto-generated from NatSpec in interfaces
- **User Flows**: Step-by-step sequences for key operations

## Contract Architecture

The marketplace consists of 5 core contracts:

| Contract | Type | Description |
|----------|------|-------------|
| **IPAsset** | ERC721 | IP asset ownership and licensing |
| **LicenseToken** | ERC1155 | License ownership and management |
| **GovernanceArbitrator** | Governance | Dispute resolution and arbitration |
| **Marketplace** | Trading | IP asset and license marketplace |
| **RevenueDistributor** | Logic | Revenue sharing and royalties |

All contracts except RevenueDistributor use UUPS upgradeable pattern.

## Project Structure

```
.
├── src/              # Smart contracts
│   ├── interfaces/   # Contract interfaces
│   ├── IPAsset.sol
│   ├── LicenseToken.sol
│   ├── GovernanceArbitrator.sol
│   ├── Marketplace.sol
│   └── RevenueDistributor.sol
├── script/           # Deployment scripts
│   ├── deployment-guide.md        # Deployment instructions
│   ├── DeployProduction.s.sol     # Deploy all contracts
│   ├── DeployIPAsset.s.sol        # Individual deployments
│   └── SetupAddresses.s.sol       # Wire contracts together
└── test/             # Test files
```

## Testing

```bash
# Run all tests
forge test

# Specific test file
forge test --match-path "test/IPAsset.t.sol"

# Specific contract tests
forge test --match-contract IPAssetTest

# With gas reporting
forge test --gas-report

# Coverage
forge coverage
forge coverage --report html && open coverage/index.html
```

## Verification

After deployment, verify contracts:

```bash
# Check contract exists
cast code <CONTRACT_ADDRESS> --rpc-url passetHub

# Read contract data
cast call <CONTRACT_ADDRESS> "name()(string)" --rpc-url passetHub

# Send transaction
cast send <CONTRACT_ADDRESS> "mintIP(address,string)" $YOUR_ADDRESS "ipfs://metadata" \
  --rpc-url passetHub \
  --private-key $PRIVATE_KEY \
  --legacy
```