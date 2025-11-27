# IIPAsset
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/deaf418b415477f4b81161589e5d319de1e2522a/src/interfaces/IIPAsset.sol)

Interface for IP Asset NFT contract representing intellectual property ownership

*ERC-721 upgradeable contract with metadata versioning and license management*


## Functions
### initialize

Initializes the IPAsset contract (proxy pattern)

*Sets up ERC721, AccessControl, Pausable, and UUPS upgradeable patterns*


```solidity
function initialize(string memory name, string memory symbol, address admin, address licenseToken, address arbitrator)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|The name for the ERC721 token|
|`symbol`|`string`|The symbol for the ERC721 token|
|`admin`|`address`|Address to receive all initial admin roles (DEFAULT_ADMIN, PAUSER, UPGRADER)|
|`licenseToken`|`address`|Address of the LicenseToken contract|
|`arbitrator`|`address`|Address of the GovernanceArbitrator contract|


### mintIP

Mints a new IP asset NFT

*Creates a token with auto-incrementing ID and stores initial metadata*


```solidity
function mintIP(address to, string memory metadataURI) external returns (uint256 tokenId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`to`|`address`|Address to receive the newly minted IP asset|
|`metadataURI`|`string`|IPFS or HTTP URI pointing to IP metadata|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The ID of the newly minted token|


### mintLicense

Creates a new license for an IP asset

*Delegates to LicenseToken contract to mint the license.
Only the IP asset owner can mint licenses.
Emits LicenseRegistered event for off-chain tracking.*


```solidity
function mintLicense(
    uint256 ipTokenId,
    address licensee,
    uint256 supply,
    string memory publicMetadataURI,
    string memory privateMetadataURI,
    uint256 expiryTime,
    string memory terms,
    bool isExclusive,
    uint256 paymentInterval
) external returns (uint256 licenseId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipTokenId`|`uint256`|The IP asset to create a license for|
|`licensee`|`address`|Address to receive the license|
|`supply`|`uint256`|Number of license tokens to mint (ERC-1155 supply)|
|`publicMetadataURI`|`string`|Publicly visible license metadata URI|
|`privateMetadataURI`|`string`|Private license terms URI (access controlled)|
|`expiryTime`|`uint256`|Unix timestamp when license expires|
|`terms`|`string`|Human-readable license terms|
|`isExclusive`|`bool`|Whether this is an exclusive license|
|`paymentInterval`|`uint256`|Payment interval in seconds (0 = one-time, >0 = recurring)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The ID of the newly created license|


### updateMetadata

Updates the metadata URI for an IP asset

*Only the token owner can update. Creates a new version in history.*


```solidity
function updateMetadata(uint256 tokenId, string memory newURI) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`newURI`|`string`|The new metadata URI|


### configureRevenueSplit

Configures revenue split for an IP asset

*Only the token owner can configure. Delegates to RevenueDistributor.*


```solidity
function configureRevenueSplit(uint256 tokenId, address[] memory recipients, uint256[] memory shares) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`recipients`|`address[]`|Array of addresses to receive revenue shares|
|`shares`|`uint256[]`|Array of share amounts in basis points (must sum to 10000)|


### burn

Burns an IP asset NFT

*Only owner can burn. Blocked if active licenses exist or dispute is active.*


```solidity
function burn(uint256 tokenId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID to burn|


### setDisputeStatus

Sets the dispute status for an IP asset

*Only callable by ARBITRATOR_ROLE (GovernanceArbitrator contract)*


```solidity
function setDisputeStatus(uint256 tokenId, bool hasDispute) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`hasDispute`|`bool`|Whether there is an active dispute|


### setLicenseTokenContract

Updates the LicenseToken contract address

*Only callable by admin*


```solidity
function setLicenseTokenContract(address licenseToken) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseToken`|`address`|New LicenseToken contract address|


### setArbitratorContract

Updates the GovernanceArbitrator contract address

*Only callable by admin*


```solidity
function setArbitratorContract(address arbitrator) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`arbitrator`|`address`|New GovernanceArbitrator contract address|


### setRevenueDistributorContract

Updates the RevenueDistributor contract address

*Only callable by admin*


```solidity
function setRevenueDistributorContract(address distributor) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`distributor`|`address`|New RevenueDistributor contract address|


### updateActiveLicenseCount

Updates the active license count for an IP asset

*Only callable by LICENSE_MANAGER_ROLE (LicenseToken contract)*


```solidity
function updateActiveLicenseCount(uint256 tokenId, int256 delta) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`delta`|`int256`|Change in license count (positive or negative)|


### hasActiveDispute

Checks if an IP asset has an active dispute


```solidity
function hasActiveDispute(uint256 tokenId) external view returns (bool hasDispute);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`hasDispute`|`bool`|Whether there is an active dispute|


### pause

Pauses all state-changing operations

*Only callable by DEFAULT_ADMIN_ROLE*


```solidity
function pause() external;
```

### unpause

Unpauses all state-changing operations

*Only callable by DEFAULT_ADMIN_ROLE*


```solidity
function unpause() external;
```

## Events
### IPMinted
Emitted when a new IP asset is minted


```solidity
event IPMinted(uint256 indexed tokenId, address indexed owner, string metadataURI);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The ID of the newly minted token|
|`owner`|`address`|The address that owns the new IP asset|
|`metadataURI`|`string`|The URI pointing to the IP metadata|

### MetadataUpdated
Emitted when IP metadata is updated

*Includes old and new URIs for complete off-chain indexing without state tracking*


```solidity
event MetadataUpdated(uint256 indexed tokenId, string oldURI, string newURI, uint256 timestamp);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The ID of the token being updated|
|`oldURI`|`string`|The previous metadata URI|
|`newURI`|`string`|The new metadata URI|
|`timestamp`|`uint256`|The block timestamp when update occurred|

### LicenseMinted
Emitted when a license is minted for an IP asset


```solidity
event LicenseMinted(uint256 indexed ipTokenId, uint256 indexed licenseId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipTokenId`|`uint256`|The IP asset token ID|
|`licenseId`|`uint256`|The newly created license ID|

### LicenseRegistered
Emitted when a license is registered for an IP asset

*This event provides complete license context for off-chain indexing without requiring array storage.
Indexers can build complete license lists by filtering this event by ipTokenId.
This replaces the need for on-chain ipToLicenses[] array storage (gas optimization).*


```solidity
event LicenseRegistered(
    uint256 indexed ipTokenId, uint256 indexed licenseId, address indexed licensee, uint256 supply, bool isExclusive
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipTokenId`|`uint256`|The IP asset token ID this license is for|
|`licenseId`|`uint256`|The ID of the newly registered license|
|`licensee`|`address`|The address receiving the license|
|`supply`|`uint256`|Number of license tokens minted (ERC-1155 supply)|
|`isExclusive`|`bool`|Whether this is an exclusive license|

### RevenueSplitConfigured
Emitted when revenue split is configured for an IP asset


```solidity
event RevenueSplitConfigured(uint256 indexed tokenId, address[] recipients, uint256[] shares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`recipients`|`address[]`|Array of recipient addresses|
|`shares`|`uint256[]`|Array of share percentages (must sum to 10000 basis points)|

### DisputeStatusChanged
Emitted when an IP asset's dispute status changes


```solidity
event DisputeStatusChanged(uint256 indexed tokenId, bool hasDispute);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`hasDispute`|`bool`|Whether the asset now has an active dispute|

### LicenseTokenContractSet
Emitted when the LicenseToken contract address is updated


```solidity
event LicenseTokenContractSet(address indexed newContract);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newContract`|`address`|The new LicenseToken contract address|

### ArbitratorContractSet
Emitted when the GovernanceArbitrator contract address is updated


```solidity
event ArbitratorContractSet(address indexed newContract);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newContract`|`address`|The new GovernanceArbitrator contract address|

### RevenueDistributorSet
Emitted when the RevenueDistributor contract address is updated


```solidity
event RevenueDistributorSet(address indexed newContract);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newContract`|`address`|The new RevenueDistributor contract address|

## Errors
### InvalidAddress
Thrown when attempting to mint to zero address


```solidity
error InvalidAddress();
```

### InvalidContractAddress
Thrown when setting a contract address to zero address


```solidity
error InvalidContractAddress(address contractAddress);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`contractAddress`|`address`|The invalid address that was attempted|

### EmptyMetadata
Thrown when metadata URI is empty


```solidity
error EmptyMetadata();
```

### NotTokenOwner
Thrown when caller is not the token owner


```solidity
error NotTokenOwner();
```

### HasActiveLicenses
Thrown when attempting to burn a token with active licenses


```solidity
error HasActiveLicenses(uint256 tokenId, uint256 count);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`count`|`uint256`|Number of active licenses preventing the burn|

### HasActiveDispute
Thrown when attempting to burn a token with an active dispute


```solidity
error HasActiveDispute(uint256 tokenId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|

### LicenseCountUnderflow
Thrown when attempting to decrement license count below zero


```solidity
error LicenseCountUnderflow(uint256 tokenId, uint256 current, uint256 attempted);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenId`|`uint256`|The IP asset token ID|
|`current`|`uint256`|Current license count|
|`attempted`|`uint256`|Amount attempting to decrement|

