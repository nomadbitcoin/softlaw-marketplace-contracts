# GovernanceArbitrator
[Git Source](https://github.com/your-org/softlaw-marketplace-contracts/blob/780633a2de81ce811954fe06eaece193fa652c84/src/GovernanceArbitrator.sol)

**Inherits:**
[IGovernanceArbitrator](/src/interfaces/IGovernanceArbitrator.sol/interface.IGovernanceArbitrator.md), Initializable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable


## State Variables
### ARBITRATOR_ROLE

```solidity
bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
```


### RESOLUTION_DEADLINE

```solidity
uint256 public constant RESOLUTION_DEADLINE = 30 days;
```


### licenseTokenContract

```solidity
address public licenseTokenContract;
```


### ipAssetContract

```solidity
address public ipAssetContract;
```


### revenueDistributorContract

```solidity
address public revenueDistributorContract;
```


### _disputeIdCounter

```solidity
uint256 private _disputeIdCounter;
```


### disputes

```solidity
mapping(uint256 => Dispute) public disputes;
```


### _licenseDisputes

```solidity
mapping(uint256 => uint256[]) private _licenseDisputes;
```


## Functions
### constructor


```solidity
constructor();
```

### initialize


```solidity
function initialize(address admin, address licenseToken, address ipAsset, address revenueDistributor)
    external
    initializer;
```

### submitDispute


```solidity
function submitDispute(uint256 licenseId, string memory reason, string memory proofURI)
    external
    whenNotPaused
    returns (uint256);
```

### resolveDispute


```solidity
function resolveDispute(uint256 disputeId, bool approve, string memory resolutionReason)
    external
    onlyRole(ARBITRATOR_ROLE)
    whenNotPaused;
```

### executeRevocation


```solidity
function executeRevocation(uint256 disputeId) external onlyRole(ARBITRATOR_ROLE) whenNotPaused;
```

### getDispute


```solidity
function getDispute(uint256 disputeId) external view returns (Dispute memory dispute);
```

### getDisputesForLicense


```solidity
function getDisputesForLicense(uint256 licenseId) external view returns (uint256[] memory disputeIds);
```

### isDisputeOverdue


```solidity
function isDisputeOverdue(uint256 disputeId) external view returns (bool overdue);
```

### getTimeRemaining


```solidity
function getTimeRemaining(uint256 disputeId) external view returns (uint256 timeRemaining);
```

### getDisputeCount


```solidity
function getDisputeCount() external view returns (uint256 count);
```

### pause


```solidity
function pause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### unpause


```solidity
function unpause() external onlyRole(DEFAULT_ADMIN_ROLE);
```

### _authorizeUpgrade


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE);
```

