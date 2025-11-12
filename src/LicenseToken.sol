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

    mapping(uint256 => License) public licenses;
    mapping(uint256 => bool) private _isExpired;
    mapping(uint256 => bool) private _hasExclusiveLicense;
    uint256 private _licenseIdCounter;
    address public ipAssetContract;

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
        uint256 paymentInterval
    ) external onlyRole(IP_ASSET_ROLE) whenNotPaused returns (uint256) {
        // Validate IP asset exists by checking if it has an active dispute status
        // This is a lightweight check that the IP asset contract recognizes this token
        try IIPAsset(ipAssetContract).hasActiveDispute(ipAssetId) returns (bool) {
            // Valid IP asset - dispute check succeeded
        } catch {
            revert InvalidIPAsset();
        }

        // Validate exclusive/non-exclusive and enforce mutual exclusion
        if (isExclusive) {
            if (supply != 1) revert ExclusiveLicenseMustHaveSupplyOne();
            if (_hasExclusiveLicense[ipAssetId]) revert ExclusiveLicenseAlreadyExists();
            _hasExclusiveLicense[ipAssetId] = true;
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
            paymentInterval: paymentInterval
        });

        _mint(to, licenseId, supply, "");

        // Update IPAsset active license count
        IIPAsset(ipAssetContract).updateActiveLicenseCount(ipAssetId, int256(supply));

        emit LicenseCreated(licenseId, ipAssetId, to, isExclusive, paymentInterval);
        return licenseId;
    }

    function markExpired(uint256 licenseId) external {}

    function batchMarkExpired(uint256[] memory licenseIds) external {}

    function revokeLicense(uint256 licenseId, string memory reason) external {}

    function recordPayment(uint256 licenseId) external {}

    function checkAndRevokeForMissedPayments(uint256 licenseId) external {}

    function getPublicMetadata(uint256 licenseId) external view returns (string memory) {
        return "";
    }

    function getPrivateMetadata(uint256 licenseId) external view returns (string memory) {
        return "";
    }

    function grantPrivateAccess(uint256 licenseId, address account) external {}

    function isRevoked(uint256 licenseId) external view returns (bool) {
        return false;
    }

    function isExpired(uint256 licenseId) external view returns (bool) {
        return _isExpired[licenseId];
    }

    function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE) {}

    function reactivateLicense(uint256 licenseId) external {}

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

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
