// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRevenueDistributor
 * @notice Interface for revenue distribution with penalty calculation for late recurring payments
 * @dev Non-upgradeable contract implementing EIP-2981 royalty standard
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

    /**
     * @dev Balance tracking for recipient withdrawals
     * @param principal Principal amount available for withdrawal
     * @param timestamp Last update timestamp for penalty calculation (RECURRENT payments only)
     */
    struct Balance {
        uint256 principal;
        uint256 timestamp;
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

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a payment is distributed
     * @param ipAssetId The IP asset the payment is for
     * @param amount Total payment amount
     * @param platformFee Fee taken by platform
     */
    event PaymentDistributed(uint256 indexed ipAssetId, uint256 amount, uint256 platformFee);

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
     * @notice Emitted when penalty accrues for late payment (RECURRENT payments only)
     * @param recipient Address accruing penalty
     * @param amount Penalty amount accrued
     * @param monthsDelayed Number of months payment was delayed
     */
    event PenaltyAccrued(address indexed recipient, uint256 amount, uint256 monthsDelayed);

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
     */
    function distributePayment(uint256 ipAssetId, uint256 amount) external payable;

    /**
     * @notice Withdraws accumulated funds with penalty (if applicable)
     * @dev Calculates penalty for late recurring payments based on time delayed
     */
    function withdraw() external;

    /**
     * @notice Gets the principal balance for a recipient
     * @param recipient Address to query
     * @return balance Principal amount available for withdrawal
     */
    function getBalance(address recipient) external view returns (uint256 balance);

    /**
     * @notice Gets balance with accrued penalty for a recipient (RECURRENT payments)
     * @param recipient Address to query
     * @return principal Principal amount available
     * @return penalty Penalty accrued for late recurring payments
     * @return total Total amount available for withdrawal
     */
    function getBalanceWithPenalty(address recipient) external view returns (
        uint256 principal,
        uint256 penalty,
        uint256 total
    );

    /**
     * @notice Sets the default royalty rate
     * @dev Only callable by admin
     * @param basisPoints Royalty rate in basis points
     */
    function setDefaultRoyalty(uint256 basisPoints) external;

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
}
