// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRevenueDistributor
 * @notice Interface for simple revenue distribution to configured recipients
 * @dev Non-upgradeable contract implementing EIP-2981 royalty standard
 * @dev Pure distribution logic - payment timing and penalties handled by calling contracts (e.g., Marketplace)
 */
interface IRevenueDistributor {
    // ==================== STRUCTS ====================

    /**
     * @dev Revenue split configuration for an IP asset
     * @param recipients Array of addresses to receive revenue shares
     * @param shares Array of share amounts in basis points (must sum to 10000)
     */
    struct Split {
        address[] recipients;
        uint256[] shares;
    }


    // ==================== ERRORS ====================

    /// @notice Thrown when array lengths don't match
    error ArrayLengthMismatch();

    /// @notice Thrown when no recipients are provided
    error NoRecipientsProvided();

    /// @notice Thrown when a recipient address is zero
    error InvalidRecipient();

    /// @notice Thrown when shares don't sum to 10000 basis points
    error InvalidSharesSum();

    /// @notice Thrown when msg.value doesn't match amount parameter
    error IncorrectPaymentAmount();

    /// @notice Thrown when IP asset does not exist
    error InvalidIPAsset();

    /// @notice Thrown when attempting to withdraw with zero balance
    error NoBalanceToWithdraw();

    /// @notice Thrown when ETH transfer fails during withdrawal
    error TransferFailed();

    /// @notice Thrown when treasury address is zero
    error InvalidTreasuryAddress();

    /// @notice Thrown when platform fee exceeds 100%
    error InvalidPlatformFee();

    /// @notice Thrown when royalty rate exceeds 100%
    error InvalidRoyalty();

    /// @notice Thrown when IPAsset contract address is zero
    error InvalidIPAssetAddress();

    /// @notice Thrown when basis points exceeds 10000 (100%)
    error InvalidBasisPoints();

    /// @notice Thrown when royalty rate exceeds 100%
    error InvalidRoyaltyRate();

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a payment is distributed
     * @param ipAssetId The IP asset the payment is for
     * @param amount Total payment amount
     * @param seller Address of the seller
     * @param isPrimarySale Whether this is a primary sale (seller is in split recipients)
     */
    event PaymentDistributed(uint256 indexed ipAssetId, uint256 amount, address indexed seller, bool isPrimarySale);

    /**
     * @notice Emitted when a revenue split is configured
     * @param ipAssetId The IP asset ID
     * @param recipients Array of recipient addresses
     * @param shares Array of share amounts
     */
    event SplitConfigured(uint256 indexed ipAssetId, address[] recipients, uint256[] shares);

    /**
     * @notice Emitted when a recipient withdraws funds
     * @param recipient Address withdrawing
     * @param principal Principal amount withdrawn
     */
    event Withdrawal(address indexed recipient, uint256 principal);


    /**
     * @notice Emitted when default royalty rate is updated
     * @param newRoyaltyBasisPoints New royalty rate in basis points
     */
    event RoyaltyUpdated(uint256 newRoyaltyBasisPoints);

    /**
     * @notice Emitted when a per-asset royalty rate is updated
     * @param ipAssetId The IP asset ID
     * @param basisPoints New royalty rate in basis points
     */
    event AssetRoyaltyUpdated(uint256 indexed ipAssetId, uint256 basisPoints);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Configures revenue split for an IP asset
     * @dev Only callable by IP asset owner or CONFIGURATOR_ROLE
     * @param ipAssetId The IP asset ID
     * @param recipients Array of recipient addresses
     * @param shares Array of share amounts in basis points (must sum to 10000)
     */
    function configureSplit(
        uint256 ipAssetId,
        address[] memory recipients,
        uint256[] memory shares
    ) external;

    /**
     * @notice Distributes a payment according to configured splits
     * @dev Deducts platform fee then splits remainder among recipients
     * @param ipAssetId The IP asset ID
     * @param amount Payment amount to distribute
     * @param seller Address of the seller (receives remainder for secondary sales)
     * @param isPrimarySale True for primary sales (100% to split), false for secondary (royalty to split, remainder to seller)
     */
    function distributePayment(uint256 ipAssetId, uint256 amount, address seller, bool isPrimarySale) external payable;

    /**
     * @notice Withdraws accumulated funds
     * @dev All recipients (including platform treasury) use this function to withdraw
     */
    function withdraw() external;

    /**
     * @notice Gets the principal balance for a recipient
     * @param recipient Address to query
     * @return balance Principal amount available for withdrawal
     */
    function getBalance(address recipient) external view returns (uint256 balance);


    /**
     * @notice Sets the default royalty rate
     * @dev Only callable by admin
     * @param basisPoints Royalty rate in basis points
     */
    function setDefaultRoyalty(uint256 basisPoints) external;

    /**
     * @notice Configure royalty rate for a specific IP asset
     * @dev Only callable by CONFIGURATOR_ROLE
     * @param ipAssetId The IP asset ID
     * @param basisPoints Royalty rate in basis points (e.g., 1000 = 10%)
     */
    function setAssetRoyalty(uint256 ipAssetId, uint256 basisPoints) external;

    /**
     * @notice Get royalty rate for an IP asset (custom or default)
     * @param ipAssetId The IP asset ID
     * @return Royalty rate in basis points
     */
    function getAssetRoyalty(uint256 ipAssetId) external view returns (uint256);

    /**
     * @notice Grants CONFIGURATOR_ROLE to the IPAsset contract
     * @dev Only callable by admin. Should be called after IPAsset deployment.
     * @param ipAssetContract Address of the IPAsset contract
     */
    function grantConfiguratorRole(address ipAssetContract) external;

    /**
     * @notice Gets the configured split for an IP asset
     * @param ipAssetId The IP asset ID
     * @return recipients Array of recipient addresses
     * @return shares Array of share amounts
     */
    function ipSplits(uint256 ipAssetId) external view returns (
        address[] memory recipients,
        uint256[] memory shares
    );

    /**
     * @notice Checks if a split is configured for an IP asset
     * @param ipAssetId The IP asset ID
     * @return configured True if split exists, false otherwise
     */
    function isSplitConfigured(uint256 ipAssetId) external view returns (bool configured);
}
