// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IGovernanceArbitrator
 * @notice Interface for dispute resolution and governance
 * @dev Manages disputes for licenses with 30-day resolution deadline
 */
interface IGovernanceArbitrator {
    // ==================== ENUMS ====================

    /**
     * @dev Possible states of a dispute
     * @param Pending Dispute submitted, awaiting resolution
     * @param Approved Dispute resolved in favor of submitter
     * @param Rejected Dispute resolved against submitter
     * @param Executed Approved dispute has been executed (license revoked)
     */
    enum DisputeStatus {
        Pending,
        Approved,
        Rejected,
        Executed
    }

    // ==================== STRUCTS ====================

    /**
     * @dev Dispute information
     * @param licenseId The license being disputed
     * @param submitter Address that submitted the dispute
     * @param submittedAt Timestamp of dispute submission
     * @param reason Human-readable dispute reason
     * @param proofURI URI pointing to evidence/proof
     * @param resolutionReason Arbitrator's resolution reasoning
     * @param status Current dispute status
     * @param resolver Address that resolved the dispute
     * @param resolvedAt Timestamp of resolution
     * @param executed Whether revocation has been executed
     */
    struct Dispute {
        uint256 licenseId;
        address submitter;
        uint256 submittedAt;
        string reason;
        string proofURI;
        string resolutionReason;
        DisputeStatus status;
        address resolver;
        uint256 resolvedAt;
        bool executed;
    }

    // ==================== EVENTS ====================

    /**
     * @notice Emitted when a new dispute is submitted
     * @param disputeId Unique dispute identifier
     * @param licenseId The license being disputed
     * @param submitter Address submitting the dispute
     * @param reason Dispute reason
     */
    event DisputeSubmitted(
        uint256 indexed disputeId,
        uint256 indexed licenseId,
        address indexed submitter,
        string reason
    );

    /**
     * @notice Emitted when a dispute is resolved
     * @param disputeId The dispute that was resolved
     * @param approved Whether dispute was approved (true) or rejected (false)
     * @param resolver Address that resolved the dispute
     * @param reason Resolution reasoning
     */
    event DisputeResolved(
        uint256 indexed disputeId,
        bool approved,
        address indexed resolver,
        string reason
    );

    /**
     * @notice Emitted when a license is revoked due to dispute
     * @param licenseId The license that was revoked
     * @param disputeId The dispute that caused revocation
     */
    event LicenseRevoked(uint256 indexed licenseId, uint256 indexed disputeId);

    /**
     * @notice Emitted when a dispute becomes overdue
     * @param disputeId The overdue dispute
     * @param daysOverdue Number of days past deadline
     */
    event DisputeOverdue(uint256 indexed disputeId, uint256 daysOverdue);

    // ==================== FUNCTIONS ====================

    /**
     * @notice Initializes the GovernanceArbitrator contract (proxy pattern)
     * @dev Sets up admin roles and contract references
     * @param admin Address to receive admin role
     * @param licenseToken Address of LicenseToken contract
     * @param ipAsset Address of IPAsset contract
     * @param revenueDistributor Address of RevenueDistributor contract
     */
    function initialize(
        address admin,
        address licenseToken,
        address ipAsset,
        address revenueDistributor
    ) external;

    /**
     * @notice Submits a new dispute for a license
     * @dev Can be submitted by any party (licensee, IP owner, third party)
     * @param licenseId The license being disputed
     * @param reason Human-readable dispute reason
     * @param proofURI URI pointing to evidence/documentation
     * @return disputeId Unique identifier for the dispute
     */
    function submitDispute(
        uint256 licenseId,
        string memory reason,
        string memory proofURI
    ) external returns (uint256 disputeId);

    /**
     * @notice Resolves a dispute
     * @dev Only callable by ARBITRATOR_ROLE
     * @param disputeId The dispute to resolve
     * @param approved Whether to approve (true) or reject (false) the dispute
     * @param resolutionReason Explanation of the resolution
     */
    function resolveDispute(
        uint256 disputeId,
        bool approved,
        string memory resolutionReason
    ) external;

    /**
     * @notice Executes license revocation for an approved dispute
     * @dev Calls LicenseToken.revokeLicense() and updates dispute status
     * @param disputeId The approved dispute to execute
     */
    function executeRevocation(uint256 disputeId) external;

    /**
     * @notice Gets full dispute information
     * @param disputeId The dispute ID
     * @return dispute The complete dispute struct
     */
    function getDispute(uint256 disputeId) external view returns (Dispute memory dispute);

    /**
     * @notice Gets all disputes for a specific license
     * @param licenseId The license ID
     * @return disputeIds Array of dispute IDs
     */
    function getDisputesForLicense(uint256 licenseId) external view returns (uint256[] memory disputeIds);

    /**
     * @notice Checks if a dispute is overdue (past 30-day deadline)
     * @param disputeId The dispute ID
     * @return overdue Whether the dispute is overdue
     */
    function isDisputeOverdue(uint256 disputeId) external view returns (bool overdue);

    /**
     * @notice Gets time remaining for dispute resolution
     * @param disputeId The dispute ID
     * @return timeRemaining Seconds remaining (0 if overdue)
     */
    function getTimeRemaining(uint256 disputeId) external view returns (uint256 timeRemaining);

    /**
     * @notice Gets all overdue disputes
     * @return disputeIds Array of overdue dispute IDs
     */
    function getOverdueDisputes() external view returns (uint256[] memory disputeIds);

    /**
     * @notice Grants a role to an account
     * @dev Only callable by role admin
     * @param role The role identifier
     * @param account The account to grant the role to
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @notice Pauses dispute submissions
     * @dev Only callable by PAUSER_ROLE
     */
    function pause() external;

    /**
     * @notice Unpauses dispute submissions
     * @dev Only callable by PAUSER_ROLE
     */
    function unpause() external;
}
