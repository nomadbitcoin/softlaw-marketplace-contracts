# Softlaw Marketplace Contracts

Smart contracts for the Softlaw marketplace, built with Foundry and designed for deployment on Polkadot's Asset Hub (PolkaVM).

## Overview

This project uses Foundry with Resolc compiler support for PolkaVM-compatible smart contract development. It supports both standard EVM testing and PolkaVM deployment.

## Prerequisites

### Install Foundry (both versions required)

**Standard Foundry** (for testing):
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

**Foundry-Polkadot** (for PolkaVM deployment):
```bash
curl -L https://raw.githubusercontent.com/paritytech/foundry-polkadot/refs/heads/master/foundryup/install | bash
foundryup-polkadot
```

### Setup Environment

```bash
cp .env.example .env
# Add your PRIVATE_KEY to .env
```

Get testnet tokens from [Polkadot Faucet](https://faucet.polkadot.io/)

## Development

### Testing

Use standard Foundry for testing:

```bash
foundryup
forge test
```

### Building

For PolkaVM deployment, use foundry-polkadot:

```bash
foundryup-polkadot
forge build
```

## Deployment

### Quick Deploy (Testnet)

```bash
foundryup-polkadot
forge build
./deploy.sh
```

### Manual Deploy

```bash
source .env
forge create src/Counter.sol:Counter \
  --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
  --private-key $PRIVATE_KEY
```

### Deploy with Script

```bash
source .env
forge script script/Counter.s.sol:CounterScript \
  --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Network Configuration

### Passet Hub (Testnet)

- **RPC**: `https://testnet-passet-hub-eth-rpc.polkadot.io`
- **Chain ID**: `420420422`
- **Explorer**: https://polkadot-hub-testnet.blockscout.com/
- **Faucet**: https://faucet.polkadot.io/

### Polkadot Hub (Mainnet)

Check [Polkadot docs](https://docs.polkadot.com/polkadot-protocol/smart-contract-basics/networks/) for mainnet endpoints.

## Verification

After deployment, update `CONTRACT_ADDRESS` in `verify-deployment.sh` and run:

```bash
./verify-deployment.sh
```

Or verify manually:

```bash
# Check contract exists
cast code <CONTRACT_ADDRESS> --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Read state
cast call <CONTRACT_ADDRESS> "number()" --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Send transaction
source .env
cast send <CONTRACT_ADDRESS> "increment()" \
  --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
  --private-key $PRIVATE_KEY
```

## Project Structure

```
.
├── src/              # Smart contracts
├── script/           # Deployment scripts
├── test/             # Test files
├── lib/              # Dependencies (forge-std)
├── foundry.toml      # Foundry configuration
├── .env              # Environment variables (not committed)
├── deploy.sh         # Deployment automation
└── verify-deployment.sh  # Contract verification
```

## Compiler Versions

- **Standard Foundry**: v1.4.3-stable (testing)
- **Foundry-Polkadot**: v1.1.0-stable with Resolc v0.4.1 (deployment)

Switch between versions:
```bash
foundryup          # Standard Foundry
foundryup-polkadot # Foundry-Polkadot
```

## Troubleshooting

**"No contract bytecode"**:
- Ensure you're in the project root
- Run `forge build` first
- Verify foundry-polkadot is active: `forge --version`

**"--resolc-compile not recognized"**:
- Switch to foundry-polkadot: `foundryup-polkadot`

**"Compilation skipped"**:
- Force rebuild: `forge clean && forge build --force`

## Security

- Never commit private keys (`.env` is gitignored)
- Use hardware wallets for mainnet deployments
- Test thoroughly on testnet before mainnet
- Use keystore for production:
  ```bash
  cast wallet import deployer --interactive
  forge script --account deployer --sender <address>
  ```

## Resources

- [Polkadot Developer Docs](https://docs.polkadot.com/)
- [Foundry-Polkadot](https://github.com/paritytech/foundry-polkadot)
- [Foundry Book](https://book.getfoundry.sh/)

## License

[Add your license here]
