# User Flows

Key user journeys through the Softlaw Marketplace system.

## Creating and Licensing IP

```mermaid
sequenceDiagram
    actor Owner as IP Owner
    participant IP as IPAsset
    participant LT as LicenseToken
    participant RD as RevenueDistributor

    Owner->>IP: mintIP(metadata)
    IP->>IP: Mint ERC-721 token
    IP-->>Owner: tokenId

    Owner->>RD: configureSplit(tokenId, recipients, shares)
    RD->>RD: Store revenue split
    RD-->>Owner: Split configured

    Owner->>IP: mintLicense(ipTokenId, licensee, params)
    IP->>LT: mintLicense(to, ipAssetId, params)
    LT->>LT: Create ERC-1155 license
    LT->>IP: updateActiveLicenseCount(tokenId, +1)
    LT-->>IP: licenseId
    IP-->>Owner: licenseId
```

## Buying a Listed License

```mermaid
sequenceDiagram
    actor Seller
    actor Buyer
    participant MP as Marketplace
    participant LT as LicenseToken
    participant RD as RevenueDistributor

    Seller->>LT: approve(Marketplace, licenseId)
    Seller->>MP: createListing(nftContract, tokenId, price)
    MP->>MP: Store listing
    MP-->>Seller: listingId

    Buyer->>MP: buyListing(listingId) + ETH
    MP->>LT: safeTransferFrom(seller, buyer, licenseId)
    MP->>RD: distributePayment(ipAssetId, amount)
    RD->>RD: Calculate fees & splits
    RD->>RD: Update balances
    MP-->>Buyer: License transferred

    Note over Seller,RD: Seller and IP owner can withdraw later
```

## Making an Offer

```mermaid
sequenceDiagram
    actor Buyer
    actor Seller
    participant MP as Marketplace
    participant LT as LicenseToken
    participant RD as RevenueDistributor

    Buyer->>MP: createOffer(nftContract, tokenId, expiry) + ETH
    MP->>MP: Store offer with escrowed funds
    MP-->>Buyer: offerId

    Note over Seller: Seller decides to accept

    Seller->>LT: approve(Marketplace, tokenId)
    Seller->>MP: acceptOffer(offerId)
    MP->>LT: safeTransferFrom(seller, buyer, tokenId)
    MP->>RD: distributePayment(ipAssetId, amount)
    RD->>RD: Calculate fees & splits
    RD->>RD: Update balances
    MP-->>Seller: Offer accepted

    alt Buyer cancels before acceptance
        Buyer->>MP: cancelOffer(offerId)
        MP->>Buyer: Refund escrowed ETH
    end
```

## Recurring Payments (Subscription Licenses)

```mermaid
sequenceDiagram
    actor Licensee
    participant MP as Marketplace
    participant LT as LicenseToken
    participant RD as RevenueDistributor

    Note over Licensee,MP: License has paymentInterval > 0

    loop Every payment interval
        Licensee->>MP: getTotalPaymentDue(licenseContract, licenseId)
        MP-->>Licensee: baseAmount, penalty, total

        Licensee->>MP: makeRecurringPayment(licenseContract, licenseId) + ETH
        MP->>MP: Calculate missed payments

        alt < 3 missed payments
            MP->>RD: distributePayment(ipAssetId, amount)
            MP-->>Licensee: Payment successful
        else >= 3 missed payments
            MP->>LT: revokeForMissedPayments(licenseId, missedCount)
            LT->>LT: Mark license as revoked
            MP-->>Licensee: License auto-revoked
        end
    end
```

## Dispute Resolution

```mermaid
sequenceDiagram
    actor User
    actor Arbitrator
    participant GA as GovernanceArbitrator
    participant LT as LicenseToken
    participant IP as IPAsset

    User->>GA: submitDispute(licenseId, reason, proofURI)
    GA->>LT: Check license is active
    GA->>IP: setDisputeStatus(tokenId, true)
    GA->>GA: Create dispute record
    GA-->>User: disputeId

    Note over Arbitrator,GA: Within 30 days

    Arbitrator->>GA: resolveDispute(disputeId, approved, reason)
    GA->>GA: Update dispute status
    GA-->>Arbitrator: Dispute resolved

    alt Dispute approved
        Arbitrator->>GA: executeRevocation(disputeId)
        GA->>LT: revokeLicense(licenseId, reason)
        LT->>LT: Mark license revoked
        LT->>IP: updateActiveLicenseCount(tokenId, -1)
        GA->>IP: setDisputeStatus(tokenId, false)
    else Dispute rejected
        GA->>IP: setDisputeStatus(tokenId, false)
    end
```

## Revenue Withdrawal

```mermaid
sequenceDiagram
    actor Recipient
    participant RD as RevenueDistributor

    Recipient->>RD: getBalance(address)
    RD-->>Recipient: balance

    Recipient->>RD: withdraw()
    RD->>RD: Check balance > 0
    RD->>RD: Reset balance to 0
    RD->>Recipient: Transfer ETH
    RD-->>Recipient: Withdrawal successful
```
