// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/ILicenseToken.sol";
import "./interfaces/IIPAsset.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract LicenseToken is
    ILicenseToken,
    Initializable,
    ERC1155Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
    bytes32 public constant IP_ASSET_ROLE = keccak256("IP_ASSET_ROLE");
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");

    /// @notice Default maximum number of missed payments before auto-revocation (3 payments)
    uint8 public constant DEFAULT_MAX_MISSED_PAYMENTS = 3;

    mapping(uint256 => License) public licenses;
    mapping(uint256 => bool) private _isExpired;
    mapping(uint256 => bool) private _hasExclusiveLicense;
    mapping(uint256 => mapping(address => bool)) private _privateAccessGrants;
    uint256 private _licenseIdCounter;
    address public ipAssetContract;
    address public arbitratorContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory baseURI,
        address admin,
        address ipAsset,
        address arbitrator,
        address revenueDistributor
    ) external initializer {
        __ERC1155_init(baseURI);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITRATOR_ROLE, arbitrator);
        _grantRole(IP_ASSET_ROLE, ipAsset);

        ipAssetContract = ipAsset;
        arbitratorContract = arbitrator;
    }

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
        uint8 maxMissedPayments
    ) external onlyRole(IP_ASSET_ROLE) whenNotPaused returns (uint256) {
        try IIPAsset(ipAssetContract).hasActiveDispute(ipAssetId) returns (bool) {
            // Validate IP asset exists by checking if it has an active dispute status
            // This is a lightweight check that the IP asset contract recognizes this token
        } catch {
            revert InvalidIPAsset();
        }

        // Validate exclusive/non-exclusive and enforce mutual exclusion
        if (isExclusive) {
            if (supply != 1) revert ExclusiveLicenseMustHaveSupplyOne();
            if (_hasExclusiveLicense[ipAssetId]) revert ExclusiveLicenseAlreadyExists();
            _hasExclusiveLicense[ipAssetId] = true;
        }

        // Use default if 0 is passed
        if (maxMissedPayments == 0) {
            maxMissedPayments = DEFAULT_MAX_MISSED_PAYMENTS;
        }

        uint256 licenseId = _licenseIdCounter++;

        licenses[licenseId] = License({
            ipAssetId: ipAssetId,
            supply: supply,
            expiryTime: expiryTime,
            terms: terms,
            isExclusive: isExclusive,
            isRevoked: false,
            publicMetadataURI: publicMetadataURI,
            privateMetadataURI: privateMetadataURI,
            paymentInterval: paymentInterval,
            maxMissedPayments: maxMissedPayments
        });

        _mint(to, licenseId, supply, "");

        // Update IPAsset active license count
        IIPAsset(ipAssetContract).updateActiveLicenseCount(ipAssetId, int256(supply));

        emit LicenseCreated(licenseId, ipAssetId, to, isExclusive, paymentInterval);
        return licenseId;
    }

    function markExpired(uint256 licenseId) external {
        License memory license = licenses[licenseId];

        // Perpetual licenses (expiryTime == 0) cannot expire
        if (license.expiryTime == 0) {
            revert LicenseIsPerpetual();
        }
        if (block.timestamp < license.expiryTime) revert LicenseNotYetExpired();
        if (_isExpired[licenseId]) revert AlreadyMarkedExpired();

        _isExpired[licenseId] = true;

        IIPAsset(ipAssetContract).updateActiveLicenseCount(license.ipAssetId, -int256(license.supply));

        emit LicenseExpired(licenseId);
    }

    function batchMarkExpired(uint256[] memory licenseIds) external {
        for (uint256 i = 0; i < licenseIds.length; i++) {
            try this.markExpired(licenseIds[i]) {
                // Success
            } catch {
                // Continue on error (don't revert entire batch)
            }
        }
    }

    function revokeLicense(uint256 licenseId, string memory reason) external onlyRole(ARBITRATOR_ROLE) {
        _revoke(licenseId);
        emit LicenseRevoked(licenseId, reason);
    }

    function revokeForMissedPayments(uint256 licenseId, uint256 missedCount) external {
        uint8 maxAllowed = licenses[licenseId].maxMissedPayments;
        if (missedCount < maxAllowed) revert InsufficientMissedPayments();
        _revoke(licenseId);
        emit AutoRevoked(licenseId, missedCount);
    }

    function _revoke(uint256 licenseId) internal {
        if (licenses[licenseId].isRevoked) revert AlreadyRevoked();

        licenses[licenseId].isRevoked = true;

        if (licenses[licenseId].isExclusive) {
            _hasExclusiveLicense[licenses[licenseId].ipAssetId] = false;
        }

        License memory license = licenses[licenseId];
        IIPAsset(ipAssetContract).updateActiveLicenseCount(license.ipAssetId, -int256(license.supply));
    }

    function getPublicMetadata(uint256 licenseId) external view returns (string memory) {
        return licenses[licenseId].publicMetadataURI;
    }

    function getPrivateMetadata(uint256 licenseId) external view returns (string memory) {
        if (
            balanceOf(msg.sender, licenseId) > 0 || _privateAccessGrants[licenseId][msg.sender]
                || hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) {
            return licenses[licenseId].privateMetadataURI;
        }
        revert NotAuthorizedForPrivateMetadata();
    }

    function grantPrivateAccess(uint256 licenseId, address account) external {
        if (balanceOf(msg.sender, licenseId) == 0) revert NotLicenseOwner();

        _privateAccessGrants[licenseId][account] = true;
        emit PrivateAccessGranted(licenseId, account);
    }

    function revokePrivateAccess(uint256 licenseId, address account) external {
        if (balanceOf(msg.sender, licenseId) == 0) revert NotLicenseOwner();

        _privateAccessGrants[licenseId][account] = false;
        emit PrivateAccessRevoked(licenseId, account);
    }

    function hasPrivateAccess(uint256 licenseId, address account) external view returns (bool) {
        return _privateAccessGrants[licenseId][account];
    }

    function isRevoked(uint256 licenseId) external view returns (bool) {
        return licenses[licenseId].isRevoked;
    }

    function isExpired(uint256 licenseId) external view returns (bool) {
        return _isExpired[licenseId];
    }

    function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (arbitrator == address(0)) revert InvalidArbitratorAddress();
        address oldArbitrator = arbitratorContract;
        arbitratorContract = arbitrator;
        _revokeRole(ARBITRATOR_ROLE, oldArbitrator);
        _grantRole(ARBITRATOR_ROLE, arbitrator);
        emit ArbitratorContractUpdated(oldArbitrator, arbitrator);
    }

    function setIPAssetContract(address ipAsset) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (ipAsset == address(0)) revert InvalidIPAssetAddress();
        address oldIPAsset = ipAssetContract;
        ipAssetContract = ipAsset;
        _revokeRole(IP_ASSET_ROLE, oldIPAsset);
        _grantRole(IP_ASSET_ROLE, ipAsset);
        emit IPAssetContractUpdated(oldIPAsset, ipAsset);
    }

    function grantRole(bytes32 role, address account)
        public
        override(AccessControlUpgradeable, ILicenseToken)
        onlyRole(getRoleAdmin(role))
    {
        super.grantRole(role, account);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, AccessControlUpgradeable, ILicenseToken)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function getPaymentInterval(uint256 licenseId) external view returns (uint256) {
        return licenses[licenseId].paymentInterval;
    }

    function isRecurring(uint256 licenseId) external view returns (bool) {
        return licenses[licenseId].paymentInterval > 0;
    }

    function isOneTime(uint256 licenseId) external view returns (bool) {
        return licenses[licenseId].paymentInterval == 0;
    }

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
        )
    {
        License memory license = licenses[licenseId];
        return (
            license.ipAssetId,
            license.supply,
            license.expiryTime,
            license.terms,
            license.paymentInterval,
            license.isExclusive,
            license.isRevoked,
            _isExpired[licenseId]
        );
    }

    function isActiveLicense(uint256 licenseId) external view returns (bool) {
        return !licenses[licenseId].isRevoked && !_isExpired[licenseId];
    }

    function getMaxMissedPayments(uint256 licenseId) external view returns (uint8) {
        return licenses[licenseId].maxMissedPayments;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        for (uint256 i = 0; i < ids.length; i++) {
            if (from != address(0)) {
                // Not minting - validate transfer conditions
                if (_isExpired[ids[i]]) revert CannotTransferExpiredLicense();
                if (licenses[ids[i]].isRevoked) revert CannotTransferRevokedLicense();
            }
        }
        super._update(from, to, ids, values);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
