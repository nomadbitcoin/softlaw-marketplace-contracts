# ILicenseToken
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/95a2b524a76f219f6ef11d45ce10720548eae569/src/interfaces/ILicenseToken.sol)

Interface for License Token contract (ERC-1155 semi-fungible tokens)

*Manages licenses for IP assets with expiry and revocation*

*Payment tracking is handled by Marketplace contract*


## Functions
### initialize

Initializes the LicenseToken contract (proxy pattern)

*Sets up ERC1155, AccessControl, and contract references*

*Grants DEFAULT_ADMIN_ROLE, ARBITRATOR_ROLE, and IP_ASSET_ROLE*

*Can only be called once due to initializer modifier*


```solidity
function initialize(string memory baseURI, address admin, address ipAsset, address arbitrator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`baseURI`|`string`|Base URI for token metadata|
|`admin`|`address`|Address to receive all initial admin roles|
|`ipAsset`|`address`|Address of the IPAsset contract (granted IP_ASSET_ROLE)|
|`arbitrator`|`address`|Address of the GovernanceArbitrator contract (granted ARBITRATOR_ROLE)|


### mintLicense

Mints a new license token

*Only callable by IP_ASSET_ROLE through IPAsset contract*

*Validates IP asset exists via hasActiveDispute() call*

*Exclusive licenses must have supply = 1 and only one can exist per IP asset*

*If maxMissedPayments = 0, defaults to DEFAULT_MAX_MISSED_PAYMENTS (3)*

*If penaltyRateBPS = 0, defaults to DEFAULT_PENALTY_RATE (500)*

*penaltyRateBPS must be <= MAX_PENALTY_RATE (5000)*

*Updates IP asset active license count*


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
) external returns (uint256 licenseId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Address to receive the license|
|`ipAssetId`|`uint256`|The IP asset to license|
|`supply`|`uint256`|Number of license tokens to mint (must be 1 for exclusive licenses)|
|`publicMetadataURI`|`string`|Publicly accessible metadata|
|`privateMetadataURI`|`string`|Private metadata (access controlled)|
|`expiryTime`|`uint256`|Unix timestamp when license expires (0 = perpetual)|
|`terms`|`string`|Human-readable license terms|
|`isExclusive`|`bool`|Whether this is an exclusive license|
|`paymentInterval`|`uint256`|Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)|
|`maxMissedPayments`|`uint8`|Maximum missed payments before auto-revocation (0 = use DEFAULT_MAX_MISSED_PAYMENTS)|
|`penaltyRateBPS`|`uint16`|Penalty rate in basis points per month (0 = use DEFAULT_PENALTY_RATE, max = MAX_PENALTY_RATE)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The ID of the newly minted license|


### markExpired

Marks a license as expired

*Can be called by anyone once expiry time has passed*

*Perpetual licenses (expiryTime = 0) cannot be expired*

*Updates IP asset active license count*


```solidity
function markExpired(uint256 licenseId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license to mark as expired|


### batchMarkExpired

Marks multiple licenses as expired in a single transaction

*Continues on error - does not revert entire batch if individual license fails*


```solidity
function batchMarkExpired(uint256[] memory licenseIds) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseIds`|`uint256[]`|Array of license IDs to mark as expired|


### revokeLicense

Revokes a license

*Only callable by ARBITRATOR_ROLE (dispute resolution)*

*Clears exclusive license flag if applicable*

*Updates IP asset active license count*


```solidity
function revokeLicense(uint256 licenseId, string memory reason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license to revoke|
|`reason`|`string`|Human-readable revocation reason|


### revokeForMissedPayments

Revokes a license for missed payments

*Anyone can call this function, but it will only succeed if missedCount >= maxMissedPayments*

*Payment tracking is handled by Marketplace contract*

*Spam prevention: built-in validation requires missedCount to meet threshold*

*Clears exclusive license flag if applicable*

*Updates IP asset active license count*


```solidity
function revokeForMissedPayments(uint256 licenseId, uint256 missedCount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license to revoke|
|`missedCount`|`uint256`|Number of missed payments (must meet maxMissedPayments threshold)|


### getPublicMetadata

Gets the public metadata URI for a license


```solidity
function getPublicMetadata(uint256 licenseId) external view returns (string memory uri);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`uri`|`string`|The public metadata URI|


### getPrivateMetadata

Gets the private metadata URI for a license

*Access controlled - only license holder, granted accounts, and admin*


```solidity
function getPrivateMetadata(uint256 licenseId) external view returns (string memory uri);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`uri`|`string`|The private metadata URI|


### grantPrivateAccess

Grants access to private metadata for an account

*Only license holder can grant access*


```solidity
function grantPrivateAccess(uint256 licenseId, address account) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|
|`account`|`address`|The account to grant access to|


### revokePrivateAccess

Revokes private metadata access from an account

*Only license holder can revoke access*


```solidity
function revokePrivateAccess(uint256 licenseId, address account) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|
|`account`|`address`|The account to revoke access from|


### hasPrivateAccess

Checks if an account has been granted private metadata access


```solidity
function hasPrivateAccess(uint256 licenseId, address account) external view returns (bool hasAccess);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|
|`account`|`address`|The account to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hasAccess`|`bool`|Whether the account has been granted access|


### isRevoked

Checks if a license is revoked


```solidity
function isRevoked(uint256 licenseId) external view returns (bool revoked);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`revoked`|`bool`|Whether the license is revoked|


### isExpired

Checks if a license is expired


```solidity
function isExpired(uint256 licenseId) external view returns (bool expired);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`expired`|`bool`|Whether the license is expired|


### setArbitratorContract

Updates the GovernanceArbitrator contract address

*Only callable by DEFAULT_ADMIN_ROLE*

*Revokes ARBITRATOR_ROLE from old address and grants to new address*


```solidity
function setArbitratorContract(address arbitrator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`arbitrator`|`address`|New arbitrator contract address (cannot be zero address)|


### setIPAssetContract

Updates the IPAsset contract address

*Only callable by DEFAULT_ADMIN_ROLE*

*Revokes IP_ASSET_ROLE from old address and grants to new address*


```solidity
function setIPAssetContract(address ipAsset) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAsset`|`address`|New IP asset contract address (cannot be zero address)|


### grantRole

Grants a role to an account

*Only callable by role admin*


```solidity
function grantRole(bytes32 role, address account) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`role`|`bytes32`|The role identifier|
|`account`|`address`|The account to grant the role to|


### supportsInterface

Checks if contract supports a given interface


```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool supported);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|The interface identifier (ERC-165)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`supported`|`bool`|Whether the interface is supported|


### getPaymentInterval

Gets the payment interval for a license


```solidity
function getPaymentInterval(uint256 licenseId) external view returns (uint256 interval);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`interval`|`uint256`|Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)|


### isRecurring

Checks if a license has recurring payments


```solidity
function isRecurring(uint256 licenseId) external view returns (bool recurring);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`recurring`|`bool`|True if payment interval > 0|


### isOneTime

Checks if a license is one-time payment


```solidity
function isOneTime(uint256 licenseId) external view returns (bool oneTime);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`oneTime`|`bool`|True if payment interval == 0|


### getLicenseInfo

Gets comprehensive license information


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
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset this license is for|
|`supply`|`uint256`|Number of license tokens minted|
|`expiryTime`|`uint256`|Unix timestamp when license expires|
|`terms`|`string`|Human-readable license terms|
|`paymentInterval`|`uint256`|Payment interval in seconds|
|`isExclusive`|`bool`|Whether this is an exclusive license|
|`revokedStatus`|`bool`|Whether the license has been revoked|
|`expiredStatus`|`bool`|Whether the license has expired|


### isActiveLicense

Checks if a license is currently active

*A license is active if it is neither revoked nor expired*


```solidity
function isActiveLicense(uint256 licenseId) external view returns (bool active);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`active`|`bool`|True if license is not revoked and not expired|


### getMaxMissedPayments

Gets the maximum number of missed payments allowed for a license


```solidity
function getMaxMissedPayments(uint256 licenseId) external view returns (uint8 maxMissed);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`maxMissed`|`uint8`|Maximum number of missed payments before auto-revocation|


### getPenaltyRate

Gets the penalty rate for a license


```solidity
function getPenaltyRate(uint256 licenseId) external view returns (uint16 penaltyRate);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`penaltyRate`|`uint16`|Penalty rate in basis points (100 bps = 1% per month)|


## Events
### LicenseCreated
Emitted when a new license is created


```solidity
event LicenseCreated(
    uint256 indexed licenseId,
    uint256 indexed ipAssetId,
    address indexed licensee,
    bool isExclusive,
    uint256 paymentInterval
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The ID of the newly created license|
|`ipAssetId`|`uint256`|The IP asset this license is for|
|`licensee`|`address`|The address receiving the license|
|`isExclusive`|`bool`|Whether this is an exclusive license|
|`paymentInterval`|`uint256`|Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)|

### LicenseExpired
Emitted when a license expires


```solidity
event LicenseExpired(uint256 indexed licenseId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license that expired|

### LicenseRevoked
Emitted when a license is revoked


```solidity
event LicenseRevoked(uint256 indexed licenseId, string reason);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license that was revoked|
|`reason`|`string`|Human-readable revocation reason|

### AutoRevoked
Emitted when a license is automatically revoked for missed payments


```solidity
event AutoRevoked(uint256 indexed licenseId, uint256 missedPayments);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license that was auto-revoked|
|`missedPayments`|`uint256`|Number of missed payments that triggered revocation|

### PrivateAccessGranted
Emitted when private metadata access is granted


```solidity
event PrivateAccessGranted(uint256 indexed licenseId, address indexed account);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|
|`account`|`address`|The account granted access|

### PrivateAccessRevoked
Emitted when private metadata access is revoked


```solidity
event PrivateAccessRevoked(uint256 indexed licenseId, address indexed account);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|
|`account`|`address`|The account whose access was revoked|

### ArbitratorContractUpdated
Emitted when the arbitrator contract is updated


```solidity
event ArbitratorContractUpdated(address indexed oldArbitrator, address indexed newArbitrator);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldArbitrator`|`address`|The previous arbitrator contract address|
|`newArbitrator`|`address`|The new arbitrator contract address|

### IPAssetContractUpdated
Emitted when the IP asset contract is updated


```solidity
event IPAssetContractUpdated(address indexed oldIPAsset, address indexed newIPAsset);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`oldIPAsset`|`address`|The previous IP asset contract address|
|`newIPAsset`|`address`|The new IP asset contract address|

## Errors
### InvalidIPAsset
Thrown when attempting to create license for invalid IP asset


```solidity
error InvalidIPAsset();
```

### InvalidSupply
Thrown when license supply is invalid (e.g., zero)


```solidity
error InvalidSupply();
```

### ExclusiveLicenseMustHaveSupplyOne
Thrown when exclusive license does not have supply of exactly 1


```solidity
error ExclusiveLicenseMustHaveSupplyOne();
```

### ExclusiveLicenseAlreadyExists
Thrown when attempting to create multiple exclusive licenses for same IP


```solidity
error ExclusiveLicenseAlreadyExists();
```

### LicenseIsPerpetual
Thrown when attempting to expire a perpetual license


```solidity
error LicenseIsPerpetual();
```

### LicenseNotYetExpired
Thrown when attempting to mark a license as expired before expiry time


```solidity
error LicenseNotYetExpired();
```

### AlreadyMarkedExpired
Thrown when attempting to mark an already expired license as expired


```solidity
error AlreadyMarkedExpired();
```

### AlreadyRevoked
Thrown when attempting to revoke an already revoked license


```solidity
error AlreadyRevoked();
```

### NotAuthorizedForPrivateMetadata
Thrown when unauthorized access to private metadata is attempted


```solidity
error NotAuthorizedForPrivateMetadata();
```

### NotLicenseOwner
Thrown when non-license owner attempts owner-only operation


```solidity
error NotLicenseOwner();
```

### InsufficientMissedPayments
Thrown when insufficient missed payments for auto-revocation


```solidity
error InsufficientMissedPayments();
```

### CannotTransferExpiredLicense
Thrown when attempting to transfer an expired license


```solidity
error CannotTransferExpiredLicense();
```

### CannotTransferRevokedLicense
Thrown when attempting to transfer a revoked license


```solidity
error CannotTransferRevokedLicense();
```

### InvalidArbitratorAddress
Thrown when attempting to set arbitrator to zero address


```solidity
error InvalidArbitratorAddress();
```

### InvalidIPAssetAddress
Thrown when attempting to set IP asset contract to zero address


```solidity
error InvalidIPAssetAddress();
```

### InvalidMaxMissedPayments
Thrown when maxMissedPayments is zero or exceeds allowed maximum


```solidity
error InvalidMaxMissedPayments();
```

### InvalidPenaltyRate
Thrown when penalty rate exceeds maximum allowed rate


```solidity
error InvalidPenaltyRate();
```

## Structs
### License
*License configuration and state*


```solidity
struct License {
    uint256 ipAssetId;
    uint256 supply;
    uint256 expiryTime;
    string terms;
    bool isExclusive;
    bool isRevoked;
    string publicMetadataURI;
    string privateMetadataURI;
    uint256 paymentInterval;
    uint8 maxMissedPayments;
    uint16 penaltyRateBPS;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset this license is for|
|`supply`|`uint256`|Number of license tokens minted (ERC-1155 supply)|
|`expiryTime`|`uint256`|Unix timestamp when license expires (0 = perpetual, never expires)|
|`terms`|`string`|Human-readable license terms|
|`isExclusive`|`bool`|Whether this is an exclusive license|
|`isRevoked`|`bool`|Whether the license has been revoked|
|`publicMetadataURI`|`string`|Publicly accessible metadata URI|
|`privateMetadataURI`|`string`|Private metadata URI (access controlled)|
|`paymentInterval`|`uint256`|Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)|
|`maxMissedPayments`|`uint8`|Maximum number of missed payments before auto-revocation (1-255, 0 defaults to 3)|
|`penaltyRateBPS`|`uint16`|Penalty rate in basis points (100 bps = 1% per month, 0 defaults to 500, max 5000 = 50%)|

