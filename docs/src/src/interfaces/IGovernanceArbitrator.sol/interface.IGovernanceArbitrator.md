# IGovernanceArbitrator
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/95a2b524a76f219f6ef11d45ce10720548eae569/src/interfaces/IGovernanceArbitrator.sol)

Interface for third-party dispute arbitration (no governance)

*Manages license disputes with 30-day resolution deadline via designated arbitrators*


## Functions
### initialize

Initializes the GovernanceArbitrator contract (proxy pattern)

*Sets up admin roles and contract references*


```solidity
function initialize(address admin, address licenseToken, address ipAsset, address revenueDistributor) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`admin`|`address`|Address to receive admin role|
|`licenseToken`|`address`|Address of LicenseToken contract|
|`ipAsset`|`address`|Address of IPAsset contract|
|`revenueDistributor`|`address`|Address of RevenueDistributor contract|


### submitDispute

Submits a new dispute for a license

*Can be submitted by any party (licensee, IP owner, third party)*


```solidity
function submitDispute(uint256 licenseId, string memory reason, string memory proofURI)
    external
    returns (uint256 disputeId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license being disputed|
|`reason`|`string`|Human-readable dispute reason|
|`proofURI`|`string`|URI pointing to evidence/documentation|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|Unique identifier for the dispute|


### resolveDispute

Resolves a dispute

*Only callable by ARBITRATOR_ROLE*


```solidity
function resolveDispute(uint256 disputeId, bool approved, string memory resolutionReason) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The dispute to resolve|
|`approved`|`bool`|Whether to approve (true) or reject (false) the dispute|
|`resolutionReason`|`string`|Explanation of the resolution|


### executeRevocation

Executes license revocation for an approved dispute

*Calls LicenseToken.revokeLicense() and updates dispute status*


```solidity
function executeRevocation(uint256 disputeId) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The approved dispute to execute|


### getDispute

Gets full dispute information


```solidity
function getDispute(uint256 disputeId) external view returns (Dispute memory dispute);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The dispute ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`dispute`|`Dispute`|The complete dispute struct|


### getDisputesForLicense

Gets all dispute IDs for a specific license


```solidity
function getDisputesForLicense(uint256 licenseId) external view returns (uint256[] memory disputeIds);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`disputeIds`|`uint256[]`|Array of dispute IDs|


### isDisputeOverdue

Checks if a dispute is overdue (past 30-day deadline)


```solidity
function isDisputeOverdue(uint256 disputeId) external view returns (bool overdue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The dispute ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`overdue`|`bool`|Whether the dispute is overdue|


### getTimeRemaining

Gets time remaining for dispute resolution


```solidity
function getTimeRemaining(uint256 disputeId) external view returns (uint256 timeRemaining);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The dispute ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`timeRemaining`|`uint256`|Seconds remaining (0 if overdue)|


### getDisputeCount

Gets the total number of disputes submitted


```solidity
function getDisputeCount() external view returns (uint256 count);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`count`|`uint256`|Total dispute count|


### pause

Pauses dispute submissions

*Only callable by DEFAULT_ADMIN_ROLE*


```solidity
function pause() external;
```

### unpause

Unpauses dispute submissions

*Only callable by DEFAULT_ADMIN_ROLE*


```solidity
function unpause() external;
```

## Events
### DisputeSubmitted
Emitted when a new dispute is submitted


```solidity
event DisputeSubmitted(uint256 indexed disputeId, uint256 indexed licenseId, address indexed submitter, string reason);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|Unique dispute identifier|
|`licenseId`|`uint256`|The license being disputed|
|`submitter`|`address`|Address submitting the dispute|
|`reason`|`string`|Dispute reason|

### DisputeResolved
Emitted when a dispute is resolved


```solidity
event DisputeResolved(uint256 indexed disputeId, bool approved, address indexed resolver, string reason);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`disputeId`|`uint256`|The dispute that was resolved|
|`approved`|`bool`|Whether dispute was approved (true) or rejected (false)|
|`resolver`|`address`|Address that resolved the dispute|
|`reason`|`string`|Resolution reasoning|

### LicenseRevoked
Emitted when a license is revoked due to dispute


```solidity
event LicenseRevoked(uint256 indexed licenseId, uint256 indexed disputeId);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license that was revoked|
|`disputeId`|`uint256`|The dispute that caused revocation|

## Errors
### EmptyReason
Thrown when dispute reason is empty (BR-005.3)


```solidity
error EmptyReason();
```

### LicenseNotActive
Thrown when attempting to dispute an inactive license (BR-005.2)


```solidity
error LicenseNotActive();
```

### DisputeAlreadyResolved
Thrown when attempting to resolve an already resolved dispute


```solidity
error DisputeAlreadyResolved();
```

### DisputeResolutionOverdue
Thrown when attempting to resolve a dispute after 30-day deadline (BR-005.8)


```solidity
error DisputeResolutionOverdue();
```

### DisputeNotApproved
Thrown when attempting to execute a dispute that is not approved


```solidity
error DisputeNotApproved();
```

### NotArbitrator
Thrown when caller does not have ARBITRATOR_ROLE


```solidity
error NotArbitrator();
```

## Structs
### Dispute
*Complete dispute information*


```solidity
struct Dispute {
    uint256 licenseId;
    address submitter;
    address ipOwner;
    string reason;
    string proofURI;
    DisputeStatus status;
    uint256 submittedAt;
    uint256 resolvedAt;
    address resolver;
    string resolutionReason;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`licenseId`|`uint256`|The license being disputed|
|`submitter`|`address`|Address that submitted the dispute (BR-005.1: any party)|
|`ipOwner`|`address`|IP asset owner (cached from license data)|
|`reason`|`string`|Human-readable dispute reason (BR-005.3: required)|
|`proofURI`|`string`|Optional URI to supporting evidence (BR-005.1: optional)|
|`status`|`DisputeStatus`|Current dispute status|
|`submittedAt`|`uint256`|Timestamp when dispute was submitted|
|`resolvedAt`|`uint256`|Timestamp when dispute was resolved (0 if pending)|
|`resolver`|`address`|Address of arbitrator who resolved the dispute|
|`resolutionReason`|`string`|Human-readable resolution explanation|

## Enums
### DisputeStatus
*Possible states of a dispute*


```solidity
enum DisputeStatus {
    Pending,
    Approved,
    Rejected,
    Executed
}
```

