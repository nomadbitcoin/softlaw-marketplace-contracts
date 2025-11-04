# Softlaw Marketplace Contracts

Smart contracts for the Softlaw marketplace, built with Foundry for deployment on Polkadot's Asset Hub (PolkaVM).

## Prerequisites

### Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Environment Setup

```bash
cp .env.example .env
# Add your PRIVATE_KEY to .env
```

Get testnet tokens from [Polkadot Faucet](https://faucet.polkadot.io/?parachain=1111)

## Testing

Run tests:
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

### Build Contracts

```bash
forge build
```

## Deployment

### Deploy to Passet Hub Testnet

```bash
source .env
forge script script/DeployIPAsset.s.sol:DeployIPAsset \
  --rpc-url paseo \
  --broadcast \
  --private-key $PRIVATE_KEY
  --legacy
  --skip-simulation
```

### Quick Deploy Script

```bash
./deploy.sh
```

## Networks

### Passet Hub (Testnet)

- **Network**: Passet Hub (Polkadot Asset Hub TestNet)
- **Type**: EVM-compatible
- **Chain ID**: `420420422`
- **RPC**: `https://testnet-passet-hub-eth-rpc.polkadot.io`
- **Explorer**: https://blockscout-passet-hub.parity-testnet.parity.io
- **Faucet**: https://faucet.polkadot.io/?parachain=1111

### Polkadot Hub (Mainnet)

Check [Polkadot docs](https://docs.polkadot.com/polkadot-protocol/smart-contract-basics/networks/) for mainnet endpoints.

## Verification

After deployment:

```bash
# Check contract exists
cast code <CONTRACT_ADDRESS> --rpc-url paseo

# Verify initialization
cast call <CONTRACT_ADDRESS> "name()(string)" --rpc-url paseo

# Send transaction
source .env
cast send <CONTRACT_ADDRESS> "mintIP(address,string)" $YOUR_ADDRESS "ipfs://metadata" \
  --rpc-url paseo \
  --private-key $PRIVATE_KEY
```

## Project Structure

```
.
├── src/              # Smart contracts
│   ├── interfaces/   # Contract interfaces
│   └── base/         # Base contract implementations
├── script/           # Deployment scripts
├── test/             # Test files
│   └── base/         # Base contract tests
├── lib/              # Dependencies (forge-std, OpenZeppelin)
├── foundry.toml      # Foundry configuration
├── .env              # Environment variables (not committed)
└── docs/             # Documentation and architecture
    ├── architecture/ # Technical specifications
    └── stories/      # User stories and epics
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
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)

## License

MIT
