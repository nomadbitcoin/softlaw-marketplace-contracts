# Softlaw Marketplace Contracts

Smart contracts for the Softlaw marketplace, built with Foundry for deployment on Polkadot's Asset Hub (PolkaVM).

## Prerequisites

### Install Foundry

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

### Environment Setup

```bash
cp .env.example .env
# Add your PRIVATE_KEY to .env
```

Get testnet tokens from [Polkadot Faucet](https://faucet.polkadot.io/)

## Testing

Run tests (default profile uses Solc for EVM):
```bash
forge test                                    # All tests
forge test --match-path "test/base/*.t.sol"  # Base contracts only
forge test --match-contract IPAssetTest       # Specific contract
```

### Gas Reports

```bash
forge test --gas-report                                   # All contracts
forge test --match-path "test/base/*.t.sol" --gas-report # Base contracts only
```

### Coverage

```bash
forge coverage                          # Terminal output
forge coverage --report lcov            # LCOV format
forge coverage --report html            # HTML report
open coverage/index.html                # View in browser
```

## Building

### PolkaVM Build

```bash
FOUNDRY_PROFILE=polkavm forge build
```

### Check Bytecode Size

```bash
# Check bytecode size (must be < 100KB)
FOUNDRY_PROFILE=polkavm forge inspect IPAsset bytecode | wc -c

# Verify PolkaVM prefix (should be 0x5056)
FOUNDRY_PROFILE=polkavm forge inspect IPAsset bytecode | head -c 6
```

### Size Calculation

```bash
bytecode=$(FOUNDRY_PROFILE=polkavm forge inspect IPAsset bytecode)
size=$(((${#bytecode} - 2) / 2))
kb=$(echo "scale=2; $size / 1024" | bc)
echo "IPAsset: $kb KB (limit: 100 KB)"
```

## Deployment

### Quick Deploy (Testnet)

```bash
foundryup-polkadot
FOUNDRY_PROFILE=polkavm forge build
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

## Networks

### Passet Hub (Testnet)

- **RPC**: `https://testnet-passet-hub-eth-rpc.polkadot.io`
- **Chain ID**: `420420422`
- **Explorer**: https://polkadot-hub-testnet.blockscout.com/
- **Faucet**: https://faucet.polkadot.io/

### Polkadot Hub (Mainnet)

Check [Polkadot docs](https://docs.polkadot.com/polkadot-protocol/smart-contract-basics/networks/) for mainnet endpoints.

## Verification

After deployment:

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
│   └── base/         # Minimal base contracts for PolkaVM
├── script/           # Deployment scripts
├── test/             # Test files
│   └── base/         # Base contract tests
├── lib/              # Dependencies (forge-std)
├── foundry.toml      # Foundry configuration
├── .env              # Environment variables (not committed)
└── docs/             # Documentation and stories
```

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
- [Base Contracts Documentation](src/base/README.md)

## License

MIT
