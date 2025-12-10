// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ILicenseToken
 * @notice Interface for License Token contract (ERC-1155 semi-fungible tokens)
 * @dev Manages licenses for IP assets with expiry and revocation
 * @dev Payment tracking is handled by Marketplace contract
 */
interface ILicenseToken {
    // ==================== STRUCTS ====================

    /**
     * @dev License configuration and state
     * @param ipAssetId The IP asset this license is for
     * @param supply Number of license tokens minted (ERC-1155 supply)
     * @param expiryTime Unix timestamp when license expires (0 = perpetual, never expires)
     * @param terms Human-readable license terms
     * @param isExclusive Whether this is an exclusive license
     * @param isRevoked Whether the license has been revoked
     * @param publicMetadataURI Publicly accessible metadata URI
     * @param privateMetadataURI Private metadata URI (access controlled)
     * @param paymentInterval Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)
     * @param maxMissedPayments Maximum number of missed payments before auto-revocation (1-255, 0 defaults to 3)
     * @param penaltyRateBPS Penalty rate in basis points (100 bps = 1% per month, 0 defaults to 500, max 5000 = 50%)
     */
    struct License {
        uint256 ipAssetId;
        uint256 supply;
        uint256 expiryTime;
        string terms;
        bool isExclusive;
        bool isRevoked;
        string publicMetadataURI;
        string privateMetadataURI;
        uint256 paymentInterval;
        uint8 maxMissedPayments;
        uint16 penaltyRateBPS;
    }

    // ==================== CUSTOM ERRORS ====================

    /// @notice Thrown when attempting to create license for invalid IP asset
    error InvalidIPAsset();

    /// @notice Thrown when license supply is invalid (e.g., zero)
    error InvalidSupply();

    /// @notice Thrown when exclusive license does not have supply of exactly 1
    error ExclusiveLicenseMustHaveSupplyOne();

    /// @notice Thrown when attempting to create multiple exclusive licenses for same IP
    error ExclusiveLicenseAlreadyExists();

    /// @notice Thrown when attempting to expire a perpetual license
    error LicenseIsPerpetual();

    /// @notice Thrown when attempting to mark a license as expired before expiry time
    error LicenseNotYetExpired();

    /// @notice Thrown when attempting to mark an already expired license as expired
    error AlreadyMarkedExpired();

    /// @notice Thrown when attempting to revoke an already revoked license
    error AlreadyRevoked();

    /// @notice Thrown when unauthorized access to private metadata is attempted
    error NotAuthorizedForPrivateMetadata();

    /// @notice Thrown when non-license owner attempts owner-only operation
    error NotLicenseOwner();

    /// @notice Thrown when insufficient missed payments for auto-revocation
    error InsufficientMissedPayments();

    /// @notice Thrown when attempting to transfer an expired license
    error CannotTransferExpiredLicense();

    /// @notice Thrown when attempting to transfer a revoked license
    error CannotTransferRevokedLicense();

    /// @notice Thrown when attempting to set arbitrator to zero address
    error InvalidArbitratorAddress();

    /// @notice Thrown when attempting to set IP asset contract to zero address
    error InvalidIPAssetAddress();

    /// @notice Thrown when maxMissedPayments is zero or exceeds allowed maximum
    error InvalidMaxMissedPayments();

    /// @notice Thrown when penalty rate exceeds maximum allowed rate
    error InvalidPenaltyRate();

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a new license is created
     * @param licenseId The ID of the newly created license
     * @param ipAssetId The IP asset this license is for
     * @param licensee The address receiving the license
     * @param isExclusive Whether this is an exclusive license
     * @param paymentInterval Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)
     */
    event LicenseCreated(
        uint256 indexed licenseId,
        uint256 indexed ipAssetId,
        address indexed licensee,
        bool isExclusive,
        uint256 paymentInterval
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

    /**
     * @notice Emitted when private metadata access is revoked
     * @param licenseId The license ID
     * @param account The account whose access was revoked
     */
    event PrivateAccessRevoked(uint256 indexed licenseId, address indexed account);

    /**
     * @notice Emitted when the arbitrator contract is updated
     * @param oldArbitrator The previous arbitrator contract address
     * @param newArbitrator The new arbitrator contract address
     */
    event ArbitratorContractUpdated(address indexed oldArbitrator, address indexed newArbitrator);

    /**
     * @notice Emitted when the IP asset contract is updated
     * @param oldIPAsset The previous IP asset contract address
     * @param newIPAsset The new IP asset contract address
     */
    event IPAssetContractUpdated(address indexed oldIPAsset, address indexed newIPAsset);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the LicenseToken contract (proxy pattern)
     * @dev Sets up ERC1155, AccessControl, and contract references
     * @dev Grants DEFAULT_ADMIN_ROLE, ARBITRATOR_ROLE, and IP_ASSET_ROLE
     * @dev Can only be called once due to initializer modifier
     * @param baseURI Base URI for token metadata
     * @param admin Address to receive all initial admin roles
     * @param ipAsset Address of the IPAsset contract (granted IP_ASSET_ROLE)
     * @param arbitrator Address of the GovernanceArbitrator contract (granted ARBITRATOR_ROLE)
     */
    function initialize(
        string memory baseURI,
        address admin,
        address ipAsset,
        address arbitrator
    ) external;

    /**
     * @notice Mints a new license token
     * @dev Only callable by IP_ASSET_ROLE through IPAsset contract
     * @dev Validates IP asset exists via hasActiveDispute() call
     * @dev Exclusive licenses must have supply = 1 and only one can exist per IP asset
     * @dev If maxMissedPayments = 0, defaults to DEFAULT_MAX_MISSED_PAYMENTS (3)
     * @dev If penaltyRateBPS = 0, defaults to DEFAULT_PENALTY_RATE (500)
     * @dev penaltyRateBPS must be <= MAX_PENALTY_RATE (5000)
     * @dev Updates IP asset active license count
     * @param to Address to receive the license
     * @param ipAssetId The IP asset to license
     * @param supply Number of license tokens to mint (must be 1 for exclusive licenses)
     * @param publicMetadataURI Publicly accessible metadata
     * @param privateMetadataURI Private metadata (access controlled)
     * @param expiryTime Unix timestamp when license expires (0 = perpetual)
     * @param terms Human-readable license terms
     * @param isExclusive Whether this is an exclusive license
     * @param paymentInterval Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)
     * @param maxMissedPayments Maximum missed payments before auto-revocation (0 = use DEFAULT_MAX_MISSED_PAYMENTS)
     * @param penaltyRateBPS Penalty rate in basis points per month (0 = use DEFAULT_PENALTY_RATE, max = MAX_PENALTY_RATE)
     * @return licenseId The ID of the newly minted license
     */
    function mintLicense(
        address to,
        uint256 ipAssetId,
        uint256 supply,
        string memory publicMetadataURI,
        string memory privateMetadataURI,
        uint256 expiryTime,
        string memory terms,
        bool isExclusive,
        uint256 paymentInterval,
        uint8 maxMissedPayments,
        uint16 penaltyRateBPS
    ) external returns (uint256 licenseId);

    /**
     * @notice Marks a license as expired
     * @dev Can be called by anyone once expiry time has passed
     * @dev Perpetual licenses (expiryTime = 0) cannot be expired
     * @dev Updates IP asset active license count
     * @param licenseId The license to mark as expired
     */
    function markExpired(uint256 licenseId) external;

    /**
     * @notice Marks multiple licenses as expired in a single transaction
     * @dev Continues on error - does not revert entire batch if individual license fails
     * @param licenseIds Array of license IDs to mark as expired
     */
    function batchMarkExpired(uint256[] memory licenseIds) external;

    /**
     * @notice Revokes a license
     * @dev Only callable by ARBITRATOR_ROLE (dispute resolution)
     * @dev Clears exclusive license flag if applicable
     * @dev Updates IP asset active license count
     * @param licenseId The license to revoke
     * @param reason Human-readable revocation reason
     */
    function revokeLicense(uint256 licenseId, string memory reason) external;

    /**
     * @notice Revokes a license for missed payments
     * @dev Anyone can call this function, but it will only succeed if missedCount >= maxMissedPayments
     * @dev Payment tracking is handled by Marketplace contract
     * @dev Spam prevention: built-in validation requires missedCount to meet threshold
     * @dev Clears exclusive license flag if applicable
     * @dev Updates IP asset active license count
     * @param licenseId The license to revoke
     * @param missedCount Number of missed payments (must meet maxMissedPayments threshold)
     */
    function revokeForMissedPayments(uint256 licenseId, uint256 missedCount) external;

    /**
     * @notice Gets the public metadata URI for a license
     * @param licenseId The license ID
     * @return uri The public metadata URI
     */
    function getPublicMetadata(uint256 licenseId) external view returns (string memory uri);

    /**
     * @notice Gets the private metadata URI for a license
     * @dev Access controlled - only license holder, granted accounts, and admin
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
     * @notice Revokes private metadata access from an account
     * @dev Only license holder can revoke access
     * @param licenseId The license ID
     * @param account The account to revoke access from
     */
    function revokePrivateAccess(uint256 licenseId, address account) external;

    /**
     * @notice Checks if an account has been granted private metadata access
     * @param licenseId The license ID
     * @param account The account to check
     * @return hasAccess Whether the account has been granted access
     */
    function hasPrivateAccess(uint256 licenseId, address account) external view returns (bool hasAccess);

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
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Revokes ARBITRATOR_ROLE from old address and grants to new address
     * @param arbitrator New arbitrator contract address (cannot be zero address)
     */
    function setArbitratorContract(address arbitrator) external;

    /**
     * @notice Updates the IPAsset contract address
     * @dev Only callable by DEFAULT_ADMIN_ROLE
     * @dev Revokes IP_ASSET_ROLE from old address and grants to new address
     * @param ipAsset New IP asset contract address (cannot be zero address)
     */
    function setIPAssetContract(address ipAsset) external;

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

    /**
     * @notice Gets the payment interval for a license
     * @param licenseId The license ID
     * @return interval Payment interval in seconds (0 = ONE_TIME, >0 = RECURRENT)
     */
    function getPaymentInterval(uint256 licenseId) external view returns (uint256 interval);

    /**
     * @notice Checks if a license has recurring payments
     * @param licenseId The license ID
     * @return recurring True if payment interval > 0
     */
    function isRecurring(uint256 licenseId) external view returns (bool recurring);

    /**
     * @notice Checks if a license is one-time payment
     * @param licenseId The license ID
     * @return oneTime True if payment interval == 0
     */
    function isOneTime(uint256 licenseId) external view returns (bool oneTime);

    /**
     * @notice Gets comprehensive license information
     * @param licenseId The license ID
     * @return ipAssetId The IP asset this license is for
     * @return supply Number of license tokens minted
     * @return expiryTime Unix timestamp when license expires
     * @return terms Human-readable license terms
     * @return paymentInterval Payment interval in seconds
     * @return isExclusive Whether this is an exclusive license
     * @return revokedStatus Whether the license has been revoked
     * @return expiredStatus Whether the license has expired
     */
    function getLicenseInfo(uint256 licenseId)
        external
        view
        returns (
            uint256 ipAssetId,
            uint256 supply,
            uint256 expiryTime,
            string memory terms,
            uint256 paymentInterval,
            bool isExclusive,
            bool revokedStatus,
            bool expiredStatus
        );

    /**
     * @notice Checks if a license is currently active
     * @dev A license is active if it is neither revoked nor expired
     * @param licenseId The license ID
     * @return active True if license is not revoked and not expired
     */
    function isActiveLicense(uint256 licenseId) external view returns (bool active);

    /**
     * @notice Gets the maximum number of missed payments allowed for a license
     * @param licenseId The license ID
     * @return maxMissed Maximum number of missed payments before auto-revocation
     */
    function getMaxMissedPayments(uint256 licenseId) external view returns (uint8 maxMissed);

    /**
     * @notice Gets the penalty rate for a license
     * @param licenseId The license ID
     * @return penaltyRate Penalty rate in basis points (100 bps = 1% per month)
     */
    function getPenaltyRate(uint256 licenseId) external view returns (uint16 penaltyRate);
}
