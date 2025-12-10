# LicenseToken
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/95a2b524a76f219f6ef11d45ce10720548eae569/src/LicenseToken.sol)

**Inherits:**
[ILicenseToken](/src/interfaces/ILicenseToken.sol/interface.ILicenseToken.md), Initializable, ERC1155Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable


## State Variables
### ARBITRATOR_ROLE

```solidity
bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
```


### IP_ASSET_ROLE

```solidity
bytes32 public constant IP_ASSET_ROLE = keccak256("IP_ASSET_ROLE");
```


### MARKETPLACE_ROLE

```solidity
bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
```


### DEFAULT_MAX_MISSED_PAYMENTS

```solidity
uint8 public constant DEFAULT_MAX_MISSED_PAYMENTS = 3;
```


### DEFAULT_PENALTY_RATE

```solidity
uint16 public constant DEFAULT_PENALTY_RATE = 500;
```


### MAX_PENALTY_RATE

```solidity
uint16 public constant MAX_PENALTY_RATE = 5000;
```


### licenses

```solidity
mapping(uint256 => License) public licenses;
```


### _isExpired

```solidity
mapping(uint256 => bool) private _isExpired;
```


### _hasExclusiveLicense

```solidity
mapping(uint256 => bool) private _hasExclusiveLicense;
```


### _privateAccessGrants

```solidity
mapping(uint256 => mapping(address => bool)) private _privateAccessGrants;
```


### _licenseIdCounter

```solidity
uint256 private _licenseIdCounter;
```


### ipAssetContract

```solidity
address public ipAssetContract;
```


### arbitratorContract

```solidity
address public arbitratorContract;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(string memory baseURI, address admin, address ipAsset, address arbitrator) external initializer;
```

### mintLicense


```solidity
function mintLicense(
    address to,
    uint256 ipAssetId,
    uint256 supply,
    string memory publicMetadataURI,
    string memory privateMetadataURI,
    uint256 expiryTime,
    string memory terms,
    bool isExclusive,
    uint256 paymentInterval,
    uint8 maxMissedPayments,
    uint16 penaltyRateBPS
) external onlyRole(IP_ASSET_ROLE) whenNotPaused returns (uint256);
```

### markExpired


```solidity
function markExpired(uint256 licenseId) external;
```

### batchMarkExpired


```solidity
function batchMarkExpired(uint256[] memory licenseIds) external;
```

### revokeLicense


```solidity
function revokeLicense(uint256 licenseId, string memory reason) external onlyRole(ARBITRATOR_ROLE);
```

### revokeForMissedPayments


```solidity
function revokeForMissedPayments(uint256 licenseId, uint256 missedCount) external;
```

### _revoke


```solidity
function _revoke(uint256 licenseId) internal;
```

### getPublicMetadata


```solidity
function getPublicMetadata(uint256 licenseId) external view returns (string memory);
```

### getPrivateMetadata


```solidity
function getPrivateMetadata(uint256 licenseId) external view returns (string memory);
```

### grantPrivateAccess


```solidity
function grantPrivateAccess(uint256 licenseId, address account) external;
```

### revokePrivateAccess


```solidity
function revokePrivateAccess(uint256 licenseId, address account) external;
```

### hasPrivateAccess


```solidity
function hasPrivateAccess(uint256 licenseId, address account) external view returns (bool);
```

### isRevoked


```solidity
function isRevoked(uint256 licenseId) external view returns (bool);
```

### isExpired


```solidity
function isExpired(uint256 licenseId) external view returns (bool);
```

### setArbitratorContract


```solidity
function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setIPAssetContract


```solidity
function setIPAssetContract(address ipAsset) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### grantRole


```solidity
function grantRole(bytes32 role, address account)
    public
    override(AccessControlUpgradeable, ILicenseToken)
    onlyRole(getRoleAdmin(role));
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC1155Upgradeable, AccessControlUpgradeable, ILicenseToken)
    returns (bool);
```

### getPaymentInterval


```solidity
function getPaymentInterval(uint256 licenseId) external view returns (uint256);
```

### isRecurring


```solidity
function isRecurring(uint256 licenseId) external view returns (bool);
```

### isOneTime


```solidity
function isOneTime(uint256 licenseId) external view returns (bool);
```

### getLicenseInfo


```solidity
function getLicenseInfo(uint256 licenseId)
    external
    view
    returns (
        uint256 ipAssetId,
        uint256 supply,
        uint256 expiryTime,
        string memory terms,
        uint256 paymentInterval,
        bool isExclusive,
        bool revokedStatus,
        bool expiredStatus
    );
```

### isActiveLicense


```solidity
function isActiveLicense(uint256 licenseId) external view returns (bool);
```

### getMaxMissedPayments


```solidity
function getMaxMissedPayments(uint256 licenseId) external view returns (uint8);
```

### getPenaltyRate


```solidity
function getPenaltyRate(uint256 licenseId) external view returns (uint16);
```

### _update


```solidity
function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override;
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```

### pause


```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### unpause


```solidity
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

