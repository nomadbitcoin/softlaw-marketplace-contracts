# Revenue Flow

How payments are distributed through the system.

## Primary vs Secondary Sales

**The system automatically detects whether a sale is primary or secondary:**

- **Primary Sale**: First sale of an IP asset or license → Platform fee applies
- **Secondary Sale**: Subsequent sales of the same IP asset or license → Royalty fee applies

## Payment Distribution Overview

RevenueDistributor handles payment splitting differently for primary and secondary sales:

```mermaid
graph TB
    PAYMENT[Total Payment<br/>1000 ETH]

    subgraph "Step 1: Platform Fee"
        FEE[Platform Fee<br/>2.5% = 25 ETH]
        NET[Remaining<br/>975 ETH]
    end

    subgraph "Step 2: Revenue Split"
        SPLIT{Split<br/>Configured?}
        OWNER_ONLY[All to<br/>IP Owner<br/>975 ETH]
        SPLIT_MODE[Split by<br/>Shares]
        R1[Owner 70%<br/>682.5 ETH]
        R2[Collab 30%<br/>292.5 ETH]
    end

    subgraph "Balances"
        TREASURY[Treasury: 25 ETH]
        B1[Owner Balance]
        B2[Collab Balance]
    end

    PAYMENT --> FEE
    PAYMENT --> NET
    FEE --> TREASURY

    NET --> SPLIT
    SPLIT -->|No| OWNER_ONLY
    SPLIT -->|Yes| SPLIT_MODE
    SPLIT_MODE --> R1
    SPLIT_MODE --> R2
    OWNER_ONLY --> B1
    R1 --> B1
    R2 --> B2

    B1 -.->|withdraw| W1[Withdraws]
    B2 -.->|withdraw| W2[Withdraws]
    TREASURY -.->|withdraw| W3[Withdraws]

    style FEE fill:#ffcccc
    style NET fill:#ccffcc
    style TREASURY fill:#ffffcc
```

### Distribution Rules

**For Primary Sales** (first sale of an IP asset or license):
1. **Platform fee** is calculated on total amount and deducted first (e.g., 2.5%)
2. **If revenue split configured**, remaining amount split by shares (must sum to 100%)
3. **If no split configured**, all remaining amount goes to IP asset owner

**For Secondary Sales** (subsequent sales):
1. **Royalty fee** is calculated on total amount (default or per-asset custom rate)
2. **Royalty amount** is distributed according to revenue split configuration
3. **Remaining amount** goes to the seller

**General Rules**:
4. **Balances accumulate** until recipient calls withdraw()
5. **Pull-based withdrawals** - recipients control when to withdraw

## Primary Sale Payment Flow

When this is the first sale of an IP asset or license:

```mermaid
sequenceDiagram
    participant Buyer
    participant MP as Marketplace
    participant RD as RevenueDistributor
    participant Treasury
    participant IPOwner as IP Owner (Seller)
    participant Collaborator

    Buyer->>MP: buyListing() + 1000 ETH
    MP->>RD: distributePayment(ipAssetId, 1000, ipOwner) + 1000 ETH

    Note over RD: Marketplace tracks first sale<br/>→ PRIMARY SALE

    Note over RD: Platform fee = 2.5% (25 ETH)
    Note over RD: Net amount = 975 ETH

    RD->>RD: balances[treasury] += 25 ETH

    Note over RD: Split configured:<br/>IP Owner: 70% (700 basis points)<br/>Collaborator: 30% (300 basis points)

    RD->>RD: balances[ipOwner] += 682.5 ETH (70% of 975)
    RD->>RD: balances[collaborator] += 292.5 ETH (30% of 975)

    RD-->>MP: Payment distributed

    Note over Treasury,Collaborator: Later, recipients withdraw

    IPOwner->>RD: withdraw()
    RD->>IPOwner: Transfer 682.5 ETH

    Collaborator->>RD: withdraw()
    RD->>Collaborator: Transfer 292.5 ETH

    Treasury->>RD: withdraw()
    RD->>Treasury: Transfer 25 ETH
```

## Secondary Sale Payment Flow

When this is a subsequent sale of a previously sold IP asset or license:

```mermaid
sequenceDiagram
    participant Buyer
    participant MP as Marketplace
    participant Seller as Licensee (Seller)
    participant RD as RevenueDistributor
    participant IPOwner as IP Owner
    participant Collaborator

    Buyer->>MP: buyListing() + 1000 ETH
    MP->>RD: distributePayment(ipAssetId, 1000, seller) + 1000 ETH

    Note over RD: Marketplace tracks subsequent sale<br/>→ SECONDARY SALE

    Note over RD: Royalty rate = 10% (100 ETH)
    Note over RD: Seller gets = 900 ETH

    RD->>RD: balances[seller] += 900 ETH

    Note over RD: Royalty split by configured shares:<br/>IP Owner: 70%<br/>Collaborator: 30%

    RD->>RD: balances[ipOwner] += 70 ETH (70% of royalty)
    RD->>RD: balances[collaborator] += 30 ETH (30% of royalty)

    RD-->>MP: Payment distributed

    Note over Seller,Collaborator: Later, recipients withdraw

    Seller->>RD: withdraw()
    RD->>Seller: Transfer 900 ETH

    IPOwner->>RD: withdraw()
    RD->>IPOwner: Transfer 70 ETH

    Collaborator->>RD: withdraw()
    RD->>Collaborator: Transfer 30 ETH
```

## Recurring Payment Flow

```mermaid
sequenceDiagram
    participant Licensee
    participant MP as Marketplace
    participant RD as RevenueDistributor
    participant IPOwner as IP Owner

    Note over Licensee,MP: Payment due: 100 ETH base + 5 ETH penalty

    Licensee->>MP: makeRecurringPayment(licenseId) + 105 ETH

    MP->>MP: Calculate missedPayments
    MP->>MP: Update lastPaymentTime

    MP->>RD: distributePayment(ipAssetId, 105) + 105 ETH

    Note over RD: Platform fee = 2.5% (2.625 ETH)
    Note over RD: Net amount = 102.375 ETH

    RD->>RD: balances[treasury] += 2.625 ETH
    RD->>RD: balances[ipOwner] += 102.375 ETH

    RD-->>MP: Payment distributed
    MP-->>Licensee: Payment successful

    Note over Licensee,IPOwner: Penalty increases net payment to IP owner
```

## Revenue Split Configuration

Revenue splits are configured per IP asset in basis points (1 basis point = 0.01%).

```mermaid
graph LR
    subgraph "Example Split Configuration"
        NET[Net Amount<br/>10000 basis points = 100%]

        NET --> A[Creator: 5000 bp<br/>50%]
        NET --> B[Contributor: 3000 bp<br/>30%]
        NET --> C[Investor: 2000 bp<br/>20%]
    end

    style NET fill:#e1f5ff
    style A fill:#ffe1f5
    style B fill:#fff4e1
    style C fill:#e1ffe1
```

### Requirements

- All shares must sum to **exactly 10000 basis points** (100%)
- No recipient address can be zero address
- At least one recipient required
- Split can only be configured by IP owner or `CONFIGURATOR_ROLE`

## Royalty Configuration

Royalty rates can be set globally (default) or per IP asset:

**Default Royalty**:
- Applied to all IP assets unless overridden
- Set by admin via `setDefaultRoyalty(basisPoints)`
- Example: 1000 basis points = 10%

**Per-Asset Royalty**:
- Custom royalty for specific IP assets
- Set by CONFIGURATOR_ROLE via `setAssetRoyalty(ipAssetId, basisPoints)`
- Overrides default royalty
- Example: High-value IP might have 1500 bp (15%), while others use default

**Querying Royalty**:
- Use `getAssetRoyalty(ipAssetId)` to get effective rate (custom or default)
- Returns custom rate if set, otherwise returns default rate

## Withdrawal Pattern

All recipients (platform treasury, IP owners, collaborators) use the same withdrawal mechanism:

```mermaid
stateDiagram-v2
    [*] --> HasBalance: Revenue distributed
    HasBalance --> Withdrawn: withdraw()
    Withdrawn --> [*]

    HasBalance --> HasMoreBalance: Additional revenue
    HasMoreBalance --> Withdrawn: withdraw()

    note right of HasBalance
        Balance accumulates
        from multiple sales
    end note

    note right of Withdrawn
        Balance reset to 0
        ETH transferred
    end note
```

### Benefits

- Gas efficient (no iterating through recipients)
- Recipients control their own withdrawals
- Supports multiple revenue sources accumulating
- No risk of failed transfers blocking other recipients
