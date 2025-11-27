# IMarketplace
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/deaf418b415477f4b81161589e5d319de1e2522a/src/interfaces/IMarketplace.sol)

Interface for NFT marketplace with listings and offers

*Supports both ERC-721 and ERC-1155 tokens with platform fees and royalties*


## Functions
### initialize

Initializes the Marketplace contract (proxy pattern)

*Sets up admin roles. Platform fees are managed by RevenueDistributor.*


```solidity
function initialize(address admin, address revenueDistributor) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address to receive admin role|
|`revenueDistributor`|`address`|Address of RevenueDistributor contract|


### createListing

Creates a new NFT listing

*Seller must approve marketplace contract before listing*


```solidity
function createListing(address nftContract, uint256 tokenId, uint256 price, bool isERC721)
    external
    returns (bytes32 listingId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftContract`|`address`|Address of NFT contract|
|`tokenId`|`uint256`|Token ID to list|
|`price`|`uint256`|Listing price in wei|
|`isERC721`|`bool`|Whether the NFT is ERC-721 (true) or ERC-1155 (false)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`listingId`|`bytes32`|Unique identifier for the listing|


### cancelListing

Cancels an active listing

*Only seller can cancel their own listing*


```solidity
function cancelListing(bytes32 listingId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingId`|`bytes32`|The listing to cancel|


### buyListing

Buys an NFT from a listing

*Transfers NFT, distributes payment with fees/royalties*


```solidity
function buyListing(bytes32 listingId) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingId`|`bytes32`|The listing to purchase|


### createOffer

Creates an offer for an NFT

*Offer price is held in escrow*


```solidity
function createOffer(address nftContract, uint256 tokenId, uint256 expiryTime)
    external
    payable
    returns (bytes32 offerId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`nftContract`|`address`|Address of NFT contract|
|`tokenId`|`uint256`|Token ID to make offer for|
|`expiryTime`|`uint256`|Unix timestamp when offer expires|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|Unique identifier for the offer|


### acceptOffer

Accepts an offer for an NFT

*Only NFT owner can accept. Transfers NFT and distributes payment.*


```solidity
function acceptOffer(bytes32 offerId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|The offer to accept|


### cancelOffer

Cancels an offer and refunds escrowed funds

*Only offer creator can cancel*


```solidity
function cancelOffer(bytes32 offerId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|The offer to cancel|


### pause

Pauses all marketplace operations

*Only callable by PAUSER_ROLE*


```solidity
function pause() external;
```

### unpause

Unpauses all marketplace operations

*Only callable by PAUSER_ROLE*


```solidity
function unpause() external;
```

### setPenaltyRate

Sets the penalty rate for late recurring payments

*Only callable by admin. Penalty is calculated pro-rata per second.*


```solidity
function setPenaltyRate(uint256 basisPoints) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`basisPoints`|`uint256`|Penalty rate in basis points per month (e.g., 500 = 5% per month)|


### getMissedPayments

Calculates the number of missed payments for a recurring license

*Returns 0 for ONE_TIME licenses*


```solidity
function getMissedPayments(address licenseContract, uint256 licenseId) external view returns (uint256 missedPayments);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseContract`|`address`|Address of the license token contract|
|`licenseId`|`uint256`|The license ID to check|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`missedPayments`|`uint256`|Number of missed payment periods|


### makeRecurringPayment

Makes a recurring payment for a subscription license

*Calculates penalty for late payments, auto-revokes after 3 missed payments*


```solidity
function makeRecurringPayment(address licenseContract, uint256 licenseId) external payable;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseContract`|`address`|Address of the license token contract|
|`licenseId`|`uint256`|The license ID to pay for|


### getRecurringPaymentAmount

Gets the base amount for a recurring payment


```solidity
function getRecurringPaymentAmount(uint256 licenseId) external view returns (uint256 baseAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`baseAmount`|`uint256`|The base payment amount (without penalty)|


### calculatePenalty

Calculates the current penalty for late payment

*Returns 0 if payment is not overdue or for ONE_TIME licenses*


```solidity
function calculatePenalty(address licenseContract, uint256 licenseId) external view returns (uint256 penalty);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseContract`|`address`|Address of the license token contract|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`penalty`|`uint256`|Penalty amount in wei|


### getTotalPaymentDue

Gets the total amount due for next recurring payment (base + penalty)

*Useful for frontends to know exact amount before creating transaction*


```solidity
function getTotalPaymentDue(address licenseContract, uint256 licenseId)
    external
    view
    returns (uint256 baseAmount, uint256 penalty, uint256 total);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseContract`|`address`|Address of the license token contract|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`baseAmount`|`uint256`|The base payment amount|
|`penalty`|`uint256`|The penalty amount if overdue|
|`total`|`uint256`|The total amount due (baseAmount + penalty)|


## Events
### ListingCreated
Emitted when a new listing is created


```solidity
event ListingCreated(
    bytes32 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingId`|`bytes32`|Unique identifier for the listing|
|`seller`|`address`|Address of the seller|
|`nftContract`|`address`|NFT contract address|
|`tokenId`|`uint256`|Token ID being listed|
|`price`|`uint256`|Listing price|

### ListingCancelled
Emitted when a listing is cancelled


```solidity
event ListingCancelled(bytes32 indexed listingId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`listingId`|`bytes32`|The listing that was cancelled|

### OfferCreated
Emitted when an offer is created


```solidity
event OfferCreated(bytes32 indexed offerId, address indexed buyer, address nftContract, uint256 tokenId, uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|Unique identifier for the offer|
|`buyer`|`address`|Address making the offer|
|`nftContract`|`address`|NFT contract address|
|`tokenId`|`uint256`|Token ID for the offer|
|`price`|`uint256`|Offer price|

### OfferAccepted
Emitted when an offer is accepted


```solidity
event OfferAccepted(bytes32 indexed offerId, address indexed seller);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|The offer that was accepted|
|`seller`|`address`|Address of the seller who accepted|

### OfferCancelled
Emitted when an offer is cancelled


```solidity
event OfferCancelled(bytes32 indexed offerId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offerId`|`bytes32`|The offer that was cancelled|

### Sale
Emitted when a sale is completed


```solidity
event Sale(bytes32 indexed saleId, address indexed buyer, address indexed seller, uint256 price);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`saleId`|`bytes32`|Unique sale identifier|
|`buyer`|`address`|Address of the buyer|
|`seller`|`address`|Address of the seller|
|`price`|`uint256`|Total sale price|

### RecurringPaymentMade
Emitted when a recurring payment is made


```solidity
event RecurringPaymentMade(
    uint256 indexed licenseId, address indexed payer, uint256 baseAmount, uint256 penalty, uint256 timestamp
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID for the recurring payment|
|`payer`|`address`|Address making the payment|
|`baseAmount`|`uint256`|Base payment amount (without penalty)|
|`penalty`|`uint256`|Penalty amount for late payment|
|`timestamp`|`uint256`|Time of payment|

### PenaltyRateUpdated
Emitted when penalty rate is updated


```solidity
event PenaltyRateUpdated(uint256 newRate);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRate`|`uint256`|New penalty rate in basis points per day|

## Errors
### InvalidPrice
Thrown when price is zero or invalid


```solidity
error InvalidPrice();
```

### NotTokenOwner
Thrown when caller is not the token owner


```solidity
error NotTokenOwner();
```

### NotSeller
Thrown when caller is not the seller


```solidity
error NotSeller();
```

### ListingNotActive
Thrown when listing is not active


```solidity
error ListingNotActive();
```

### InsufficientPayment
Thrown when payment amount is insufficient


```solidity
error InsufficientPayment();
```

### NotOfferBuyer
Thrown when caller is not the offer buyer


```solidity
error NotOfferBuyer();
```

### OfferNotActive
Thrown when offer is not active


```solidity
error OfferNotActive();
```

### OfferExpired
Thrown when offer has expired


```solidity
error OfferExpired();
```

### NotRecurringLicense
Thrown when operation requires recurring license but license is one-time


```solidity
error NotRecurringLicense();
```

### LicenseNotActive
Thrown when license is not active


```solidity
error LicenseNotActive();
```

### InsufficientMissedPaymentsForRevocation
Thrown when attempting revocation without sufficient missed payments


```solidity
error InsufficientMissedPaymentsForRevocation();
```

### LicenseRevokedForMissedPayments
Thrown when license has been revoked for missed payments


```solidity
error LicenseRevokedForMissedPayments();
```

### InvalidPenaltyRate
Thrown when penalty rate exceeds maximum allowed


```solidity
error InvalidPenaltyRate();
```

### TransferFailed
Thrown when native token transfer fails


```solidity
error TransferFailed();
```

## Structs
### Listing
*Marketplace listing configuration*


```solidity
struct Listing {
    address seller;
    address nftContract;
    uint256 tokenId;
    uint256 price;
    bool isActive;
    bool isERC721;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`seller`|`address`|Address of the seller|
|`nftContract`|`address`|Address of the NFT contract (ERC-721 or ERC-1155)|
|`tokenId`|`uint256`|Token ID being listed|
|`price`|`uint256`|Listing price in wei|
|`isActive`|`bool`|Whether the listing is currently active|
|`isERC721`|`bool`|Whether the NFT is ERC-721 (true) or ERC-1155 (false)|

### Offer
*Offer configuration for NFT purchase*


```solidity
struct Offer {
    address buyer;
    address nftContract;
    uint256 tokenId;
    uint256 price;
    bool isActive;
    uint256 expiryTime;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`buyer`|`address`|Address making the offer|
|`nftContract`|`address`|Address of the NFT contract|
|`tokenId`|`uint256`|Token ID for the offer|
|`price`|`uint256`|Offer price in wei (held in escrow)|
|`isActive`|`bool`|Whether the offer is currently active|
|`expiryTime`|`uint256`|Unix timestamp when offer expires|

### RecurringPayment
*Recurring payment tracking for subscription licenses*


```solidity
struct RecurringPayment {
    uint256 lastPaymentTime;
    address currentOwner;
    uint256 baseAmount;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`lastPaymentTime`|`uint256`|Timestamp of the last payment made|
|`currentOwner`|`address`|Current owner of the license (tracks transfers)|
|`baseAmount`|`uint256`|Base payment amount for recurring payments|

