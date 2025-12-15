# Marketplace
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/780633a2de81ce811954fe06eaece193fa652c84/src/Marketplace.sol)

**Inherits:**
[IMarketplace](/src/interfaces/IMarketplace.sol/interface.IMarketplace.md), Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable


## State Variables
### MAX_PENALTY_RATE

```solidity
uint256 public constant MAX_PENALTY_RATE = 1000;
```


### BASIS_POINTS

```solidity
uint256 public constant BASIS_POINTS = 10_000;
```


### SECONDS_PER_MONTH

```solidity
uint256 public constant SECONDS_PER_MONTH = 2_592_000;
```


### PENALTY_GRACE_PERIOD

```solidity
uint256 public constant PENALTY_GRACE_PERIOD = 3 days;
```


### listings

```solidity
mapping(bytes32 => Listing) public listings;
```


### offers

```solidity
mapping(bytes32 => Offer) public offers;
```


### escrow

```solidity
mapping(bytes32 => uint256) public escrow;
```


### recurring

```solidity
mapping(uint256 => RecurringPayment) public recurring;
```


### _ipAssetSold

```solidity
mapping(uint256 => bool) private _ipAssetSold;
```


### _licenseSold

```solidity
mapping(bytes32 => bool) private _licenseSold;
```


### revenueDistributor

```solidity
address public revenueDistributor;
```


### penaltyBasisPointsPerMonth

```solidity
uint256 public penaltyBasisPointsPerMonth;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address admin, address _revenueDistributor) external initializer;
```

### createListing


```solidity
function createListing(address nftContract, uint256 tokenId, uint256 price, bool isERC721)
    external
    whenNotPaused
    returns (bytes32);
```

### cancelListing


```solidity
function cancelListing(bytes32 listingId) external whenNotPaused;
```

### buyListing


```solidity
function buyListing(bytes32 listingId) external payable whenNotPaused nonReentrant;
```

### createOffer


```solidity
function createOffer(address nftContract, uint256 tokenId, uint256 expiryTime)
    external
    payable
    whenNotPaused
    returns (bytes32);
```

### acceptOffer


```solidity
function acceptOffer(bytes32 offerId) external whenNotPaused nonReentrant;
```

### _transferNFT


```solidity
function _transferNFT(address nftContract, address from, address to, uint256 tokenId, bool isERC721) private;
```

### _distributePayment


```solidity
function _distributePayment(uint256 ipAssetId, uint256 totalAmount, address seller, bool isPrimarySale) internal;
```

### cancelOffer


```solidity
function cancelOffer(bytes32 offerId) external;
```

### pause


```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### unpause


```solidity
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### setPenaltyRate


```solidity
function setPenaltyRate(uint256 basisPoints) external onlyRole(DEFAULT_ADMIN_ROLE);
```

### getMissedPayments


```solidity
function getMissedPayments(address licenseContract, uint256 licenseId) public view returns (uint256);
```

### getRecurringPaymentAmount


```solidity
function getRecurringPaymentAmount(uint256 licenseId) public view returns (uint256);
```

### calculatePenalty


```solidity
function calculatePenalty(address licenseContract, uint256 licenseId) public view returns (uint256);
```

### getTotalPaymentDue


```solidity
function getTotalPaymentDue(address licenseContract, uint256 licenseId)
    public
    view
    returns (uint256 baseAmount, uint256 penalty, uint256 total);
```

### makeRecurringPayment


```solidity
function makeRecurringPayment(address licenseContract, uint256 licenseId) external payable whenNotPaused nonReentrant;
```

### _validateRecurringPayment


```solidity
function _validateRecurringPayment(address licenseContract, uint256 licenseId) internal;
```

### _updatePaymentState


```solidity
function _updatePaymentState(uint256 licenseId) internal;
```

### _missedPayments


```solidity
function _missedPayments(uint256 lastPaid, uint256 interval) internal view returns (uint256);
```

### _isOwner


```solidity
function _isOwner(address nftContract, uint256 tokenId, address owner, bool isERC721) internal view returns (bool);
```

### _refund


```solidity
function _refund(address to, uint256 amount) internal;
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```

