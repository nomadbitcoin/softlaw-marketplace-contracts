# RevenueDistributor
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/95a2b524a76f219f6ef11d45ce10720548eae569/src/RevenueDistributor.sol)

**Inherits:**
[IRevenueDistributor](/src/interfaces/IRevenueDistributor.sol/interface.IRevenueDistributor.md), ReentrancyGuard, AccessControl, IERC2981


## State Variables
### platformTreasury

```solidity
address public platformTreasury;
```


### platformFeeBasisPoints

```solidity
uint256 public platformFeeBasisPoints;
```


### defaultRoyaltyBasisPoints

```solidity
uint256 public defaultRoyaltyBasisPoints;
```


### ipAssetContract

```solidity
address public ipAssetContract;
```


### _ipSplits

```solidity
mapping(uint256 => Split) private _ipSplits;
```


### _balances

```solidity
mapping(address => uint256) private _balances;
```


### assetRoyaltyBasisPoints

```solidity
mapping(uint256 => uint256) public assetRoyaltyBasisPoints;
```


### CONFIGURATOR_ROLE
Role for configuring revenue splits


```solidity
bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
```


### BASIS_POINTS
Basis points denominator (100% = 10000 bp)


```solidity
uint256 public constant BASIS_POINTS = 10_000;
```


## Functions
### constructor


```solidity
constructor(
    address _treasury,
    uint256 _platformFeeBasisPoints,
    uint256 _defaultRoyaltyBasisPoints,
    address _ipAssetContract
);
```

### configureSplit


```solidity
function configureSplit(uint256 ipAssetId, address[] memory recipients, uint256[] memory shares)
    external
    onlyRole(CONFIGURATOR_ROLE);
```

### distributePayment


```solidity
function distributePayment(uint256 ipAssetId, uint256 amount, address seller) external payable nonReentrant;
```

### withdraw


```solidity
function withdraw() external nonReentrant;
```

### getBalance


```solidity
function getBalance(address recipient) external view returns (uint256 balance);
```

### royaltyInfo


```solidity
function royaltyInfo(uint256 tokenId, uint256 salePrice)
    external
    view
    override
    returns (address receiver, uint256 royaltyAmount);
```

### setDefaultRoyalty


```solidity
function setDefaultRoyalty(uint256 basisPoints) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setAssetRoyalty


```solidity
function setAssetRoyalty(uint256 ipAssetId, uint256 basisPoints) external onlyRole(CONFIGURATOR_ROLE);
```

### getAssetRoyalty


```solidity
function getAssetRoyalty(uint256 ipAssetId) public view returns (uint256);
```

### grantConfiguratorRole


```solidity
function grantConfiguratorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### ipSplits


```solidity
function ipSplits(uint256 ipAssetId) external view returns (address[] memory recipients, uint256[] memory shares);
```

### isSplitConfigured


```solidity
function isSplitConfigured(uint256 ipAssetId) external view returns (bool configured);
```

### _isRecipientInSplit


```solidity
function _isRecipientInSplit(address addr, address[] memory recipients) internal pure returns (bool);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override(AccessControl, IERC165) returns (bool);
```

