# IPAsset
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/95a2b524a76f219f6ef11d45ce10720548eae569/src/IPAsset.sol)

**Inherits:**
Initializable, ERC721Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, [IIPAsset](/src/interfaces/IIPAsset.sol/interface.IIPAsset.md)


## State Variables
### LICENSE_MANAGER_ROLE

```solidity
bytes32 public constant LICENSE_MANAGER_ROLE = keccak256("LICENSE_MANAGER_ROLE");
```


### ARBITRATOR_ROLE

```solidity
bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
```


### licenseTokenContract

```solidity
address public licenseTokenContract;
```


### arbitratorContract

```solidity
address public arbitratorContract;
```


### revenueDistributor

```solidity
address public revenueDistributor;
```


### _tokenIdCounter

```solidity
uint256 private _tokenIdCounter;
```


### _metadataURIs

```solidity
mapping(uint256 => string) private _metadataURIs;
```


### activeLicenseCount

```solidity
mapping(uint256 => uint256) public activeLicenseCount;
```


### _hasActiveDispute

```solidity
mapping(uint256 => bool) private _hasActiveDispute;
```


### _privateMetadata

```solidity
mapping(uint256 => string) private _privateMetadata;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(string memory name, string memory symbol, address admin, address licenseToken, address arbitrator)
    external
    initializer;
```

### mintIP


```solidity
function mintIP(address to, string memory metadataURI) external whenNotPaused returns (uint256);
```

### mintLicense


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
) external whenNotPaused returns (uint256);
```

### updateMetadata


```solidity
function updateMetadata(uint256 tokenId, string memory newURI) external whenNotPaused;
```

### tokenURI


```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory);
```

### configureRevenueSplit


```solidity
function configureRevenueSplit(uint256 tokenId, address[] memory recipients, uint256[] memory shares)
    external
    whenNotPaused;
```

### setRoyaltyRate


```solidity
function setRoyaltyRate(uint256 tokenId, uint256 basisPoints) external whenNotPaused;
```

### burn


```solidity
function burn(uint256 tokenId) external whenNotPaused;
```

### setDisputeStatus


```solidity
function setDisputeStatus(uint256 tokenId, bool hasDispute) external onlyRole(ARBITRATOR_ROLE);
```

### setLicenseTokenContract


```solidity
function setLicenseTokenContract(address licenseToken) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setArbitratorContract


```solidity
function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setRevenueDistributorContract


```solidity
function setRevenueDistributorContract(address distributor) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### updateActiveLicenseCount


```solidity
function updateActiveLicenseCount(uint256 tokenId, int256 delta) external onlyRole(LICENSE_MANAGER_ROLE);
```

### hasActiveDispute


```solidity
function hasActiveDispute(uint256 tokenId) external view returns (bool);
```

### setPrivateMetadata


```solidity
function setPrivateMetadata(uint256 tokenId, string memory metadata) external whenNotPaused;
```

### getPrivateMetadata


```solidity
function getPrivateMetadata(uint256 tokenId) external view returns (string memory);
```

### pause


```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### unpause


```solidity
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    override(ERC721Upgradeable, AccessControlUpgradeable)
    returns (bool);
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```

