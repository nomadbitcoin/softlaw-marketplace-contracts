# Minimal Base Contracts for PolkaVM Deployment

## Overview

This directory contains **minimal implementations** of OpenZeppelin-compatible base contracts, optimized for deployment on **PolkaVM** with its strict **100KB bytecode limit**.

These contracts remove non-essential features (extensions, complex logic) to drastically reduce bytecode size while maintaining core functionality, interface compatibility, and **essential events for industry tool support**.

---

## Attribution

All contracts in this directory are based on [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) (MIT License).

**Modifications:**
- Kept essential events for industry compatibility (wallets, indexers, explorers)
- Removed extensions (e.g., ERC721Enumerable, ERC721URIStorage)
- Simplified access control (no role hierarchy)
- Removed safety checks (e.g., ERC721 receiver callbacks) where necessary
- Minimal storage patterns

---

## Contracts

| Contract | Purpose | Events Included | Security Features |
|----------|---------|----------------|-------------------|
| `Initializable.sol` | Proxy initialization pattern | None | Basic initialization protection |
| `PausableUpgradeable.sol` | Pause/unpause functionality | Paused, Unpaused | Full pause mechanism |
| `AccessControlUpgradeable.sol` | Role-based access control | RoleGranted, RoleRevoked | Role-based permissions (single admin) |
| `ERC721Upgradeable.sol` | ERC721 NFT standard | Transfer, Approval, ApprovalForAll | Safe transfer with receiver checks ✅ |
| `IERC721Receiver.sol` | ERC721 receiver interface | N/A | Interface for safe transfers |
| `UUPSUpgradeable.sol` | UUPS upgrade mechanism | Upgraded | Upgrade authorization (no rollback) |
| `ERC1967Proxy.sol` | Minimal proxy for testing | N/A | Standard ERC-1967 proxy pattern |

**Total base overhead: ~21KB** (vs. ~85KB with standard OpenZeppelin)
**IPAsset bytecode: 86.3 KB** (8.7 KB under 95KB target)
**Zero external dependencies** (except forge-std for testing)

---

## Security Considerations

### CRITICAL Trade-offs for Production

#### 1. Essential Events & Safe Transfers Included
**Events:**
- **ERC721**: Transfer, Approval, ApprovalForAll (required for wallets, NFT platforms)
- **AccessControl**: RoleGranted, RoleRevoked (required for security monitoring)
- **Pausable**: Paused, Unpaused (required for incident tracking)
- **UUPS**: Upgraded (required for upgrade tracking)

**Safety Features:**
- **ERC721 Receiver Checks**: Full implementation with try/catch for safe transfers
- Prevents tokens being lost to non-receiver contracts
- Compatible with safeTransferFrom standard

**Benefit:** Full compatibility with OpenSea, MetaMask, Etherscan, and safe token transfers.

**Cost:**
- Events: +5.6 KB
- Receiver checks: +4.4 KB
- **Total: +10 KB** (still 8.7 KB under 95KB target)

#### 2. Simplified Role Hierarchy
**Impact:** Only `DEFAULT_ADMIN_ROLE` can grant/revoke other roles.

**Mitigation:**
- Sufficient for single admin model
- Use multi-sig wallet for admin role in production

#### 3. No Rollback Protection
**Impact:** Contract upgrades cannot be automatically rolled back.

**Mitigation:**
- Thoroughly test upgrades on testnet before production
- Implement governance timelock for upgrade proposals
- Maintain emergency pause mechanism

---

## Bytecode Size Achievements

### Before (Standard OpenZeppelin)
- IPAsset with OpenZeppelin: **~173KB** (exceeds PolkaVM limit)

### After (Minimal Base Contracts with Essential Events & Safe Transfers)
- **IPAsset size: 86.3 KB** (within limit, 8.7 KB headroom)
- **Reduction: ~87KB** (50.1% size reduction)
- **Events overhead: 5.6 KB** (essential for industry compatibility)
- **Receiver checks: 4.4 KB** (essential for security)

---

## Usage

```solidity
pragma solidity ^0.8.28;

import "./base/Initializable.sol";
import "./base/ERC721Upgradeable.sol";
import "./base/AccessControlUpgradeable.sol";
import "./base/PausableUpgradeable.sol";
import "./base/UUPSUpgradeable.sol";

contract IPAsset is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    function initialize() public initializer {
        __ERC721_init("IP Asset", "IPA");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }
}
```

---

## Testing

All base contracts have corresponding test files in `test/base/`:

- `test/base/Initializable.t.sol`
- `test/base/PausableUpgradeable.t.sol`
- `test/base/AccessControlUpgradeable.t.sol`
- `test/base/ERC721Upgradeable.t.sol`
- `test/base/UUPSUpgradeable.t.sol`

Run base contract tests:
```bash
# Default profile uses Solc for testing
forge test --match-path "test/base/*.t.sol" -vvv
```

## PolkaVM Compilation

To compile contracts for PolkaVM deployment with resolc:

```bash
# Use polkavm profile for production builds
FOUNDRY_PROFILE=polkavm forge build

# Check bytecode size
FOUNDRY_PROFILE=polkavm forge inspect IPAsset bytecode | wc -c

# Verify PolkaVM bytecode prefix (should be 0x5056)
FOUNDRY_PROFILE=polkavm forge inspect IPAsset bytecode | head -c 6
```

---

## ERC-165 Interface Support

Base contracts implement `supportsInterface()` for:

- **IERC165**: `0x01ffc9a7`
- **IERC721**: `0x80ac58cd`
- **IERC721Metadata**: `0x5b5e139f`
- **IAccessControl**: `0x7965db0b`

---

## Solidity Version

**Required:** `pragma solidity ^0.8.28;`

All base contracts use Solidity 0.8.28 for PolkaVM compatibility with `resolc` compiler.

---

## License

MIT License (inherited from OpenZeppelin Contracts)
