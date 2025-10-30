// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IMarketplace
 * @notice Interface for NFT marketplace with listings and offers
 * @dev Supports both ERC-721 and ERC-1155 tokens with platform fees and royalties
 */
interface IMarketplace {
    // ==================== STRUCTS ====================

    /**
     * @dev Marketplace listing configuration
     * @param seller Address of the seller
     * @param nftContract Address of the NFT contract (ERC-721 or ERC-1155)
     * @param tokenId Token ID being listed
     * @param price Listing price in wei
     * @param isActive Whether the listing is currently active
     * @param isERC721 Whether the NFT is ERC-721 (true) or ERC-1155 (false)
     */
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isActive;
        bool isERC721;
    }

    /**
     * @dev Offer configuration for NFT purchase
     * @param buyer Address making the offer
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID for the offer
     * @param price Offer price in wei (held in escrow)
     * @param isActive Whether the offer is currently active
     * @param expiryTime Unix timestamp when offer expires
     */
    struct Offer {
        address buyer;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isActive;
        uint256 expiryTime;
    }

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a new listing is created
     * @param listingId Unique identifier for the listing
     * @param seller Address of the seller
     * @param nftContract NFT contract address
     * @param tokenId Token ID being listed
     * @param price Listing price
     */
    event ListingCreated(
        bytes32 indexed listingId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );

    /**
     * @notice Emitted when a listing is cancelled
     * @param listingId The listing that was cancelled
     */
    event ListingCancelled(bytes32 indexed listingId);

    /**
     * @notice Emitted when an offer is created
     * @param offerId Unique identifier for the offer
     * @param buyer Address making the offer
     * @param nftContract NFT contract address
     * @param tokenId Token ID for the offer
     * @param price Offer price
     */
    event OfferCreated(
        bytes32 indexed offerId,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );

    /**
     * @notice Emitted when an offer is accepted
     * @param offerId The offer that was accepted
     * @param seller Address of the seller who accepted
     */
    event OfferAccepted(bytes32 indexed offerId, address indexed seller);

    /**
     * @notice Emitted when an offer is cancelled
     * @param offerId The offer that was cancelled
     */
    event OfferCancelled(bytes32 indexed offerId);

    /**
     * @notice Emitted when a sale is completed
     * @param saleId Unique sale identifier
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @param price Total sale price
     * @param platformFee Fee paid to platform
     * @param royalty Royalty paid to creators
     */
    event Sale(
        bytes32 indexed saleId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        uint256 platformFee,
        uint256 royalty
    );

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the Marketplace contract (proxy pattern)
     * @dev Sets up admin roles and fee configuration
     * @param admin Address to receive admin role
     * @param revenueDistributor Address of RevenueDistributor contract
     * @param platformFeeBasisPoints Platform fee in basis points (e.g., 250 = 2.5%)
     * @param treasury Address to receive platform fees
     */
    function initialize(
        address admin,
        address revenueDistributor,
        uint256 platformFeeBasisPoints,
        address treasury
    ) external;

    /**
     * @notice Creates a new NFT listing
     * @dev Seller must approve marketplace contract before listing
     * @param nftContract Address of NFT contract
     * @param tokenId Token ID to list
     * @param price Listing price in wei
     * @param isERC721 Whether the NFT is ERC-721 (true) or ERC-1155 (false)
     * @return listingId Unique identifier for the listing
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isERC721
    ) external returns (bytes32 listingId);

    /**
     * @notice Cancels an active listing
     * @dev Only seller can cancel their own listing
     * @param listingId The listing to cancel
     */
    function cancelListing(bytes32 listingId) external;

    /**
     * @notice Buys an NFT from a listing
     * @dev Transfers NFT, distributes payment with fees/royalties
     * @param listingId The listing to purchase
     */
    function buyListing(bytes32 listingId) external payable;

    /**
     * @notice Creates an offer for an NFT
     * @dev Offer price is held in escrow
     * @param nftContract Address of NFT contract
     * @param tokenId Token ID to make offer for
     * @param expiryTime Unix timestamp when offer expires
     * @return offerId Unique identifier for the offer
     */
    function createOffer(
        address nftContract,
        uint256 tokenId,
        uint256 expiryTime
    ) external payable returns (bytes32 offerId);

    /**
     * @notice Accepts an offer for an NFT
     * @dev Only NFT owner can accept. Transfers NFT and distributes payment.
     * @param offerId The offer to accept
     */
    function acceptOffer(bytes32 offerId) external;

    /**
     * @notice Cancels an offer and refunds escrowed funds
     * @dev Only offer creator can cancel
     * @param offerId The offer to cancel
     */
    function cancelOffer(bytes32 offerId) external;

    /**
     * @notice Pauses all marketplace operations
     * @dev Only callable by PAUSER_ROLE
     */
    function pause() external;

    /**
     * @notice Unpauses all marketplace operations
     * @dev Only callable by PAUSER_ROLE
     */
    function unpause() external;
}
