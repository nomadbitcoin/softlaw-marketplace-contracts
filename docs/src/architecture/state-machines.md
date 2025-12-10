# State Machines

Lifecycle and state transitions for key entities in the system.

## License Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Active: mintLicense()

    Active --> Expired: expiryTime passed<br/>markExpired()
    Active --> Revoked: Dispute approved<br/>revokeLicense()
    Active --> Revoked: >= maxMissedPayments<br/>revokeForMissedPayments()

    Expired --> [*]
    Revoked --> [*]

    note right of Active
        License is usable
        Can be transferred
        Private metadata accessible
    end note

    note right of Expired
        Cannot be transferred
        Decrements activeLicenseCount
        Perpetual licenses (expiryTime=0) never expire
    end note

    note right of Revoked
        Cannot be transferred
        Decrements activeLicenseCount
        Permanent state
    end note
```

## Marketplace Listing

```mermaid
stateDiagram-v2
    [*] --> Active: createListing()

    Active --> Cancelled: cancelListing()<br/>(by seller)
    Active --> Sold: buyListing()<br/>(by buyer)

    Cancelled --> [*]
    Sold --> [*]

    note right of Active
        Visible to buyers
        NFT approved to Marketplace
        Seller can cancel
    end note

    note right of Sold
        NFT transferred to buyer
        Payment distributed
        Listing marked inactive
    end note
```

## Marketplace Offer

```mermaid
stateDiagram-v2
    [*] --> Active: createOffer()<br/>ETH escrowed

    Active --> Cancelled: cancelOffer()<br/>(by buyer)<br/>ETH refunded
    Active --> Accepted: acceptOffer()<br/>(by seller)
    Active --> Expired: block.timestamp > expiryTime

    Cancelled --> [*]
    Accepted --> [*]
    Expired --> [*]

    note right of Active
        ETH held in escrow
        Can be accepted by NFT owner
        Can be cancelled by buyer
    end note

    note right of Accepted
        NFT transferred to buyer
        Payment distributed
        Offer marked inactive
    end note

    note right of Expired
        After expiryTime
        Buyer must call cancelOffer()
        to reclaim funds
    end note
```

## Dispute Status

```mermaid
stateDiagram-v2
    [*] --> Pending: submitDispute()

    Pending --> Approved: resolveDispute(true)
    Pending --> Rejected: resolveDispute(false)

    Approved --> Executed: executeRevocation()

    Rejected --> [*]
    Executed --> [*]

    note right of Pending
        IP asset dispute flag = true
        Cannot burn IP asset
        30-day resolution deadline
    end note

    note right of Approved
        Dispute validated
        Awaiting execution
        Can now revoke license
    end note

    note right of Executed
        License revoked
        IP asset dispute flag = false
        Can now burn IP asset (if no other disputes)
    end note

    note right of Rejected
        Dispute dismissed
        IP asset dispute flag = false
        No license revocation
    end note
```

## IP Asset Lifecycle

```mermaid
stateDiagram-v2
    [*] --> NoLicenses: mintIP()

    NoLicenses --> HasLicenses: mintLicense()<br/>activeLicenseCount > 0

    HasLicenses --> NoLicenses: All licenses<br/>expired/revoked

    NoLicenses --> Burned: burn()<br/>(no dispute)
    HasLicenses --> Burned: burn()<br/>(if activeLicenseCount = 0 && no dispute)

    NoLicenses --> Disputed: submitDispute()<br/>on any license
    HasLicenses --> Disputed: submitDispute()<br/>on any license

    Disputed --> NoLicenses: Dispute rejected<br/>& no licenses
    Disputed --> HasLicenses: Dispute rejected<br/>& has licenses

    Burned --> [*]

    note right of NoLicenses
        Can burn (if no dispute)
        Can create licenses
        Can update metadata
    end note

    note right of HasLicenses
        Cannot burn
        Can create more licenses
        Can update metadata
    end note

    note right of Disputed
        Cannot burn
        Awaiting dispute resolution
        Can still create licenses
    end note
```

## Recurring Payment Status

```mermaid
stateDiagram-v2
    [*] --> Current: Initial payment

    Current --> Current: makeRecurringPayment()<br/>on time
    Current --> GracePeriod: Payment overdue<br/>(within 3 days)

    GracePeriod --> Current: makeRecurringPayment()<br/>no penalty (within grace)
    GracePeriod --> LateOnce: Grace period expires<br/>(> 3 days overdue)

    LateOnce --> Current: makeRecurringPayment()<br/>with penalty
    LateOnce --> LateTwice: 2nd missed payment

    LateTwice --> Current: makeRecurringPayment()<br/>with penalty
    LateTwice --> LateThrice: 3rd missed payment

    LateThrice --> AutoRevoked: >= maxMissedPayments<br/>auto-revoke triggered

    AutoRevoked --> [*]

    note right of Current
        No missed payments
        No penalty applied
    end note

    note right of GracePeriod
        Payment overdue but < 3 days
        No penalty yet (grace period)
        Payment can be made without penalty
    end note

    note right of LateOnce
        1+ missed payment(s)
        Beyond grace period
        Penalty = penaltyRateBPS * baseAmount * time
    end note

    note right of LateTwice
        2+ missed payments
        Higher penalty accumulation
        Configurable per license
    end note

    note right of LateThrice
        >= maxMissedPayments
        Default: 3 (configurable 1-255)
        Next payment attempt
        triggers auto-revocation
    end note

    note right of AutoRevoked
        License permanently revoked
        Cannot make further payments
    end note
```

### Configurable Payment Parameters

Each license has configurable payment parameters:

**maxMissedPayments** (defaults to 3):
- Range: 1-255
- Determines when auto-revocation occurs
- Can be set per license at mint time
- 0 = uses DEFAULT_MAX_MISSED_PAYMENTS (3)

**penaltyRateBPS** (defaults to 500 = 5%):
- Range: 0-5000 basis points (0-50%)
- Applied per month, calculated pro-rata
- Can be set per license at mint time
- 0 = uses DEFAULT_PENALTY_RATE (500)

**PENALTY_GRACE_PERIOD** (fixed at 3 days):
- Global constant across all licenses
- No penalties accrue during grace period
- After due date + 3 days, penalties start
- Gives licensees time to make payment without penalty

## Access Control States

```mermaid
stateDiagram-v2
    [*] --> NoAccess: License minted

    NoAccess --> HasAccess: grantPrivateAccess()
    HasAccess --> NoAccess: revokePrivateAccess()

    note right of NoAccess
        Can only access public metadata
        License owner always has access
        IP owner always has access
    end note

    note right of HasAccess
        Can access private metadata
        Granted by license owner
        Survives license transfer (resets)
    end note
```
