# Deployment and Testing Scripts

This folder contains scripts for deploying and testing the Softlaw Marketplace smart contracts on Asset Hub.

## Structure

```
script/
├── DeployProduction.s.sol          # Deploy all contracts at once
├── DeployIPAsset.s.sol             # Deploy IPAsset individually
├── DeployLicenseToken.s.sol        # Deploy LicenseToken individually
├── DeployRevenueDistributor.s.sol  # Deploy RevenueDistributor individually
├── DeployGovernanceArbitrator.s.sol # Deploy GovernanceArbitrator individually
├── DeployMarketplace.s.sol         # Deploy Marketplace individually
├── SetupAddresses.s.sol            # Setup and configure deployed contracts
├── UpdateAddresses.s.sol           # Helper to display addresses for action scripts
├── deployment-guide.md             # Deployment guide
└── helpers/                        # Individual helper scripts for manual testing
    ├── README.md                   # Helper scripts documentation
    ├── MintIPAsset.s.sol          # Mint an IP Asset
    ├── MintLicense.s.sol          # Mint a license
    ├── CheckIPAsset.s.sol         # Check IP Asset details
    ├── CheckLicense.s.sol         # Check license details
    ├── UpdateMetadata.s.sol       # Update IP Asset metadata
    ├── ConfigureRevenueSplit.s.sol # Configure revenue split
    └── CreateListing.s.sol        # Create marketplace listing
```

## Quick Start

### 1. Deploy All Contracts

```bash
forge script script/DeployProduction.s.sol:DeployProduction --rpc-url passetHub --broadcast -vv
```

This deploys:
- IPAsset (with proxy)
- RevenueDistributor
- LicenseToken (with proxy)
- GovernanceArbitrator (with proxy)
- Marketplace (with proxy)

**And sets up all relationships between contracts** - you don't need to run any additional setup scripts!

### 2. Update Helper Script Addresses

After deployment, **copy the proxy addresses** from the output and **manually edit** the constants at the top of each helper script in `script/helpers/*.s.sol`.

Example: In `script/helpers/MintIPAsset.s.sol`, update:
```solidity
address constant IPASSET_PROXY = 0xYourNewProxyAddress;
```

**Optional**: Run `UpdateAddresses.s.sol` to see all addresses formatted for easy copy/paste:
```bash
forge script script/UpdateAddresses.s.sol:UpdateAddresses --rpc-url passetHub -vv
```

### 3. Use Helper Scripts for Testing

See `helpers/README.md` for detailed usage of each helper script.

Example:
```bash
# Mint an IP Asset
forge script script/helpers/MintIPAsset.s.sol:MintIPAsset --rpc-url passetHub --broadcast

# Check IP Asset details
forge script script/helpers/CheckIPAsset.s.sol:CheckIPAsset --rpc-url passetHub -vv

# Mint a license
forge script script/helpers/MintLicense.s.sol:MintLicense --rpc-url passetHub --broadcast
```

## Individual Contract Deployment

If you need to deploy contracts individually:

```bash
# Deploy IPAsset only
forge script script/DeployIPAsset.s.sol:DeployIPAsset --rpc-url passetHub --broadcast

# Deploy LicenseToken only (requires IPAsset address)
forge script script/DeployLicenseToken.s.sol:DeployLicenseToken --rpc-url passetHub --broadcast

# etc...
```

## Important Notes for Asset Hub

### Why Solidity Scripts Instead of Cast?

Asset Hub's RPC has issues with `cast` commands:
- ✅ **Transactions work**: Broadcasting works fine
- ❌ **Reading fails**: `cast code`, `cast call` often return empty
- ✅ **Solution**: Use Solidity scripts for both reading and writing

### Best Practices

1. **Always use Solidity scripts** for testing (not `cast` commands)
2. **Read in same script** as writes when possible
3. **Use -vv flag** to see detailed logs
4. **Update addresses** after each deployment

## Testing Workflow

1. **Deploy**: Run `DeployProduction.s.sol` (this sets up everything!)
2. **Copy Addresses**: Note the proxy addresses from the deployment output
3. **Update Helper Scripts**: Manually edit the constants in `script/helpers/*.s.sol` files
4. **Test**: Use helper scripts to mint, check, and interact with contracts

## Environment Variables

Required in `.env`:
```bash
PRIVATE_KEY=your_private_key_here
```

RPC endpoints are configured in `foundry.toml`:
```toml
[rpc_endpoints]
passetHub = "https://testnet-passet-hub-eth-rpc.polkadot.io"
```

## Support

See individual script files for usage instructions and configuration options.
