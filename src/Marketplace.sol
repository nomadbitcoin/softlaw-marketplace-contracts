// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IMarketplace.sol";
import "./interfaces/ILicenseToken.sol";
import "./interfaces/IRevenueDistributor.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract Marketplace is
    IMarketplace,
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 public constant MAX_PENALTY_RATE = 1000;
    uint256 public constant BASIS_POINTS = 10_000;

    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Offer) public offers;
    mapping(bytes32 => uint256) public escrowBalances;
    mapping(uint256 => RecurringPayment) public recurringPayments;

    address public revenueDistributor;
    address public treasury;
    uint256 public platformFeeBasisPoints;
    uint256 public penaltyBasisPointsPerDay;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address _revenueDistributor, uint256 _platformFeeBasisPoints, address _treasury)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        revenueDistributor = _revenueDistributor;
        platformFeeBasisPoints = _platformFeeBasisPoints;
        treasury = _treasury;
        penaltyBasisPointsPerDay = 0;
    }

    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isERC721
    ) external whenNotPaused returns (bytes32) {
        if (price == 0) revert InvalidPrice();

        if (isERC721) {
            if (IERC721(nftContract).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        } else {
            if (IERC1155(nftContract).balanceOf(msg.sender, tokenId) == 0) revert NotTokenOwner();
        }

        bytes32 listingId = keccak256(abi.encodePacked(nftContract, tokenId, msg.sender, block.timestamp));
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            isActive: true,
            isERC721: isERC721
        });
        emit ListingCreated(listingId, msg.sender, nftContract, tokenId, price);
        return listingId;
    }

    function cancelListing(bytes32 listingId) external whenNotPaused {
        Listing storage listing = listings[listingId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.isActive) revert ListingNotActive();

        listing.isActive = false;
        emit ListingCancelled(listingId);
    }

    function buyListing(bytes32 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        if (!listing.isActive) revert ListingNotActive();
        if (msg.value < listing.price) revert InsufficientPayment();

        listing.isActive = false;

        if (!listing.isERC721) {
            uint256 paymentInterval = ILicenseToken(listing.nftContract).getPaymentInterval(listing.tokenId);

            if (paymentInterval > 0) {
                recurringPayments[listing.tokenId] = RecurringPayment({
                    lastPaymentTime: block.timestamp,
                    currentOwner: msg.sender
                });
            }
        }

        uint256 platformFee = (listing.price * platformFeeBasisPoints) / BASIS_POINTS;

        if (listing.isERC721) {
            IERC721(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        } else {
            IERC1155(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId, 1, "");
        }

        uint256 sellerAmount = listing.price - platformFee;

        uint256 ipAssetId;
        if (listing.isERC721) {
            ipAssetId = listing.tokenId;
        } else {
            (ipAssetId,,,,,,,) = ILicenseToken(listing.nftContract).getLicenseInfo(listing.tokenId);
        }

        IRevenueDistributor(revenueDistributor).distributePayment{value: sellerAmount}(ipAssetId, sellerAmount);

        (bool success,) = treasury.call{value: platformFee}("");
        if (!success) revert TransferFailed();

        emit Sale(listingId, msg.sender, listing.seller, listing.price, platformFee, 0);

        if (msg.value > listing.price) {
            (success,) = msg.sender.call{value: msg.value - listing.price}("");
            if (!success) revert TransferFailed();
        }
    }

    function createOffer(
        address nftContract,
        uint256 tokenId,
        uint256 expiryTime
    ) external payable returns (bytes32) {
        bytes32 offerId = keccak256(abi.encodePacked(nftContract, tokenId, msg.sender, block.timestamp));
        offers[offerId] = Offer({
            buyer: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: msg.value,
            isActive: true,
            expiryTime: expiryTime
        });
        escrowBalances[offerId] = msg.value;
        emit OfferCreated(offerId, msg.sender, nftContract, tokenId, msg.value);
        return offerId;
    }

    function acceptOffer(bytes32 offerId) external {
        emit OfferAccepted(offerId, msg.sender);
    }

    function cancelOffer(bytes32 offerId) external {
        offers[offerId].isActive = false;
        emit OfferCancelled(offerId);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
