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

        uint256 ipAssetId;
        if (listing.isERC721) {
            ipAssetId = listing.tokenId;
        } else {
            uint256 paymentInterval = ILicenseToken(listing.nftContract).getPaymentInterval(listing.tokenId);
            if (paymentInterval > 0) {
                recurringPayments[listing.tokenId] = RecurringPayment({
                    lastPaymentTime: block.timestamp,
                    currentOwner: msg.sender
                });
            }
            (ipAssetId,,,,,,,) = ILicenseToken(listing.nftContract).getLicenseInfo(listing.tokenId);
        }

        _transferNFT(listing.nftContract, listing.seller, msg.sender, listing.tokenId, listing.isERC721);
        _distributePayment(ipAssetId, listing.price);

        emit Sale(listingId, msg.sender, listing.seller, listing.price, (listing.price * platformFeeBasisPoints) / BASIS_POINTS, 0);

        if (msg.value > listing.price) {
            (bool success,) = msg.sender.call{value: msg.value - listing.price}("");
            if (!success) revert TransferFailed();
        }
    }

    function createOffer(
        address nftContract,
        uint256 tokenId,
        uint256 expiryTime
    ) external payable whenNotPaused returns (bytes32) {
        if (msg.value == 0) revert InsufficientPayment();

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

    function acceptOffer(bytes32 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];
        if (!offer.isActive) revert OfferNotActive();
        if (block.timestamp >= offer.expiryTime) revert OfferExpired();

        offer.isActive = false;
        escrowBalances[offerId] = 0;

        bool isERC721;
        try IERC721(offer.nftContract).supportsInterface(0x80ac58cd) returns (bool supported) {
            isERC721 = supported;
        } catch {
            isERC721 = false;
        }

        uint256 ipAssetId;
        if (isERC721) {
            if (IERC721(offer.nftContract).ownerOf(offer.tokenId) != msg.sender) revert NotTokenOwner();
            IERC721(offer.nftContract).safeTransferFrom(msg.sender, offer.buyer, offer.tokenId);
            ipAssetId = offer.tokenId;
        } else {
            if (IERC1155(offer.nftContract).balanceOf(msg.sender, offer.tokenId) == 0) revert NotTokenOwner();
            IERC1155(offer.nftContract).safeTransferFrom(msg.sender, offer.buyer, offer.tokenId, 1, "");
            (ipAssetId,,,,,,,) = ILicenseToken(offer.nftContract).getLicenseInfo(offer.tokenId);
        }

        _distributePayment(ipAssetId, offer.price);

        emit OfferAccepted(offerId, msg.sender);
    }

    function _transferNFT(
        address nftContract,
        address from,
        address to,
        uint256 tokenId,
        bool isERC721
    ) private {
        if (isERC721) {
            IERC721(nftContract).safeTransferFrom(from, to, tokenId);
        } else {
            IERC1155(nftContract).safeTransferFrom(from, to, tokenId, 1, "");
        }
    }

    function _distributePayment(uint256 ipAssetId, uint256 totalAmount) private {
        uint256 platformFee = (totalAmount * platformFeeBasisPoints) / BASIS_POINTS;
        uint256 sellerAmount = totalAmount - platformFee;

        IRevenueDistributor(revenueDistributor).distributePayment{value: sellerAmount}(ipAssetId, sellerAmount);

        (bool success,) = treasury.call{value: platformFee}("");
        if (!success) revert TransferFailed();
    }

    function cancelOffer(bytes32 offerId) external {
        Offer storage offer = offers[offerId];
        if (!offer.isActive) revert OfferNotActive();
        if (offer.buyer != msg.sender) revert NotOfferBuyer();

        offer.isActive = false;
        uint256 refundAmount = escrowBalances[offerId];
        escrowBalances[offerId] = 0;

        (bool success,) = msg.sender.call{value: refundAmount}("");
        if (!success) revert TransferFailed();

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
