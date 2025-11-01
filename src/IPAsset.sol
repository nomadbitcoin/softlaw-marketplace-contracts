// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IIPAsset.sol";
import "./base/Initializable.sol";
import "./base/ERC721Upgradeable.sol";
import "./base/AccessControlUpgradeable.sol";
import "./base/PausableUpgradeable.sol";
import "./base/UUPSUpgradeable.sol";

contract IPAsset is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IIPAsset
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant LICENSE_MANAGER_ROLE = keccak256("LICENSE_MANAGER_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    address public licenseTokenContract;
    address public arbitratorContract;

    uint256 private _tokenIdCounter;
    mapping(uint256 => uint256) public metadataVersion;
    mapping(uint256 => mapping(uint256 => string)) public metadataHistory;
    mapping(uint256 => uint256) public activeLicenseCount;
    mapping(uint256 => bool) private _hasActiveDispute;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address licenseToken,
        address arbitrator
    ) external initializer {
        __ERC721_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        licenseTokenContract = licenseToken;
        arbitratorContract = arbitrator;
    }

    function mintIP(address to, string memory metadataURI) external whenNotPaused returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        metadataHistory[tokenId][0] = metadataURI;
        emit IPMinted(tokenId, to, metadataURI);
        return tokenId;
    }

    function mintLicense(
        uint256 ipTokenId,
        address licensee,
        uint256 amount,
        string memory publicMetadataURI,
        string memory privateMetadataURI,
        uint256 expiryTime,
        uint256 royaltyBasisPoints,
        string memory terms,
        bool isExclusive
    ) external returns (uint256) {
        require(ownerOf(ipTokenId) == msg.sender, "Not token owner");
        return 0; // TODO: Return actual licenseId from LicenseToken
    }

    function updateMetadata(uint256 tokenId, string memory newURI) external whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        uint256 newVersion = ++metadataVersion[tokenId];
        metadataHistory[tokenId][newVersion] = newURI;
        emit MetadataUpdated(tokenId, newVersion, newURI);
    }

    function configureRevenueSplit(
        uint256 tokenId,
        address[] memory recipients,
        uint256[] memory shares
    ) external whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        emit RevenueSplitConfigured(tokenId, recipients, shares);
    }

    function burn(uint256 tokenId) external whenNotPaused {
        require(ownerOf(tokenId) == msg.sender, "Not token owner");
        require(activeLicenseCount[tokenId] == 0, "Cannot burn: active licenses exist");
        require(!_hasActiveDispute[tokenId], "Cannot burn: active dispute");
        _burn(tokenId);
    }

    function setDisputeStatus(uint256 tokenId, bool hasDispute) external onlyRole(ARBITRATOR_ROLE) {
        _hasActiveDispute[tokenId] = hasDispute;
        emit DisputeStatusChanged(tokenId, hasDispute);
    }

    function setLicenseTokenContract(address licenseToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        licenseTokenContract = licenseToken;
    }

    function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        arbitratorContract = arbitrator;
    }

    function updateActiveLicenseCount(uint256 tokenId, int256 delta) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (delta > 0) {
            activeLicenseCount[tokenId] += uint256(delta);
        } else {
            activeLicenseCount[tokenId] -= uint256(-delta);
        }
    }

    function hasActiveDispute(uint256 tokenId) external view returns (bool) {
        return _hasActiveDispute[tokenId];
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            ERC721Upgradeable.supportsInterface(interfaceId) ||
            AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
