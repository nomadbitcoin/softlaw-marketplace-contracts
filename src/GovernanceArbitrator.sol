// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IGovernanceArbitrator.sol";
import "./interfaces/ILicenseToken.sol";
import "./interfaces/IIPAsset.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract GovernanceArbitrator is
    IGovernanceArbitrator,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
    uint256 public constant RESOLUTION_DEADLINE = 30 days;

    address public licenseTokenContract;
    address public ipAssetContract;
    address public revenueDistributorContract;

    uint256 private _disputeIdCounter;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => uint256[]) private _licenseDisputes;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address admin,
        address licenseToken,
        address ipAsset,
        address revenueDistributor
    ) external initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITRATOR_ROLE, admin);

        licenseTokenContract = licenseToken;
        ipAssetContract = ipAsset;
        revenueDistributorContract = revenueDistributor;
    }

    function submitDispute(
        uint256 licenseId,
        string memory reason,
        string memory proofURI
    ) external whenNotPaused returns (uint256) {
        if (bytes(reason).length == 0) revert EmptyReason();

        ILicenseToken licenseToken = ILicenseToken(licenseTokenContract);

        if (!licenseToken.isActiveLicense(licenseId)) {
            revert LicenseNotActive();
        }

        (uint256 ipAssetId,,,,,,,) = licenseToken.getLicenseInfo(licenseId);

        IIPAsset ipAsset = IIPAsset(ipAssetContract);
        address ipOwner = IERC721(ipAssetContract).ownerOf(ipAssetId);

        // Only IP owner or licensee can submit disputes
        bool isIPOwner = msg.sender == ipOwner;
        bool isLicensee = IERC1155(licenseTokenContract).balanceOf(msg.sender, licenseId) > 0;
        if (!isIPOwner && !isLicensee) {
            revert NotAuthorizedToDispute();
        }

        uint256 disputeId = ++_disputeIdCounter;

        disputes[disputeId] = Dispute({
            licenseId: licenseId,
            submitter: msg.sender,
            ipOwner: ipOwner,
            reason: reason,
            proofURI: proofURI,
            status: DisputeStatus.Pending,
            submittedAt: block.timestamp,
            resolvedAt: 0,
            resolver: address(0),
            resolutionReason: ""
        });

        _licenseDisputes[licenseId].push(disputeId);

        ipAsset.setDisputeStatus(ipAssetId, true);

        emit DisputeSubmitted(disputeId, licenseId, msg.sender, reason);
        return disputeId;
    }

    function resolveDispute(
        uint256 disputeId,
        bool approve,
        string memory resolutionReason
    ) external onlyRole(ARBITRATOR_ROLE) whenNotPaused {
        Dispute storage dispute = disputes[disputeId];

        if (dispute.status != DisputeStatus.Pending) revert DisputeAlreadyResolved();

        dispute.status = approve ? DisputeStatus.Approved : DisputeStatus.Rejected;
        dispute.resolver = msg.sender;
        dispute.resolvedAt = block.timestamp;
        dispute.resolutionReason = resolutionReason;

        ILicenseToken licenseToken = ILicenseToken(licenseTokenContract);
        (uint256 ipAssetId,,,,,,,) = licenseToken.getLicenseInfo(dispute.licenseId);

        uint256[] memory licenseDisputeIds = _licenseDisputes[dispute.licenseId];

        bool hasOtherPending = false;
        for (uint256 i = 0; i < licenseDisputeIds.length; i++) {
            if (
                licenseDisputeIds[i] != disputeId &&
                disputes[licenseDisputeIds[i]].status == DisputeStatus.Pending
            ) {
                hasOtherPending = true;
                break;
            }
        }

        if (!hasOtherPending) {
            IIPAsset(ipAssetContract).setDisputeStatus(ipAssetId, false);
        }

        // If dispute approved, automatically revoke the license
        if (approve) {
            licenseToken.revokeLicense(dispute.licenseId, resolutionReason);
            emit LicenseRevoked(dispute.licenseId, disputeId);
        }

        emit DisputeResolved(disputeId, approve, msg.sender, resolutionReason);
    }

    function executeRevocation(uint256 disputeId) external onlyRole(ARBITRATOR_ROLE) whenNotPaused {
        Dispute storage dispute = disputes[disputeId];

        if (dispute.status != DisputeStatus.Approved) revert DisputeNotApproved();

        dispute.status = DisputeStatus.Executed;

        ILicenseToken(licenseTokenContract).revokeLicense(
            dispute.licenseId,
            dispute.resolutionReason
        );

        emit LicenseRevoked(dispute.licenseId, disputeId);
    }

    function getDispute(uint256 disputeId) external view returns (Dispute memory dispute) {
        return disputes[disputeId];
    }

    function getDisputesForLicense(uint256 licenseId) external view returns (uint256[] memory disputeIds) {
        return _licenseDisputes[licenseId];
    }

    function isDisputeOverdue(uint256 disputeId) external view returns (bool overdue) {
        Dispute memory dispute = disputes[disputeId];
        bool isOverdue =
            dispute.status == DisputeStatus.Pending &&
            block.timestamp > dispute.submittedAt + RESOLUTION_DEADLINE;

        return isOverdue;
    }

    function getTimeRemaining(uint256 disputeId) external view returns (uint256 timeRemaining) {
        Dispute memory dispute = disputes[disputeId];
        uint256 deadline = dispute.submittedAt + RESOLUTION_DEADLINE;
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    function getDisputeCount() external view returns (uint256 count) {
        return _disputeIdCounter;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
