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
    uint256 public constant SECONDS_PER_MONTH = 2_592_000;
    uint256 public constant MAX_MISSED_PAYMENTS = 3;
    uint256 public constant PENALTY_GRACE_PERIOD = 3 days;

    mapping(bytes32 => Listing) public listings;
    mapping(bytes32 => Offer) public offers;
    mapping(bytes32 => uint256) public escrow;
    mapping(uint256 => RecurringPayment) public recurring;

    address public revenueDistributor;
    uint256 public penaltyBasisPointsPerMonth;

    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address _revenueDistributor)
        external
        initializer
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        revenueDistributor = _revenueDistributor;
        penaltyBasisPointsPerMonth = 0;
    }

    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isERC721
    ) external whenNotPaused returns (bytes32) {
        if (price == 0) revert InvalidPrice();
        if (!_isOwner(nftContract, tokenId, msg.sender, isERC721)) revert NotTokenOwner();

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
                recurring[listing.tokenId] = RecurringPayment({
                    lastPaymentTime: block.timestamp,
                    currentOwner: msg.sender,
                    baseAmount: listing.price
                });
            }
            (ipAssetId,,,,,,,) = ILicenseToken(listing.nftContract).getLicenseInfo(listing.tokenId);
        }

        _transferNFT(listing.nftContract, listing.seller, msg.sender, listing.tokenId, listing.isERC721);
        _distributePayment(ipAssetId, listing.price);

        emit Sale(listingId, msg.sender, listing.seller, listing.price);

        if (msg.value > listing.price) {
            _refund(msg.sender, msg.value - listing.price);
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
        escrow[offerId] = msg.value;
        emit OfferCreated(offerId, msg.sender, nftContract, tokenId, msg.value);
        return offerId;
    }

    function acceptOffer(bytes32 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];
        if (!offer.isActive) revert OfferNotActive();
        if (block.timestamp >= offer.expiryTime) revert OfferExpired();

        offer.isActive = false;
        escrow[offerId] = 0;

        bool isERC721;
        try IERC721(offer.nftContract).supportsInterface(0x80ac58cd) returns (bool supported) {
            isERC721 = supported;
        } catch {
            isERC721 = false;
        }

        if (!_isOwner(offer.nftContract, offer.tokenId, msg.sender, isERC721)) revert NotTokenOwner();

        uint256 ipAssetId;
        if (isERC721) {
            IERC721(offer.nftContract).safeTransferFrom(msg.sender, offer.buyer, offer.tokenId);
            ipAssetId = offer.tokenId;
        } else {
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

    function _distributePayment(uint256 ipAssetId, uint256 totalAmount) internal {
        IRevenueDistributor(revenueDistributor).distributePayment{value: totalAmount}(ipAssetId, totalAmount);
    }

    function cancelOffer(bytes32 offerId) external {
        Offer storage offer = offers[offerId];
        if (!offer.isActive) revert OfferNotActive();
        if (offer.buyer != msg.sender) revert NotOfferBuyer();

        offer.isActive = false;
        uint256 refundAmount = escrow[offerId];
        escrow[offerId] = 0;

        _refund(msg.sender, refundAmount);

        emit OfferCancelled(offerId);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setPenaltyRate(uint256 basisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (basisPoints > MAX_PENALTY_RATE) revert InvalidPenaltyRate();
        penaltyBasisPointsPerMonth = basisPoints;
        emit PenaltyRateUpdated(basisPoints);
    }

    function getMissedPayments(address licenseContract, uint256 licenseId) public view returns (uint256) {
        uint256 interval = ILicenseToken(licenseContract).getPaymentInterval(licenseId);
        uint256 lastPaid = recurring[licenseId].lastPaymentTime;
        return _missedPayments(lastPaid, interval);
    }


    function getRecurringPaymentAmount(uint256 licenseId) public view returns (uint256) {
        return recurring[licenseId].baseAmount;
    }

    function calculatePenalty(address licenseContract, uint256 licenseId) public view returns (uint256) {
        uint256 interval = ILicenseToken(licenseContract).getPaymentInterval(licenseId);
        if (interval == 0) return 0;

        uint256 baseAmount = getRecurringPaymentAmount(licenseId);
        uint256 lastPaid = recurring[licenseId].lastPaymentTime;
        if (lastPaid == 0) return 0;

        uint256 nextDue = lastPaid + interval;
        if (block.timestamp <= nextDue) return 0;

        // Check if within grace period
        uint256 gracePeriodEnd = nextDue + PENALTY_GRACE_PERIOD;
        if (block.timestamp <= gracePeriodEnd) return 0;

        // Get per-license penalty rate (monthly rate in basis points)
        uint16 penaltyRateBPS = ILicenseToken(licenseContract).getPenaltyRate(licenseId);

        // Calculate penalty only on time after grace period
        // Formula: penalty = baseAmount * monthlyRateBPS * daysLate / 10000 / 30
        // Using 30 days as average month length for pro-rata daily calculation
        uint256 secondsOverdue = block.timestamp - gracePeriodEnd;
        uint256 daysLate = secondsOverdue / 1 days;
        return (baseAmount * penaltyRateBPS * daysLate) / (BASIS_POINTS * 30);
    }

    function getTotalPaymentDue(address licenseContract, uint256 licenseId)
        public
        view
        returns (uint256 baseAmount, uint256 penalty, uint256 total)
    {
        baseAmount = getRecurringPaymentAmount(licenseId);
        penalty = calculatePenalty(licenseContract, licenseId);
        total = baseAmount + penalty;
    }

    function makeRecurringPayment(address licenseContract, uint256 licenseId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        _validateRecurringPayment(licenseContract, licenseId);

        (uint256 baseAmount, uint256 penalty, uint256 totalAmount) = getTotalPaymentDue(licenseContract, licenseId);

        if (msg.value < totalAmount) revert InsufficientPayment();

        _updatePaymentState(licenseId);

        (uint256 ipAssetId,,,,,,,) = ILicenseToken(licenseContract).getLicenseInfo(licenseId);
        _distributePayment(ipAssetId, totalAmount);

        emit RecurringPaymentMade(licenseId, msg.sender, baseAmount, penalty, block.timestamp);

        if (msg.value > totalAmount) {
            _refund(msg.sender, msg.value - totalAmount);
        }
    }

    function _validateRecurringPayment(address licenseContract, uint256 licenseId) internal {
        uint256 interval = ILicenseToken(licenseContract).getPaymentInterval(licenseId);
        if (interval == 0) revert NotRecurringLicense();

        if (!ILicenseToken(licenseContract).isActiveLicense(licenseId)) revert LicenseNotActive();

        if (IERC1155(licenseContract).balanceOf(msg.sender, licenseId) == 0) revert NotTokenOwner();

        uint256 missed = getMissedPayments(licenseContract, licenseId);
        if (missed > MAX_MISSED_PAYMENTS) {
            ILicenseToken(licenseContract).revokeForMissedPayments(licenseId, missed);
            revert LicenseRevokedForMissedPayments();
        }
    }

    function _updatePaymentState(uint256 licenseId) internal {
        recurring[licenseId].lastPaymentTime = block.timestamp;
        recurring[licenseId].currentOwner = msg.sender;
    }


    function _missedPayments(uint256 lastPaid, uint256 interval) internal view returns (uint256) {
        if (lastPaid == 0 || interval == 0) return 0;
        uint256 timeSinceLastPayment = block.timestamp - lastPaid;
        return timeSinceLastPayment / interval;
    }

    function _isOwner(address nftContract, uint256 tokenId, address owner, bool isERC721) internal view returns (bool) {
        if (isERC721) {
            return IERC721(nftContract).ownerOf(tokenId) == owner;
        } else {
            return IERC1155(nftContract).balanceOf(owner, tokenId) > 0;
        }
    }

    function _refund(address to, uint256 amount) internal {
        if (amount > 0) {
            (bool success,) = to.call{value: amount}("");
            if (!success) revert TransferFailed();
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }
}
