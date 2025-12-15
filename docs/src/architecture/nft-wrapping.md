# NFT Wrapping

IPAsset supports wrapping external NFTs into the licensing system using a custodial approach.

## How It Works

When an NFT is wrapped:
1. The NFT transfers to the IPAsset contract (custody)
2. IPAsset mints a new token representing the wrapped NFT
3. The IPAsset token grants all licensing rights
4. The owner controls everything through the IPAsset token

## Why Custodial?

**Prevents ownership desync.** If Alice wraps her NFT and then sells the original NFT separately, two people would claim ownership. Custodial wrapping locks the NFT, ensuring the IPAsset owner has exclusive control.

**Enables clean licensing.** Only the IPAsset owner can create licenses. No risk of unauthorized licensing after selling the underlying NFT.

**Atomic transfers.** Selling the IPAsset transfers all rights in one transaction. No coordination needed.

## Key Rules

- Only NFT owner can wrap
- One NFT can only be wrapped once
- Cannot unwrap with active licenses
- Cannot unwrap with active disputes
- Unwrapping burns the IPAsset and returns the original NFT

## Functions

### wrapNFT()
Wraps an external ERC-721 NFT into an IPAsset.

```solidity
function wrapNFT(
    address nftContract,
    uint256 nftTokenId,
    string memory metadataURI
) external returns (uint256 ipTokenId)
```

**Requirements:**
- Caller must own the NFT
- NFT not already wrapped
- Caller must approve IPAsset contract

### unwrapNFT()
Burns the IPAsset and returns the original NFT.

```solidity
function unwrapNFT(uint256 tokenId) external
```

**Requirements:**
- Caller must own the IPAsset
- No active licenses
- No active disputes

### isWrapped()
Check if an IPAsset wraps an external NFT.

```solidity
function isWrapped(uint256 tokenId) external view returns (bool)
```

### getWrappedNFT()
Get details of the wrapped NFT.

```solidity
function getWrappedNFT(uint256 tokenId)
    external view
    returns (address nftContract, uint256 nftTokenId)
```

Returns zero address if not wrapped.

## Trade-offs

**Advantages:**
- No ownership conflicts
- Single source of truth
- Atomic transfers
- Clear legal ownership

**Disadvantages:**
- Contract holds valuable NFTs (custody risk)
- NFT cannot be used elsewhere while wrapped
- Must unwrap to exit (burns IPAsset)

## Security

The IPAsset contract holds all wrapped NFTs. Security measures:
- Thorough audits required
- UUPS upgrade process with admin controls
- Reentrancy protection on wrap/unwrap
- Owner validation on all operations

## Use Cases

**Existing NFT collections:** Wrap Bored Apes, CryptoPunks, or any ERC-721 NFT to license them through Softlaw Marketplace.

**IP migration:** Move existing IP-backed NFTs into the licensing system without creating new tokens.

**Exit strategy:** Unwrap to retrieve the original NFT and exit the licensing system.
