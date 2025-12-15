// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IIPAsset.sol";
import "./interfaces/ILicenseToken.sol";
import "./interfaces/IRevenueDistributor.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract IPAsset is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IIPAsset
{
    bytes32 public constant LICENSE_MANAGER_ROLE = keccak256("LICENSE_MANAGER_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    address public licenseTokenContract;
    address public arbitratorContract;
    address public revenueDistributor;

    uint256 private _tokenIdCounter;
    mapping(uint256 => string) private _metadataURIs;
    mapping(uint256 => uint256) public activeLicenseCount;
    mapping(uint256 => bool) private _hasActiveDispute;
    mapping(uint256 => string) private _privateMetadata;
    mapping(uint256 => IIPAsset.WrappedNFT) private _wrappedNFTs;
    mapping(address => mapping(uint256 => uint256)) private _nftToIPAsset;

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
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        licenseTokenContract = licenseToken;
        arbitratorContract = arbitrator;
        _tokenIdCounter = 1;
    }

    function mintIP(address to, string memory metadataURI) external whenNotPaused returns (uint256) {
        if (to == address(0)) revert InvalidAddress();
        if (bytes(metadataURI).length == 0) revert EmptyMetadata();

        uint256 tokenId = _tokenIdCounter++;
        _mint(to, tokenId);
        _metadataURIs[tokenId] = metadataURI;
        emit IPMinted(tokenId, to, metadataURI);
        return tokenId;
    }

    function wrapNFT(
        address nftContract,
        uint256 nftTokenId,
        string memory metadataURI
    ) external whenNotPaused nonReentrant returns (uint256 ipTokenId) {
        if (nftContract == address(0)) revert InvalidAddress();
        if (bytes(metadataURI).length == 0) revert EmptyMetadata();

        address nftOwner = IERC721(nftContract).ownerOf(nftTokenId);
        if (nftOwner != msg.sender) revert NFTNotOwned(nftContract, nftTokenId, msg.sender);

        uint256 existingIPAsset = _nftToIPAsset[nftContract][nftTokenId];
        if (existingIPAsset != 0) revert NFTAlreadyWrapped(existingIPAsset);

        ipTokenId = _tokenIdCounter++;
        _mint(msg.sender, ipTokenId);
        _metadataURIs[ipTokenId] = metadataURI;

        _wrappedNFTs[ipTokenId] = IIPAsset.WrappedNFT({
            nftContract: nftContract,
            nftTokenId: nftTokenId
        });

        _nftToIPAsset[nftContract][nftTokenId] = ipTokenId;

        emit IPMinted(ipTokenId, msg.sender, metadataURI);
        emit NFTWrapped(ipTokenId, nftContract, nftTokenId, msg.sender);

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), nftTokenId);

        return ipTokenId;
    }

    function unwrapNFT(uint256 tokenId) external whenNotPaused nonReentrant {
        // CHECKS
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        IIPAsset.WrappedNFT storage wrapped = _wrappedNFTs[tokenId];
        if (wrapped.nftContract == address(0)) revert NotWrappedNFT();

        if (activeLicenseCount[tokenId] > 0) {
            revert HasActiveLicenses(tokenId, activeLicenseCount[tokenId]);
        }

        if (_hasActiveDispute[tokenId]) {
            revert HasActiveDispute(tokenId);
        }

        // Store NFT details in memory for later transfer
        address nftContract = wrapped.nftContract;
        uint256 nftTokenId = wrapped.nftTokenId;

        // EFFECTS
        _burn(tokenId);

        delete _wrappedNFTs[tokenId];
        delete _nftToIPAsset[nftContract][nftTokenId];
        delete _metadataURIs[tokenId];
        delete activeLicenseCount[tokenId];
        delete _hasActiveDispute[tokenId];

        emit NFTUnwrapped(tokenId, nftContract, nftTokenId, msg.sender);

        // INTERACTIONS
        IERC721(nftContract).transferFrom(address(this), msg.sender, nftTokenId);
    }

    function mintLicense(
        uint256 ipTokenId,
        address licensee,
        uint256 supply,
        string memory publicMetadataURI,
        string memory privateMetadataURI,
        uint256 expiryTime,
        string memory terms,
        bool isExclusive,
        uint256 paymentInterval
    ) external whenNotPaused returns (uint256) {
        if (ownerOf(ipTokenId) != msg.sender) revert NotTokenOwner();
        if (licensee == address(0)) revert InvalidAddress();

        // Call LicenseToken to mint the actual license
        // Using 0 for maxMissedPayments to apply DEFAULT_MAX_MISSED_PAYMENTS (3)
        // Using 0 for penaltyRateBPS to apply DEFAULT_PENALTY_RATE (500 = 5% annual)
        uint256 licenseId = ILicenseToken(licenseTokenContract).mintLicense(
            licensee,
            ipTokenId,
            supply,
            publicMetadataURI,
            privateMetadataURI,
            expiryTime,
            terms,
            isExclusive,
            paymentInterval,
            0,  // maxMissedPayments: 0 = use default (3)
            0   // penaltyRateBPS: 0 = use default (500 = 5% annual)
        );

        emit LicenseRegistered(ipTokenId, licenseId, licensee, supply, isExclusive);
        return licenseId;
    }

    function updateMetadata(uint256 tokenId, string memory newURI) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (bytes(newURI).length == 0) revert EmptyMetadata();

        string memory oldURI = _metadataURIs[tokenId];
        _metadataURIs[tokenId] = newURI;
        emit MetadataUpdated(tokenId, oldURI, newURI, block.timestamp);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _metadataURIs[tokenId];
    }

    function configureRevenueSplit(
        uint256 tokenId,
        address[] memory recipients,
        uint256[] memory shares
    ) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        IRevenueDistributor(revenueDistributor).configureSplit(
            tokenId,
            recipients,
            shares
        );

        emit RevenueSplitConfigured(tokenId, recipients, shares);
    }

    function setRoyaltyRate(uint256 tokenId, uint256 basisPoints) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        IRevenueDistributor(revenueDistributor).setAssetRoyalty(tokenId, basisPoints);

        emit RoyaltyRateSet(tokenId, basisPoints);
    }

    function burn(uint256 tokenId) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (activeLicenseCount[tokenId] > 0) {
            revert HasActiveLicenses(tokenId, activeLicenseCount[tokenId]);
        }
        if (_hasActiveDispute[tokenId]) revert HasActiveDispute(tokenId);

        _burn(tokenId);

        delete activeLicenseCount[tokenId];
        delete _hasActiveDispute[tokenId];
        delete _metadataURIs[tokenId];
    }

    function setDisputeStatus(uint256 tokenId, bool hasDispute) external onlyRole(ARBITRATOR_ROLE) {
        _hasActiveDispute[tokenId] = hasDispute;
        emit DisputeStatusChanged(tokenId, hasDispute);
    }

    function setLicenseTokenContract(address licenseToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (licenseToken == address(0)) revert InvalidContractAddress(licenseToken);
        licenseTokenContract = licenseToken;
        emit LicenseTokenContractSet(licenseToken);
    }

    function setArbitratorContract(address arbitrator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (arbitrator == address(0)) revert InvalidContractAddress(arbitrator);
        arbitratorContract = arbitrator;
        emit ArbitratorContractSet(arbitrator);
    }

    function setRevenueDistributorContract(address distributor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (distributor == address(0)) revert InvalidContractAddress(distributor);
        revenueDistributor = distributor;
        emit RevenueDistributorSet(distributor);
    }

    function updateActiveLicenseCount(uint256 tokenId, int256 delta) external onlyRole(LICENSE_MANAGER_ROLE) {
        if (delta > 0) {
            activeLicenseCount[tokenId] += uint256(delta);
        } else {
            uint256 decrement = uint256(-delta);
            uint256 current = activeLicenseCount[tokenId];
            if (current < decrement) {
                revert LicenseCountUnderflow(tokenId, current, decrement);
            }
            activeLicenseCount[tokenId] -= decrement;
        }
    }

    function hasActiveDispute(uint256 tokenId) external view returns (bool) {
        return _hasActiveDispute[tokenId];
    }

    function setPrivateMetadata(uint256 tokenId, string memory metadata) external whenNotPaused {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        _privateMetadata[tokenId] = metadata;
        emit PrivateMetadataUpdated(tokenId);
    }

    function getPrivateMetadata(uint256 tokenId) external view returns (string memory) {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        return _privateMetadata[tokenId];
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function isWrapped(uint256 tokenId) external view returns (bool) {
        return _wrappedNFTs[tokenId].nftContract != address(0);
    }

    function getWrappedNFT(uint256 tokenId)
        external
        view
        returns (address nftContract, uint256 nftTokenId)
    {
        IIPAsset.WrappedNFT storage wrapped = _wrappedNFTs[tokenId];
        return (wrapped.nftContract, wrapped.nftTokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
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

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
