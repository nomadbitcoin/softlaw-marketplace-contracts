# IRevenueDistributor
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/deaf418b415477f4b81161589e5d319de1e2522a/src/interfaces/IRevenueDistributor.sol)

Interface for simple revenue distribution to configured recipients

*Non-upgradeable contract implementing EIP-2981 royalty standard*

*Pure distribution logic - payment timing and penalties handled by calling contracts (e.g., Marketplace)*


## Functions
### configureSplit

Configures revenue split for an IP asset

*Only callable by IP asset owner or CONFIGURATOR_ROLE*


```solidity
function configureSplit(uint256 ipAssetId, address[] memory recipients, uint256[] memory shares) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset ID|
|`recipients`|`address[]`|Array of recipient addresses|
|`shares`|`uint256[]`|Array of share amounts in basis points (must sum to 10000)|


### distributePayment

Distributes a payment according to configured splits

*Deducts platform fee then splits remainder among recipients*


```solidity
function distributePayment(uint256 ipAssetId, uint256 amount) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset ID|
|`amount`|`uint256`|Payment amount to distribute|


### withdraw

Withdraws accumulated funds

*All recipients (including platform treasury) use this function to withdraw*


```solidity
function withdraw() external;
```

### getBalance

Gets the principal balance for a recipient


```solidity
function getBalance(address recipient) external view returns (uint256 balance);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Address to query|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`balance`|`uint256`|Principal amount available for withdrawal|


### setDefaultRoyalty

Sets the default royalty rate

*Only callable by admin*


```solidity
function setDefaultRoyalty(uint256 basisPoints) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`basisPoints`|`uint256`|Royalty rate in basis points|


### grantConfiguratorRole

Grants CONFIGURATOR_ROLE to the IPAsset contract

*Only callable by admin. Should be called after IPAsset deployment.*


```solidity
function grantConfiguratorRole(address ipAssetContract) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetContract`|`address`|Address of the IPAsset contract|


### ipSplits

Gets the configured split for an IP asset


```solidity
function ipSplits(uint256 ipAssetId) external view returns (address[] memory recipients, uint256[] memory shares);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`recipients`|`address[]`|Array of recipient addresses|
|`shares`|`uint256[]`|Array of share amounts|


### isSplitConfigured

Checks if a split is configured for an IP asset


```solidity
function isSplitConfigured(uint256 ipAssetId) external view returns (bool configured);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`configured`|`bool`|True if split exists, false otherwise|


## Events
### PaymentDistributed
Emitted when a payment is distributed


```solidity
event PaymentDistributed(uint256 indexed ipAssetId, uint256 amount, uint256 platformFee);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset the payment is for|
|`amount`|`uint256`|Total payment amount|
|`platformFee`|`uint256`|Fee taken by platform|

### SplitConfigured
Emitted when a revenue split is configured


```solidity
event SplitConfigured(uint256 indexed ipAssetId, address[] recipients, uint256[] shares);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`ipAssetId`|`uint256`|The IP asset ID|
|`recipients`|`address[]`|Array of recipient addresses|
|`shares`|`uint256[]`|Array of share amounts|

### Withdrawal
Emitted when a recipient withdraws funds


```solidity
event Withdrawal(address indexed recipient, uint256 principal);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`recipient`|`address`|Address withdrawing|
|`principal`|`uint256`|Principal amount withdrawn|

### RoyaltyUpdated
Emitted when default royalty rate is updated


```solidity
event RoyaltyUpdated(uint256 newRoyaltyBasisPoints);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRoyaltyBasisPoints`|`uint256`|New royalty rate in basis points|

## Errors
### ArrayLengthMismatch
Thrown when array lengths don't match


```solidity
error ArrayLengthMismatch();
```

### NoRecipientsProvided
Thrown when no recipients are provided


```solidity
error NoRecipientsProvided();
```

### InvalidRecipient
Thrown when a recipient address is zero


```solidity
error InvalidRecipient();
```

### InvalidSharesSum
Thrown when shares don't sum to 10000 basis points


```solidity
error InvalidSharesSum();
```

### IncorrectPaymentAmount
Thrown when msg.value doesn't match amount parameter


```solidity
error IncorrectPaymentAmount();
```

### InvalidIPAsset
Thrown when IP asset does not exist


```solidity
error InvalidIPAsset();
```

### NoBalanceToWithdraw
Thrown when attempting to withdraw with zero balance


```solidity
error NoBalanceToWithdraw();
```

### TransferFailed
Thrown when ETH transfer fails during withdrawal


```solidity
error TransferFailed();
```

### InvalidTreasuryAddress
Thrown when treasury address is zero


```solidity
error InvalidTreasuryAddress();
```

### InvalidPlatformFee
Thrown when platform fee exceeds 100%


```solidity
error InvalidPlatformFee();
```

### InvalidRoyalty
Thrown when royalty rate exceeds 100%


```solidity
error InvalidRoyalty();
```

### InvalidIPAssetAddress
Thrown when IPAsset contract address is zero


```solidity
error InvalidIPAssetAddress();
```

### InvalidBasisPoints
Thrown when basis points exceeds 10000 (100%)


```solidity
error InvalidBasisPoints();
```

## Structs
### Split
*Revenue split configuration for an IP asset*


```solidity
struct Split {
    address[] recipients;
    uint256[] shares;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`recipients`|`address[]`|Array of addresses to receive revenue shares|
|`shares`|`uint256[]`|Array of share amounts in basis points (must sum to 10000)|

