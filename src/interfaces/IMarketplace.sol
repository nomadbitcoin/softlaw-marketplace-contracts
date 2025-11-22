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

    /**
     * @dev Recurring payment tracking for subscription licenses
     * @param lastPaymentTime Timestamp of the last payment made
     * @param currentOwner Current owner of the license (tracks transfers)
     * @param baseAmount Base payment amount for recurring payments
     */
    struct RecurringPayment {
        uint256 lastPaymentTime;
        address currentOwner;
        uint256 baseAmount;
    }

    // ==================== CUSTOM ERRORS ====================

    /// @notice Thrown when price is zero or invalid
    error InvalidPrice();

    /// @notice Thrown when caller is not the token owner
    error NotTokenOwner();

    /// @notice Thrown when caller is not the seller
    error NotSeller();

    /// @notice Thrown when listing is not active
    error ListingNotActive();

    /// @notice Thrown when payment amount is insufficient
    error InsufficientPayment();

    /// @notice Thrown when caller is not the offer buyer
    error NotOfferBuyer();

    /// @notice Thrown when offer is not active
    error OfferNotActive();

    /// @notice Thrown when offer has expired
    error OfferExpired();

    /// @notice Thrown when operation requires recurring license but license is one-time
    error NotRecurringLicense();

    /// @notice Thrown when license is not active
    error LicenseNotActive();

    /// @notice Thrown when attempting revocation without sufficient missed payments
    error InsufficientMissedPaymentsForRevocation();

    /// @notice Thrown when license has been revoked for missed payments
    error LicenseRevokedForMissedPayments();

    /// @notice Thrown when penalty rate exceeds maximum allowed
    error InvalidPenaltyRate();

    /// @notice Thrown when native token transfer fails
    error TransferFailed();

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
     */
    event Sale(
        bytes32 indexed saleId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );

    /**
     * @notice Emitted when a recurring payment is made
     * @param licenseId The license ID for the recurring payment
     * @param payer Address making the payment
     * @param baseAmount Base payment amount (without penalty)
     * @param penalty Penalty amount for late payment
     * @param timestamp Time of payment
     */
    event RecurringPaymentMade(
        uint256 indexed licenseId, address indexed payer, uint256 baseAmount, uint256 penalty, uint256 timestamp
    );

    /**
     * @notice Emitted when penalty rate is updated
     * @param newRate New penalty rate in basis points per day
     */
    event PenaltyRateUpdated(uint256 newRate);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the Marketplace contract (proxy pattern)
     * @dev Sets up admin roles. Platform fees are managed by RevenueDistributor.
     * @param admin Address to receive admin role
     * @param revenueDistributor Address of RevenueDistributor contract
     */
    function initialize(
        address admin,
        address revenueDistributor
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

    /**
     * @notice Sets the penalty rate for late recurring payments
     * @dev Only callable by admin. Penalty is calculated pro-rata per second.
     * @param basisPoints Penalty rate in basis points per month (e.g., 500 = 5% per month)
     */
    function setPenaltyRate(uint256 basisPoints) external;

    /**
     * @notice Calculates the number of missed payments for a recurring license
     * @dev Returns 0 for ONE_TIME licenses
     * @param licenseContract Address of the license token contract
     * @param licenseId The license ID to check
     * @return missedPayments Number of missed payment periods
     */
    function getMissedPayments(address licenseContract, uint256 licenseId)
        external
        view
        returns (uint256 missedPayments);


    /**
     * @notice Makes a recurring payment for a subscription license
     * @dev Calculates penalty for late payments, auto-revokes after 3 missed payments
     * @param licenseContract Address of the license token contract
     * @param licenseId The license ID to pay for
     */
    function makeRecurringPayment(address licenseContract, uint256 licenseId) external payable;

    /**
     * @notice Gets the base amount for a recurring payment
     * @param licenseId The license ID
     * @return baseAmount The base payment amount (without penalty)
     */
    function getRecurringPaymentAmount(uint256 licenseId) external view returns (uint256 baseAmount);

    /**
     * @notice Calculates the current penalty for late payment
     * @dev Returns 0 if payment is not overdue or for ONE_TIME licenses
     * @param licenseContract Address of the license token contract
     * @param licenseId The license ID
     * @return penalty Penalty amount in wei
     */
    function calculatePenalty(address licenseContract, uint256 licenseId) external view returns (uint256 penalty);

    /**
     * @notice Gets the total amount due for next recurring payment (base + penalty)
     * @dev Useful for frontends to know exact amount before creating transaction
     * @param licenseContract Address of the license token contract
     * @param licenseId The license ID
     * @return baseAmount The base payment amount
     * @return penalty The penalty amount if overdue
     * @return total The total amount due (baseAmount + penalty)
     */
    function getTotalPaymentDue(address licenseContract, uint256 licenseId)
        external
        view
        returns (uint256 baseAmount, uint256 penalty, uint256 total);
}
