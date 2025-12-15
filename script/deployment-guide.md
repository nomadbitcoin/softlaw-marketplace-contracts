# Deployment Guide

Deploy all Softlaw Marketplace contracts to Passet Hub (or any EVM network).

## Deploy All Contracts (Recommended)

Single command to deploy all 5 contracts with proper initialization:

```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

**Deploys:**
1. IPAsset (ERC721 + proxy)
2. RevenueDistributor
3. LicenseToken (ERC1155 + proxy)
4. GovernanceArbitrator (+ proxy)
5. Marketplace (+ proxy)

**Then automatically:**
- Sets RevenueDistributor in Marketplace
- Sets LicenseToken and Arbitrator in IPAsset
- Grants IP_ASSET_ROLE to IPAsset in LicenseToken
- Verifies all connections

**Result:** Addresses saved to `deployments/<chain-id>.txt`

---

## Deploy Contracts Individually (Alternative)

Deploy one contract at a time for more control. Must follow this order:

### 1. Deploy IPAsset

```bash
forge script script/DeployIPAsset.s.sol:DeployIPAsset \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

Save proxy address:
```bash
echo "IPASSET_ADDRESS=<proxy-address>" >> .env
```

### 2. Deploy RevenueDistributor

```bash
forge script script/DeployRevenueDistributor.s.sol:DeployRevenueDistributor \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

Save address:
```bash
echo "REVENUE_DISTRIBUTOR_ADDRESS=<address>" >> .env
```

### 3. Deploy LicenseToken

```bash
forge script script/DeployLicenseToken.s.sol:DeployLicenseToken \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

Save proxy address:
```bash
echo "LICENSE_TOKEN_ADDRESS=<proxy-address>" >> .env
```

### 4. Deploy GovernanceArbitrator

```bash
forge script script/DeployGovernanceArbitrator.s.sol:DeployGovernanceArbitrator \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

Save proxy address:
```bash
echo "ARBITRATOR_ADDRESS=<proxy-address>" >> .env
```

### 5. Deploy Marketplace

```bash
forge script script/DeployMarketplace.s.sol:DeployMarketplace \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

Save proxy address:
```bash
echo "MARKETPLACE_ADDRESS=<proxy-address>" >> .env
```

### 6. Setup Addresses & Roles

Wire all contracts together:

```bash
forge script script/SetupAddresses.s.sol:SetupAddresses \
  --rpc-url passetHub \
  --broadcast \
  --legacy \
  -vv
```

This sets LicenseToken and Arbitrator in IPAsset, grants IP_ASSET_ROLE, and sets Arbitrator in LicenseToken.

**When to use individual deployment:**
- Deploy only specific contracts
- Update/replace a single contract
- Test deployment step by step
- Troubleshoot deployment issues

---

## Test Deployment First (Simulation)

Run without broadcasting to test:

```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url passetHub \
  -vv
```

Shows gas estimates and verifies logic without sending transactions.

---

## Check Deployed Addresses

```bash
cat deployments/420420422.txt
```

---

## Configuration

### Change Network

Edit `foundry.toml`:
```toml
[rpc_endpoints]
<your-network> = "<rpc-url>"
```

Then deploy:
```bash
forge script script/DeployProduction.s.sol:DeployProduction \
  --rpc-url <your-network> \
  --broadcast \
  --legacy \
  -vv
```

### Change Parameters

Edit `script/DeployProduction.s.sol`:
- Line 65-67: Platform fee (default 2.5%)
- Line 68: Default royalty (default 10%)
- Line 64: Treasury address
- Line 87: Metadata URI

---

## Troubleshooting

**RPC rate limiting:**
- Script has 3-second delays built-in
- If still limited, increase delays: edit line 46, 59, 72, etc. change `vm.sleep(3000)` to higher value

**Insufficient funds:**
```bash
# Check balance
cast balance <your-address> --rpc-url passetHub
```

**Check transaction history:**
```bash
ls broadcast/DeployProduction.s.sol/<chain-id>/
```

---

## Contract Details

| Contract | Type | Upgradeable |
|----------|------|-------------|
| IPAsset | ERC721 | Yes (UUPS) |
| LicenseToken | ERC1155 | Yes (UUPS) |
| GovernanceArbitrator | Governance | Yes (UUPS) |
| Marketplace | Trading | Yes (UUPS) |
| RevenueDistributor | Logic | No |

**Deployment takes:** ~1-2 minutes (13 transactions with delays)

---

**For Production:** Review parameters, test on testnet first, consider multi-sig for admin roles.
