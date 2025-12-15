// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/IPAsset.sol";
import "../../src/LicenseToken.sol";
import "../../src/Marketplace.sol";
import "../../src/RevenueDistributor.sol";
import "../../src/GovernanceArbitrator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title E2ETestBase
 * @notice Base contract for all end-to-end user flow tests
 * @dev - All admin setup happens in setUp() only
 *      - NO admin operations during tests (production-like)
 *      - All tests use regular user accounts only
 */
abstract contract E2ETestBase is Test {
    // ============ Contracts ============
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    RevenueDistributor public revenueDistributor;
    GovernanceArbitrator public arbitrator;

    // ============ Actors ============
    // Admin - ONLY used in setUp(), never in tests
    address internal admin = address(0xAD);

    // System accounts
    address internal treasury = address(0x1);
    address internal arbitratorRole = address(0x2);

    // User accounts (production-like)
    address internal alice = address(0x100); // Primary creator
    address internal bob = address(0x101); // Buyer/Licensee
    address internal charlie = address(0x102); // Secondary buyer
    address internal dave = address(0x103); // Tertiary buyer
    address internal eve = address(0x104); // Collaborator
    address internal frank = address(0x105); // Another collaborator
    address internal grace = address(0x106); // Licensee
    address internal henry = address(0x107); // Buyer
    address internal ivy = address(0x108); // Licensee
    address internal jack = address(0x109); // Buyer

    // ============ Constants ============
    uint256 internal constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 internal constant DEFAULT_ROYALTY_BPS = 1000; // 10%
    uint256 internal constant BASIS_POINTS = 10_000;
    uint256 internal constant GRACE_PERIOD = 3 days;
    uint256 internal constant MAX_MISSED_PAYMENTS = 3;
    uint256 internal constant DEFAULT_PENALTY_RATE = 500; // 5%

    // ============ Events for Testing ============
    event IPMinted(uint256 indexed tokenId, address indexed creator);
    event LicenseMinted(uint256 indexed licenseId, uint256 indexed ipTokenId);
    event ListingCreated(bytes32 indexed listingId, address indexed seller);
    event ListingSold(bytes32 indexed listingId, address indexed buyer);
    event OfferCreated(bytes32 indexed offerId, address indexed buyer);
    event OfferAccepted(bytes32 indexed offerId, address indexed seller);
    event RecurringPaymentMade(address indexed payer, uint256 indexed licenseId);
    event DisputeSubmitted(uint256 indexed disputeId, uint256 indexed licenseId);

    // ============ Setup ============

    function setUp() public virtual {
        vm.startPrank(admin);

        _deployContracts();
        _setupReferences();
        _grantRoles();

        vm.stopPrank();

        _fundAccounts();
    }

    function _deployContracts() internal {
        // Deploy implementation contracts
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

        // Deploy IPAsset proxy
        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "SoftLaw IP Asset",
            "SLIPA",
            admin,
            address(0), // License contract set later
            address(0)  // Arbitrator set later
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        // Deploy RevenueDistributor (non-upgradeable)
        revenueDistributor = new RevenueDistributor(
            treasury,
            PLATFORM_FEE_BPS,
            DEFAULT_ROYALTY_BPS,
            address(ipAsset)
        );

        // Deploy LicenseToken proxy
        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://softlaw.license/",
            admin,
            address(ipAsset),
            address(0), // Arbitrator set later
            address(revenueDistributor)
        );
        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(
            address(licenseTokenImpl),
            licenseTokenInitData
        );
        licenseToken = LicenseToken(address(licenseTokenProxy));

        // Deploy Marketplace proxy
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            admin,
            address(revenueDistributor),
            PLATFORM_FEE_BPS,
            treasury
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(
            address(marketplaceImpl),
            marketplaceInitData
        );
        marketplace = Marketplace(address(marketplaceProxy));

        // Deploy GovernanceArbitrator proxy
        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            admin,
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );
        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(
            address(arbitratorImpl),
            arbitratorInitData
        );
        arbitrator = GovernanceArbitrator(address(arbitratorProxy));
    }

    function _setupReferences() internal {
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        ipAsset.setRevenueDistributorContract(address(revenueDistributor));
        licenseToken.setArbitratorContract(address(arbitrator));
    }

    function _grantRoles() internal {
        // IPAsset roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));

        // LicenseToken roles
        licenseToken.grantRole(licenseToken.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));

        // GovernanceArbitrator roles
        arbitrator.grantRole(arbitrator.ARBITRATOR_ROLE(), arbitratorRole);

        // RevenueDistributor roles
        revenueDistributor.grantRole(revenueDistributor.CONFIGURATOR_ROLE(), admin);
        revenueDistributor.grantRole(revenueDistributor.CONFIGURATOR_ROLE(), address(ipAsset));
    }

    function _fundAccounts() internal {
        // Fund all user accounts with 1000 ETH each for testing
        address[10] memory users = [
            alice, bob, charlie, dave, eve,
            frank, grace, henry, ivy, jack
        ];

        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 1000 ether);
        }
    }

    // ============ Helper Functions ============

    /**
     * @notice Mint an IP asset as a user
     * @dev No admin required - any user can mint their own IP
     */
    function _mintIP(address creator, string memory metadataURI) internal returns (uint256) {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, metadataURI);
        return tokenId;
    }

    /**
     * @notice Configure revenue split for an IP asset
     */
    function _configureRevenueSplit(
        uint256 tokenId,
        address owner,
        address[] memory recipients,
        uint256[] memory shares
    ) internal {
        vm.prank(owner);
        ipAsset.configureRevenueSplit(tokenId, recipients, shares);
    }

    /**
     * @notice Set royalty rate for an IP asset
     */
    function _setRoyaltyRate(uint256 tokenId, address owner, uint256 royaltyBPS) internal {
        vm.prank(owner);
        ipAsset.setRoyaltyRate(tokenId, royaltyBPS);
    }

    /**
     * @notice Mint a license for an IP asset
     */
    function _mintLicense(
        uint256 ipTokenId,
        address ipOwner,
        address licensee,
        uint256 supply,
        uint256 expiryTime,
        bool exclusive,
        uint256 paymentInterval,
        uint256 pricePerInterval,
        string memory publicMetadataURI,
        string memory privateMetadataURI
    ) internal returns (uint256) {
        vm.prank(ipOwner);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            supply,
            publicMetadataURI,
            privateMetadataURI,
            expiryTime,
            "license terms",
            exclusive,
            paymentInterval
        );
        return licenseId;
    }

    /**
     * @notice Create a marketplace listing
     */
    function _createListing(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isERC721
    ) internal returns (bytes32) {
        vm.startPrank(seller);

        // Approve marketplace
        if (isERC721) {
            IPAsset(nftContract).approve(address(marketplace), tokenId);
        } else {
            LicenseToken(nftContract).setApprovalForAll(address(marketplace), true);
        }

        bytes32 listingId = marketplace.createListing(nftContract, tokenId, price, isERC721);
        vm.stopPrank();

        return listingId;
    }

    /**
     * @notice Buy a marketplace listing
     */
    function _buyListing(address buyer, bytes32 listingId, uint256 price) internal {
        vm.prank(buyer);
        marketplace.buyListing{value: price}(listingId);
    }

    /**
     * @notice Create a marketplace offer
     */
    function _createOffer(
        address buyer,
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 expiryTime
    ) internal returns (bytes32) {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: price}(
            nftContract,
            tokenId,
            expiryTime
        );
        return offerId;
    }

    /**
     * @notice Accept a marketplace offer
     */
    function _acceptOffer(address seller, bytes32 offerId, address nftContract, bool isERC721, uint256 tokenId) internal {
        vm.startPrank(seller);

        // Approve marketplace
        if (isERC721) {
            IPAsset(nftContract).approve(address(marketplace), tokenId);
        } else {
            LicenseToken(nftContract).setApprovalForAll(address(marketplace), true);
        }

        marketplace.acceptOffer(offerId);
        vm.stopPrank();
    }

    /**
     * @notice Make a recurring payment for a license
     */
    function _makeRecurringPayment(address payer, uint256 licenseId) internal returns (uint256 totalDue) {
        (, , totalDue) = marketplace.getTotalPaymentDue(address(licenseToken), licenseId);

        vm.prank(payer);
        marketplace.makeRecurringPayment{value: totalDue}(address(licenseToken), licenseId);
    }

    /**
     * @notice Submit a dispute
     */
    function _submitDispute(
        address disputant,
        uint256 licenseId,
        string memory reason,
        string memory proofURI
    ) internal returns (uint256) {
        vm.prank(disputant);
        uint256 disputeId = arbitrator.submitDispute(licenseId, reason, proofURI);
        return disputeId;
    }

    /**
     * @notice Mark a license as expired
     */
    function _markExpired(address caller, uint256 licenseId) internal {
        vm.prank(caller);
        licenseToken.markExpired(licenseId);
    }

    /**
     * @notice Withdraw accumulated revenue
     */
    function _withdraw(address recipient) internal returns (uint256) {
        uint256 balance = revenueDistributor.getBalance(recipient);

        vm.prank(recipient);
        revenueDistributor.withdraw();

        return balance;
    }

    /**
     * @notice Grant private metadata access
     */
    function _grantPrivateAccess(address holder, uint256 licenseId, address account) internal {
        vm.prank(holder);
        licenseToken.grantPrivateAccess(licenseId, account);
    }

    /**
     * @notice Transfer IP asset
     */
    function _transferIP(address from, address to, uint256 tokenId) internal {
        vm.prank(from);
        ipAsset.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @notice Transfer licenses
     */
    function _transferLicense(address from, address to, uint256 licenseId, uint256 amount) internal {
        vm.prank(from);
        licenseToken.safeTransferFrom(from, to, licenseId, amount, "");
    }

    /**
     * @notice Advance time by specified duration
     */
    function _advanceTime(uint256 duration) internal {
        vm.warp(block.timestamp + duration);
    }

    /**
     * @notice Get current timestamp
     */
    function _now() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Helper to create simple revenue split (single recipient)
     */
    function _simpleSplit(address recipient) internal pure returns (address[] memory, uint256[] memory) {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient;

        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000; // 100%

        return (recipients, shares);
    }

    /**
     * @notice Helper to create two-way revenue split
     */
    function _twoWaySplit(
        address recipient1,
        uint256 share1,
        address recipient2,
        uint256 share2
    ) internal pure returns (address[] memory, uint256[] memory) {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = share1;
        shares[1] = share2;

        return (recipients, shares);
    }

    /**
     * @notice Helper to create three-way revenue split
     */
    function _threeWaySplit(
        address recipient1,
        uint256 share1,
        address recipient2,
        uint256 share2,
        address recipient3,
        uint256 share3
    ) internal pure returns (address[] memory, uint256[] memory) {
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;

        uint256[] memory shares = new uint256[](3);
        shares[0] = share1;
        shares[1] = share2;
        shares[2] = share3;

        return (recipients, shares);
    }

    /**
     * @notice Calculate expected platform fee
     */
    function _platformFee(uint256 amount) internal pure returns (uint256) {
        return (amount * PLATFORM_FEE_BPS) / BASIS_POINTS;
    }

    /**
     * @notice Calculate expected royalty
     */
    function _royalty(uint256 amount, uint256 royaltyBPS) internal pure returns (uint256) {
        return (amount * royaltyBPS) / BASIS_POINTS;
    }

    /**
     * @notice Calculate penalty for late payment
     */
    function _penalty(uint256 baseAmount, uint256 penaltyRate, uint256 daysLate) internal pure returns (uint256) {
        return (baseAmount * penaltyRate * daysLate) / (BASIS_POINTS * 365);
    }
}
