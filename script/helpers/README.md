# Action Scripts

Individual scripts for manual testing on Asset Hub. Since `cast` commands don't work reliably on Asset Hub, use these Solidity scripts instead.

## Configuration

Before using these scripts, update the contract addresses in each file:
- `IPASSET_PROXY` - Your IPAsset proxy address
- `LICENSE_TOKEN_PROXY` - Your LicenseToken proxy address
- `MARKETPLACE_PROXY` - Your Marketplace proxy address
- Other configuration values as needed

## Available Scripts

### IP Asset Operations

#### MintIPAsset.s.sol
Mint a new IP Asset NFT.
```bash
forge script script/helpers/MintIPAsset.s.sol:MintIPAsset --rpc-url passetHub --broadcast
```

#### CheckIPAsset.s.sol
View IP Asset details (owner, metadata, license count, etc.)
```bash
forge script script/helpers/CheckIPAsset.s.sol:CheckIPAsset --rpc-url passetHub -vv
```

#### UpdateMetadata.s.sol
Update an IP Asset's metadata URI.
```bash
forge script script/helpers/UpdateMetadata.s.sol:UpdateMetadata --rpc-url passetHub --broadcast
```

### License Operations

#### MintLicense.s.sol
Mint a new license for an IP Asset.
```bash
forge script script/helpers/MintLicense.s.sol:MintLicense --rpc-url passetHub --broadcast
```

#### CheckLicense.s.sol
View license details (balance, info, status).
```bash
forge script script/helpers/CheckLicense.s.sol:CheckLicense --rpc-url passetHub -vv
```

### Revenue Operations

#### ConfigureRevenueSplit.s.sol
Configure revenue split for an IP Asset.
```bash
forge script script/helpers/ConfigureRevenueSplit.s.sol:ConfigureRevenueSplit --rpc-url passetHub --broadcast
```

### Marketplace Operations

#### CreateListing.s.sol
Create a marketplace listing for an IP Asset.
```bash
forge script script/helpers/CreateListing.s.sol:CreateListing --rpc-url passetHub --broadcast
```

## Tips

1. **Read-only operations**: Scripts that only read data (Check*.s.sol) don't need `--broadcast`
2. **Write operations**: Scripts that modify state need `--broadcast` flag
3. **Verbosity**: Add `-vv` or `-vvv` for more detailed output
4. **Configuration**: Edit the constants at the top of each script before running

## Example Workflow

1. Deploy contracts using `../DeployProduction.s.sol`
2. Update addresses in helper scripts
3. Mint an IP Asset: `MintIPAsset.s.sol`
4. Check it was created: `CheckIPAsset.s.sol`
5. Mint a license: `MintLicense.s.sol`
6. Check license: `CheckLicense.s.sol`
