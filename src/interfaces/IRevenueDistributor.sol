// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRevenueDistributor
 * @notice Interface for revenue distribution with interest accrual
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
     * @param interest Interest amount withdrawn
     * @param total Total amount withdrawn
     */
    event Withdrawal(address indexed recipient, uint256 principal, uint256 interest, uint256 total);

    /**
     * @notice Emitted when interest accrues for a recipient
     * @param recipient Address accruing interest
     * @param amount Interest amount accrued
     * @param monthsDelayed Number of months funds were held
     */
    event InterestAccrued(address indexed recipient, uint256 amount, uint256 monthsDelayed);

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
     * @notice Withdraws accumulated funds with interest
     * @dev Calculates interest based on time funds were held
     */
    function withdraw() external;

    /**
     * @notice Gets balance with accrued interest for a recipient
     * @param recipient Address to query
     * @return principal Principal amount available
     * @return interest Interest accrued
     * @return total Total amount available for withdrawal
     */
    function getBalanceWithInterest(address recipient) external view returns (
        uint256 principal,
        uint256 interest,
        uint256 total
    );

    /**
     * @notice EIP-2981 royalty info function
     * @param tokenId The NFT token ID
     * @param salePrice The sale price
     * @return receiver Address to receive royalty
     * @return royaltyAmount Royalty amount to pay
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (
        address receiver,
        uint256 royaltyAmount
    );

    /**
     * @notice Sets the default royalty rate
     * @dev Only callable by admin
     * @param basisPoints Royalty rate in basis points
     */
    function setDefaultRoyalty(uint256 basisPoints) external;

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
     * @notice Grants a role to an account
     * @dev Only callable by role admin
     * @param role The role identifier
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Checks if contract supports a given interface
     * @param interfaceId The interface identifier (ERC-165)
     * @return supported Whether the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool supported);
}
