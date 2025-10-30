// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ILicenseToken
 * @notice Interface for License Token contract (ERC-1155 semi-fungible tokens)
 * @dev Manages licenses for IP assets with expiry, revocation, and payment tracking
 */
interface ILicenseToken {
    // ==================== STRUCTS ====================

    /**
     * @dev License configuration and state
     * @param ipAssetId The IP asset this license is for
     * @param expiryTime Unix timestamp when license expires
     * @param royaltyBasisPoints Royalty rate in basis points (1000 = 10%)
     * @param terms Human-readable license terms
     * @param isExclusive Whether this is an exclusive license
     * @param isRevoked Whether the license has been revoked
     * @param publicMetadataURI Publicly accessible metadata URI
     * @param privateMetadataURI Private metadata URI (access controlled)
     */
    struct License {
        uint256 ipAssetId;
        uint256 expiryTime;
        uint256 royaltyBasisPoints;
        string terms;
        bool isExclusive;
        bool isRevoked;
        string publicMetadataURI;
        string privateMetadataURI;
    }

    /**
     * @dev Payment tracking for recurring payment licenses
     * @param lastPaymentTime Timestamp of most recent payment
     * @param missedPayments Count of consecutive missed payments
     * @param nextPaymentDue Timestamp when next payment is due
     * @param paymentInterval Duration between required payments
     */
    struct PaymentSchedule {
        uint256 lastPaymentTime;
        uint256 missedPayments;
        uint256 nextPaymentDue;
        uint256 paymentInterval;
    }

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a new license is created
     * @param licenseId The ID of the newly created license
     * @param ipAssetId The IP asset this license is for
     * @param licensee The address receiving the license
     * @param isExclusive Whether this is an exclusive license
     */
    event LicenseCreated(
        uint256 indexed licenseId,
        uint256 indexed ipAssetId,
        address indexed licensee,
        bool isExclusive
    );

    /**
     * @notice Emitted when a license expires
     * @param licenseId The license that expired
     */
    event LicenseExpired(uint256 indexed licenseId);

    /**
     * @notice Emitted when a license is revoked
     * @param licenseId The license that was revoked
     * @param reason Human-readable revocation reason
     */
    event LicenseRevoked(uint256 indexed licenseId, string reason);

    /**
     * @notice Emitted when a license payment is recorded
     * @param licenseId The license the payment is for
     * @param timestamp Time the payment was recorded
     */
    event PaymentRecorded(uint256 indexed licenseId, uint256 timestamp);

    /**
     * @notice Emitted when a license is automatically revoked for missed payments
     * @param licenseId The license that was auto-revoked
     * @param missedPayments Number of missed payments that triggered revocation
     */
    event AutoRevoked(uint256 indexed licenseId, uint256 missedPayments);

    /**
     * @notice Emitted when private metadata access is granted
     * @param licenseId The license ID
     * @param account The account granted access
     */
    event PrivateAccessGranted(uint256 indexed licenseId, address indexed account);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the LicenseToken contract (proxy pattern)
     * @dev Sets up ERC1155, AccessControl, and contract references
     * @param baseURI Base URI for token metadata
     * @param admin Address to receive all initial admin roles
     * @param ipAsset Address of the IPAsset contract
     * @param arbitrator Address of the GovernanceArbitrator contract
     * @param revenueDistributor Address of the RevenueDistributor contract
     */
    function initialize(
        string memory baseURI,
        address admin,
        address ipAsset,
        address arbitrator,
        address revenueDistributor
    ) external;

    /**
     * @notice Mints a new license token
     * @dev Only callable by IP asset owner through IPAsset contract
     * @param to Address to receive the license
     * @param ipAssetId The IP asset to license
     * @param amount Number of license tokens (for semi-fungible licenses)
     * @param publicMetadataURI Publicly accessible metadata
     * @param privateMetadataURI Private metadata (access controlled)
     * @param expiryTime Unix timestamp when license expires
     * @param royaltyBasisPoints Royalty rate in basis points
     * @param terms Human-readable license terms
     * @param isExclusive Whether this is an exclusive license
     * @return licenseId The ID of the newly minted license
     */
    function mintLicense(
        address to,
        uint256 ipAssetId,
        uint256 amount,
        string memory publicMetadataURI,
        string memory privateMetadataURI,
        uint256 expiryTime,
        uint256 royaltyBasisPoints,
        string memory terms,
        bool isExclusive
    ) external returns (uint256 licenseId);

    /**
     * @notice Marks a license as expired
     * @dev Can be called by anyone once expiry time has passed
     * @param licenseId The license to mark as expired
     */
    function markExpired(uint256 licenseId) external;

    /**
     * @notice Marks multiple licenses as expired in a single transaction
     * @param licenseIds Array of license IDs to mark as expired
     */
    function batchMarkExpired(uint256[] memory licenseIds) external;

    /**
     * @notice Revokes a license
     * @dev Only callable by ARBITRATOR_ROLE (dispute resolution)
     * @param licenseId The license to revoke
     * @param reason Human-readable revocation reason
     */
    function revokeLicense(uint256 licenseId, string memory reason) external;

    /**
     * @notice Records a license payment
     * @dev Updates payment schedule and resets missed payment counter
     * @param licenseId The license the payment is for
     */
    function recordPayment(uint256 licenseId) external;

    /**
     * @notice Records a missed payment
     * @dev Increments missed payment counter
     * @param licenseId The license with the missed payment
     */
    function recordMissedPayment(uint256 licenseId) external;

    /**
     * @notice Checks if a license should be auto-revoked for missed payments
     * @dev Revokes if missed payments >= 3
     * @param licenseId The license to check
     */
    function checkAndRevokeForMissedPayments(uint256 licenseId) external;

    /**
     * @notice Gets the public metadata URI for a license
     * @param licenseId The license ID
     * @return uri The public metadata URI
     */
    function getPublicMetadata(uint256 licenseId) external view returns (string memory uri);

    /**
     * @notice Gets the private metadata URI for a license
     * @dev Access controlled - only license holder and granted accounts
     * @param licenseId The license ID
     * @return uri The private metadata URI
     */
    function getPrivateMetadata(uint256 licenseId) external view returns (string memory uri);

    /**
     * @notice Grants access to private metadata for an account
     * @dev Only license holder can grant access
     * @param licenseId The license ID
     * @param account The account to grant access to
     */
    function grantPrivateAccess(uint256 licenseId, address account) external;

    /**
     * @notice Checks if a license is revoked
     * @param licenseId The license ID
     * @return revoked Whether the license is revoked
     */
    function isRevoked(uint256 licenseId) external view returns (bool revoked);

    /**
     * @notice Checks if a license is expired
     * @param licenseId The license ID
     * @return expired Whether the license is expired
     */
    function isExpired(uint256 licenseId) external view returns (bool expired);

    /**
     * @notice Updates the GovernanceArbitrator contract address
     * @dev Only callable by admin
     * @param arbitrator New arbitrator contract address
     */
    function setArbitratorContract(address arbitrator) external;

    /**
     * @notice Reactivates a previously expired or revoked license
     * @dev Only callable by admin or arbitrator (e.g., after dispute resolution)
     * @param licenseId The license to reactivate
     */
    function reactivateLicense(uint256 licenseId) external;

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

    // ==================== ERC-1155 STANDARD FUNCTIONS ====================

    /**
     * @notice Gets the balance of an account for a specific license token
     * @param account The account to query
     * @param id The license token ID
     * @return balance The number of tokens owned
     */
    function balanceOf(address account, uint256 id) external view returns (uint256 balance);

    /**
     * @notice Gets the total supply of a license token
     * @param id The license token ID
     * @return supply The total number of tokens minted
     */
    function totalSupply(uint256 id) external view returns (uint256 supply);

    /**
     * @notice Safely transfers a license token
     * @dev Transfers are blocked for expired or revoked licenses
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param id License token ID
     * @param amount Number of tokens to transfer
     * @param data Additional data for transfer hooks
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external;

    /**
     * @notice Sets approval for all tokens for an operator
     * @param operator The operator address
     * @param approved Whether to approve or revoke
     */
    function setApprovalForAll(address operator, bool approved) external;
}
