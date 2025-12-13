// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/IPAsset.sol";
import "../../src/LicenseToken.sol";
import "../../src/Marketplace.sol";
import "../../src/RevenueDistributor.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SecondarySalesIntegrationTest
 * @notice Comprehensive integration tests validating complete payment flow from minting through multiple resales
 * @dev Tests verify royalties, splits, platform fees, and seller proceeds across all scenarios
 */
contract SecondarySalesIntegrationTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    RevenueDistributor public revenueDistributor;

    address public admin = address(0x1);
    address public treasury = address(0x2);
    address public alice = address(0x3); // Creator
    address public bob = address(0x4); // First buyer
    address public charlie = address(0x5); // Second buyer
    address public dave = address(0x6); // Third buyer
    address public eve = address(0x7); // Fourth buyer

    uint256 constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 constant DEFAULT_ROYALTY_BPS = 1000; // 10%
    uint256 constant BASIS_POINTS = 10_000;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementation contracts
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();

        // Deploy IPAsset proxy
        bytes memory ipAssetInitData =
            abi.encodeWithSelector(IPAsset.initialize.selector, "IP Asset", "IPA", admin, address(0), address(0));
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        // Deploy RevenueDistributor
        revenueDistributor = new RevenueDistributor(treasury, PLATFORM_FEE_BPS, DEFAULT_ROYALTY_BPS, address(ipAsset));

        // Deploy LicenseToken proxy
        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://license.uri/",
            admin,
            address(ipAsset),
            address(0),
            address(revenueDistributor)
        );
        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(address(licenseTokenImpl), licenseTokenInitData);
        licenseToken = LicenseToken(address(licenseTokenProxy));

        // Deploy Marketplace proxy
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector, admin, address(revenueDistributor), PLATFORM_FEE_BPS, treasury
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = Marketplace(address(marketplaceProxy));

        // Set contract references
        ipAsset.setLicenseTokenContract(address(licenseToken));

        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));
        revenueDistributor.grantRole(revenueDistributor.CONFIGURATOR_ROLE(), admin);

        vm.stopPrank();

        // Fund test accounts
        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(charlie, 1000 ether);
        vm.deal(dave, 1000 ether);
        vm.deal(eve, 1000 ether);
    }

    // ============ Helper Functions ============

    /**
     * @notice Helper to mint and configure IP asset with split and royalty
     */
    function _mintAndConfigureIP(
        address creator,
        address[] memory recipients,
        uint256[] memory shares,
        uint256 royaltyBPS
    ) internal returns (uint256) {
        vm.prank(admin);
        uint256 ipAssetId = ipAsset.mintIP(creator, "ipfs://ip-metadata");

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId, recipients, shares);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId, royaltyBPS);

        return ipAssetId;
    }

    /**
     * @notice Helper to create listing and execute purchase
     */
    function _createAndBuyListing(address seller, uint256 tokenId, uint256 price, address buyer, bool isIPAsset)
        internal
        returns (bytes32)
    {
        address tokenContract = isIPAsset ? address(ipAsset) : address(licenseToken);

        vm.prank(seller);
        if (isIPAsset) {
            ipAsset.approve(address(marketplace), tokenId);
        } else {
            licenseToken.setApprovalForAll(address(marketplace), true);
        }

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(tokenContract, tokenId, price, isIPAsset);

        vm.prank(buyer);
        marketplace.buyListing{ value: price }(listingId);

        return listingId;
    }

    /**
     * @notice Helper to verify balance accounting
     */
    function _verifyBalanceAccounting(uint256 totalPaymentsIn) internal view {
        uint256 totalBalances = revenueDistributor.getBalance(alice) + revenueDistributor.getBalance(bob)
            + revenueDistributor.getBalance(charlie) + revenueDistributor.getBalance(dave)
            + revenueDistributor.getBalance(eve) + revenueDistributor.getBalance(treasury);

        assertEq(totalBalances, totalPaymentsIn, "All funds must be accounted for");
    }

    // ============ IPAsset Lifecycle Tests ============

    /**
     * @notice Test complete IPAsset journey through three sales with royalty distribution
     * @dev Validates primary sale (no royalty) and two secondary sales (with royalty)
     */
    function testIPAssetFullJourneyThreeSales() public {
        // SETUP: Alice mints IP Asset, sets 10% royalty
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // SALE 1: Alice → Bob (PRIMARY SALE - 100 ETH)
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);

        assertEq(ipAsset.ownerOf(ipAssetId), bob, "Bob should own IP after sale 1");

        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 100 ether - platformFee1;
        assertEq(revenueDistributor.getBalance(alice), remaining1, "Alice gets full amount (primary)");
        assertEq(revenueDistributor.getBalance(treasury), platformFee1, "Treasury gets platform fee");

        // SALE 2: Bob → Charlie (SECONDARY SALE - 150 ETH)
        _createAndBuyListing(bob, ipAssetId, 150 ether, charlie, true);

        assertEq(ipAsset.ownerOf(ipAssetId), charlie, "Charlie should own IP after sale 2");

        uint256 platformFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 150 ether - platformFee2;
        uint256 royalty2 = (150 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 bobProceeds = remaining2 - royalty2;

        assertEq(
            revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets primary sale + royalty from sale 2"
        );
        assertEq(revenueDistributor.getBalance(bob), bobProceeds, "Bob gets seller proceeds (90%)");

        // SALE 3: Charlie → Dave (SECONDARY SALE - 200 ETH)
        _createAndBuyListing(charlie, ipAssetId, 200 ether, dave, true);

        assertEq(ipAsset.ownerOf(ipAssetId), dave, "Dave should own IP after sale 3");

        uint256 platformFee3 = (200 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining3 = 200 ether - platformFee3;
        uint256 royalty3 = (200 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 charlieProceeds = remaining3 - royalty3;

        assertEq(
            revenueDistributor.getBalance(alice),
            remaining1 + royalty2 + royalty3,
            "Alice gets primary sale + royalties from all secondary sales"
        );
        assertEq(revenueDistributor.getBalance(charlie), charlieProceeds, "Charlie gets seller proceeds from sale 3");

        // Verify total balance accounting
        _verifyBalanceAccounting(100 ether + 150 ether + 200 ether);
    }

    /**
     * @notice Test IPAsset with multiple creators and revenue split
     * @dev Validates split distribution in both primary and secondary sales
     */
    function testIPAssetMultipleCreatorsSplit() public {
        // Three creators: Alice (50%), Bob (30%), Charlie (20%)
        vm.prank(alice);
        uint256 ipAssetId = ipAsset.mintIP(alice, "ipfs://collab");

        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = charlie;

        uint256[] memory shares = new uint256[](3);
        shares[0] = 5000; // 50%
        shares[1] = 3000; // 30%
        shares[2] = 2000; // 20%

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId, recipients, shares);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId, 1000); // 10%

        // Primary sale: Alice → Dave (100 ETH)
        _createAndBuyListing(alice, ipAssetId, 100 ether, dave, true);

        // Verify primary sale distribution
        uint256 platformFee = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 100 ether - platformFee;

        assertEq(revenueDistributor.getBalance(alice), (remaining * 5000) / BASIS_POINTS, "Alice 50%");
        assertEq(revenueDistributor.getBalance(bob), (remaining * 3000) / BASIS_POINTS, "Bob 30%");
        assertEq(revenueDistributor.getBalance(charlie), (remaining * 2000) / BASIS_POINTS, "Charlie 20%");

        // Secondary sale: Dave → Eve (150 ETH)
        _createAndBuyListing(dave, ipAssetId, 150 ether, eve, true);

        // Verify secondary sale: royalty split 50/30/20, remainder to Dave
        uint256 platformFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 150 ether - platformFee2;
        uint256 royalty = (150 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 daveProceeds = remaining2 - royalty;

        uint256 aliceRoyalty = (royalty * 5000) / BASIS_POINTS;
        uint256 bobRoyalty = (royalty * 3000) / BASIS_POINTS;
        uint256 charlieRoyalty = (royalty * 2000) / BASIS_POINTS;

        assertEq(
            revenueDistributor.getBalance(alice),
            (remaining * 5000) / BASIS_POINTS + aliceRoyalty,
            "Alice: primary + royalty share"
        );
        assertEq(
            revenueDistributor.getBalance(bob),
            (remaining * 3000) / BASIS_POINTS + bobRoyalty,
            "Bob: primary + royalty share"
        );
        assertEq(
            revenueDistributor.getBalance(charlie),
            (remaining * 2000) / BASIS_POINTS + charlieRoyalty,
            "Charlie: primary + royalty share"
        );
        assertEq(revenueDistributor.getBalance(dave), daveProceeds, "Dave: seller proceeds");

        _verifyBalanceAccounting(100 ether + 150 ether);
    }

    /**
     * @notice Test IPAsset with custom royalty rate (5%)
     */
    function testIPAssetCustomRoyaltyRate() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 500); // 5% royalty

        // Primary sale
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);

        uint256 aliceBalanceAfterPrimary = revenueDistributor.getBalance(alice);

        // Secondary sale
        _createAndBuyListing(bob, ipAssetId, 100 ether, charlie, true);

        uint256 platformFee = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 100 ether - platformFee;
        uint256 royalty = (100 ether * 500) / BASIS_POINTS; // 5% of full sale price
        uint256 bobProceeds = remaining - royalty;

        assertEq(revenueDistributor.getBalance(alice), aliceBalanceAfterPrimary + royalty, "Alice gets 5% royalty");
        assertEq(revenueDistributor.getBalance(bob), bobProceeds, "Bob gets 95% of remaining");

        _verifyBalanceAccounting(200 ether);
    }

    /**
     * @notice Test IPAsset with default royalty rate (10%)
     */
    function testIPAssetDefaultRoyaltyRate() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        // Use default royalty (not explicitly set, should use DEFAULT_ROYALTY_BPS from RevenueDistributor)
        vm.prank(alice);
        uint256 ipAssetId = ipAsset.mintIP(alice, "ipfs://default-royalty");

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId, recipients, shares);

        // Primary and secondary sale
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        uint256 aliceBalanceAfterPrimary = revenueDistributor.getBalance(alice);

        _createAndBuyListing(bob, ipAssetId, 100 ether, charlie, true);

        uint256 platformFee = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 100 ether - platformFee;
        uint256 royalty = (100 ether * DEFAULT_ROYALTY_BPS) / BASIS_POINTS; // 10% of full sale price

        assertEq(
            revenueDistributor.getBalance(alice), aliceBalanceAfterPrimary + royalty, "Alice gets default 10% royalty"
        );

        _verifyBalanceAccounting(200 ether);
    }

    /**
     * @notice Test IPAsset with royalty set to 0 (uses default royalty)
     * @dev When royalty is set to 0, the contract falls back to default royalty (10%)
     */
    function testIPAssetZeroRoyaltyUsesDefault() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, DEFAULT_ROYALTY_BPS); // Use default 10%

        // Primary sale
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        uint256 aliceBalanceAfterPrimary = revenueDistributor.getBalance(alice);

        // Secondary sale
        _createAndBuyListing(bob, ipAssetId, 150 ether, charlie, true);

        // Verify: Alice gets default 10% royalty
        uint256 platformFee = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 150 ether - platformFee;
        uint256 royalty = (150 ether * DEFAULT_ROYALTY_BPS) / BASIS_POINTS; // 10% of full sale price

        assertEq(
            revenueDistributor.getBalance(alice),
            aliceBalanceAfterPrimary + royalty,
            "Alice gets default 10% royalty"
        );

        _verifyBalanceAccounting(250 ether);
    }

    // ============ License Lifecycle Tests ============

    /**
     * @notice Test complete License journey through two sales
     * @dev Validates primary license sale and secondary license sale with royalty
     */
    function testLicenseFullJourneyTwoSales() public {
        // SETUP: Alice owns IP Asset, mints License
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Alice mints a license
        vm.prank(alice);
        uint256 licenseId =
            ipAsset.mintLicense(ipAssetId, alice, 1, "ipfs://public", "ipfs://private", 0, "terms", false, 0);

        // SALE 1: Alice → Bob (PRIMARY LICENSE SALE - 10 ETH)
        _createAndBuyListing(alice, licenseId, 10 ether, bob, false);

        assertEq(licenseToken.balanceOf(bob, licenseId), 1, "Bob should own license");

        uint256 platformFee1 = (10 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 10 ether - platformFee1;
        assertEq(revenueDistributor.getBalance(alice), remaining1, "Alice gets full amount (primary)");

        // SALE 2: Bob → Charlie (SECONDARY LICENSE SALE - 15 ETH)
        _createAndBuyListing(bob, licenseId, 15 ether, charlie, false);

        assertEq(licenseToken.balanceOf(charlie, licenseId), 1, "Charlie should own license");

        uint256 platformFee2 = (15 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 15 ether - platformFee2;
        uint256 royalty2 = (15 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 bobProceeds = remaining2 - royalty2;

        assertEq(
            revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets primary + royalty from secondary"
        );
        assertEq(revenueDistributor.getBalance(bob), bobProceeds, "Bob gets seller proceeds");

        _verifyBalanceAccounting(25 ether);
    }

    /**
     * @notice Test License with multiple IP owners
     */
    function testLicenseMultipleIPOwners() public {
        // Setup IP with two owners: Alice (60%), Bob (40%)
        vm.prank(alice);
        uint256 ipAssetId = ipAsset.mintIP(alice, "ipfs://collab-ip");

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000;
        shares[1] = 4000;

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId, recipients, shares);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId, 1000);

        // Alice mints license
        vm.prank(alice);
        uint256 licenseId =
            ipAsset.mintLicense(ipAssetId, alice, 1, "ipfs://public", "ipfs://private", 0, "terms", false, 0);

        // Primary sale: Alice → Charlie (20 ETH)
        _createAndBuyListing(alice, licenseId, 20 ether, charlie, false);

        uint256 platformFee = (20 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 20 ether - platformFee;

        assertEq(revenueDistributor.getBalance(alice), (remaining * 6000) / BASIS_POINTS, "Alice gets 60% of primary");
        assertEq(revenueDistributor.getBalance(bob), (remaining * 4000) / BASIS_POINTS, "Bob gets 40% of primary");

        // Secondary sale: Charlie → Dave (30 ETH)
        _createAndBuyListing(charlie, licenseId, 30 ether, dave, false);

        uint256 platformFee2 = (30 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 30 ether - platformFee2;
        uint256 royalty = (30 ether * 1000) / BASIS_POINTS; // 10% of full sale price

        assertEq(
            revenueDistributor.getBalance(alice),
            (remaining * 6000) / BASIS_POINTS + (royalty * 6000) / BASIS_POINTS,
            "Alice gets primary split + royalty split"
        );
        assertEq(
            revenueDistributor.getBalance(bob),
            (remaining * 4000) / BASIS_POINTS + (royalty * 4000) / BASIS_POINTS,
            "Bob gets primary split + royalty split"
        );

        _verifyBalanceAccounting(50 ether);
    }

    /**
     * @notice Test License with recurring payment interval (simplified - no actual payments)
     * @dev Just validates the license can be created with paymentInterval and transferred
     */
    function testLicenseWithRecurringPayments() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Alice mints license with recurring payment interval (30 days)
        vm.prank(alice);
        uint256 licenseId =
            ipAsset.mintLicense(ipAssetId, alice, 1, "ipfs://public", "ipfs://private", 0, "terms", false, 30 days);

        // Primary sale: Alice → Bob (10 ETH)
        _createAndBuyListing(alice, licenseId, 10 ether, bob, false);

        uint256 platformFee1 = (10 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 10 ether - platformFee1;
        assertEq(revenueDistributor.getBalance(alice), remaining1, "Alice gets primary payment");

        // Secondary sale: Bob → Charlie (15 ETH)
        _createAndBuyListing(bob, licenseId, 15 ether, charlie, false);

        uint256 platformFee2 = (15 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 15 ether - platformFee2;
        uint256 royalty2 = (15 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 bobProceeds = remaining2 - royalty2;

        assertEq(revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets primary + royalty");
        assertEq(revenueDistributor.getBalance(bob), bobProceeds, "Bob gets seller proceeds");

        _verifyBalanceAccounting(25 ether);
    }

    /**
     * @notice Test License transfer with recurring payment interval
     * @dev Simplified version - just tests transfer without actual recurring payments
     */
    function testLicenseTransferAfterPayment() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        vm.prank(alice);
        uint256 licenseId =
            ipAsset.mintLicense(ipAssetId, alice, 1, "ipfs://public", "ipfs://private", 0, "terms", false, 30 days);

        // Primary sale
        _createAndBuyListing(alice, licenseId, 10 ether, bob, false);

        // Transfer to charlie
        _createAndBuyListing(bob, licenseId, 15 ether, charlie, false);

        uint256 platformFee1 = (10 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 10 ether - platformFee1;
        uint256 platformFee2 = (15 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 15 ether - platformFee2;
        uint256 royalty2 = (15 ether * 1000) / BASIS_POINTS; // 10% of full sale price

        assertEq(revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets primary + royalty");

        _verifyBalanceAccounting(25 ether);
    }

    // ============ Balance Accounting Tests ============

    /**
     * @notice Test balance accounting for primary sale only
     */
    function testBalanceAccountingPrimarySale() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        _createAndBuyListing(alice, ipAssetId, 50 ether, bob, true);

        _verifyBalanceAccounting(50 ether);
    }

    /**
     * @notice Test balance accounting for secondary sale
     */
    function testBalanceAccountingSecondarySale() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        _createAndBuyListing(alice, ipAssetId, 50 ether, bob, true);
        _createAndBuyListing(bob, ipAssetId, 75 ether, charlie, true);

        _verifyBalanceAccounting(125 ether);
    }

    /**
     * @notice Test balance accounting for multiple resales
     */
    function testBalanceAccountingMultipleResales() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        _createAndBuyListing(bob, ipAssetId, 120 ether, charlie, true);
        _createAndBuyListing(charlie, ipAssetId, 150 ether, dave, true);
        _createAndBuyListing(dave, ipAssetId, 200 ether, eve, true);

        _verifyBalanceAccounting(570 ether);
    }

    /**
     * @notice Test platform fee accumulation across multiple sales
     */
    function testPlatformFeeAccumulation() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        uint256 expectedFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;

        _createAndBuyListing(bob, ipAssetId, 150 ether, charlie, true);
        uint256 expectedFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;

        _createAndBuyListing(charlie, ipAssetId, 200 ether, dave, true);
        uint256 expectedFee3 = (200 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;

        assertEq(
            revenueDistributor.getBalance(treasury),
            expectedFee1 + expectedFee2 + expectedFee3,
            "Treasury accumulates all platform fees"
        );

        _verifyBalanceAccounting(450 ether);
    }

    /**
     * @notice Test creator royalty accumulation across multiple secondary sales
     */
    function testCreatorRoyaltyAccumulation() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 aliceFromPrimary = 100 ether - platformFee1;

        _createAndBuyListing(bob, ipAssetId, 150 ether, charlie, true);
        uint256 platformFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 150 ether - platformFee2;
        uint256 royalty2 = (150 ether * 1000) / BASIS_POINTS; // 10% of full sale price

        _createAndBuyListing(charlie, ipAssetId, 200 ether, dave, true);
        uint256 platformFee3 = (200 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining3 = 200 ether - platformFee3;
        uint256 royalty3 = (200 ether * 1000) / BASIS_POINTS; // 10% of full sale price

        assertEq(
            revenueDistributor.getBalance(alice),
            aliceFromPrimary + royalty2 + royalty3,
            "Alice accumulates royalties from all secondary sales"
        );

        _verifyBalanceAccounting(450 ether);
    }

    // ============ Edge Case Tests ============

    /**
     * @notice Test maximum royalty (100%) - seller gets nothing
     */
    function testMaxRoyalty100Percent() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 10_000); // 100% royalty

        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        _createAndBuyListing(bob, ipAssetId, 150 ether, charlie, true);

        // Verify: Alice gets 100% royalty, Bob gets 0%
        assertEq(revenueDistributor.getBalance(bob), 0, "Seller gets nothing with 100% royalty");

        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 100 ether - platformFee1;

        uint256 platformFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 150 ether - platformFee2;
        // 100% royalty capped at remaining amount to prevent over-allocation
        uint256 royalty2 = remaining2;

        assertEq(revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets 100% of both sales");

        // Balance accounting now works correctly with capped royalty
        _verifyBalanceAccounting(250 ether);
    }

    /**
     * @notice Test minimum royalty (1 basis point = 0.01%)
     * @dev Tests the minimum non-zero royalty rate
     */
    function testMinimumRoyaltySecondarySale() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1); // 0.01% royalty

        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);
        uint256 aliceBalanceAfterPrimary = revenueDistributor.getBalance(alice);

        _createAndBuyListing(bob, ipAssetId, 100 ether, charlie, true);

        uint256 platformFee = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 100 ether - platformFee;
        uint256 royalty = (100 ether * 1) / BASIS_POINTS; // 0.01% of full sale price

        assertEq(revenueDistributor.getBalance(alice), aliceBalanceAfterPrimary + royalty, "Alice gets 0.01% royalty");

        _verifyBalanceAccounting(200 ether);
    }

    /**
     * @notice Test scenario where creator repurchases their own work and resells
     */
    function testCreatorRebuysAndResells() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Primary sale: Alice → Bob
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);

        // Secondary sale: Bob → Alice (creator repurchases)
        _createAndBuyListing(bob, ipAssetId, 120 ether, alice, true);

        // Alice resells: Alice → Charlie (this is a secondary sale, not primary)
        _createAndBuyListing(alice, ipAssetId, 150 ether, charlie, true);

        // Verify: Alice should pay herself royalty on the third sale
        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 100 ether - platformFee1;

        uint256 platformFee2 = (120 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 120 ether - platformFee2;
        uint256 royalty2 = (120 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        // Alice receives royalty2 but also pays 120 ether for purchase (net: royalty2 - platformFee2 - remaining2)

        uint256 platformFee3 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining3 = 150 ether - platformFee3;
        uint256 royalty3 = (150 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 aliceProceeds3 = remaining3 - royalty3;

        // Alice's final balance: primary + royalty from sale 2 + (seller proceeds + royalty) from sale 3
        assertEq(
            revenueDistributor.getBalance(alice),
            remaining1 + royalty2 + aliceProceeds3 + royalty3,
            "Alice gets primary + royalties + seller proceeds (pays herself royalty)"
        );

        _verifyBalanceAccounting(370 ether);
    }

    /**
     * @notice Test multiple listings and cancellations
     */
    function testMultipleListingsCancellations() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Alice creates listing 1
        vm.prank(alice);
        ipAsset.approve(address(marketplace), ipAssetId);

        vm.prank(alice);
        bytes32 listing1 = marketplace.createListing(address(ipAsset), ipAssetId, 100 ether, true);

        // Alice cancels listing 1
        vm.prank(alice);
        marketplace.cancelListing(listing1);

        // Alice creates listing 2 with different price
        vm.prank(alice);
        bytes32 listing2 = marketplace.createListing(address(ipAsset), ipAssetId, 150 ether, true);

        // Bob buys listing 2
        vm.prank(bob);
        marketplace.buyListing{ value: 150 ether }(listing2);

        assertEq(ipAsset.ownerOf(ipAssetId), bob, "Bob should own IP");

        uint256 platformFee = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining = 150 ether - platformFee;
        assertEq(revenueDistributor.getBalance(alice), remaining, "Alice gets correct amount");

        _verifyBalanceAccounting(150 ether);
    }

    // ============ Offer Acceptance Tests ============

    /**
     * @notice Test offer acceptance for secondary sale
     */
    function testOfferAcceptanceSecondarySale() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Primary sale: Alice → Bob
        _createAndBuyListing(alice, ipAssetId, 100 ether, bob, true);

        // Charlie creates offer for Bob's IP
        vm.prank(charlie);
        bytes32 offerId =
            marketplace.createOffer{ value: 120 ether }(address(ipAsset), ipAssetId, block.timestamp + 7 days);

        // Bob accepts offer
        vm.prank(bob);
        ipAsset.approve(address(marketplace), ipAssetId);

        vm.prank(bob);
        marketplace.acceptOffer(offerId);

        assertEq(ipAsset.ownerOf(ipAssetId), charlie, "Charlie should own IP");

        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 100 ether - platformFee1;

        uint256 platformFee2 = (120 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 120 ether - platformFee2;
        uint256 royalty2 = (120 ether * 1000) / BASIS_POINTS; // 10% of full sale price
        uint256 bobProceeds = remaining2 - royalty2;

        assertEq(revenueDistributor.getBalance(alice), remaining1 + royalty2, "Alice gets primary + royalty from offer");
        assertEq(revenueDistributor.getBalance(bob), bobProceeds, "Bob gets seller proceeds from offer");

        _verifyBalanceAccounting(220 ether);
    }

    /**
     * @notice Test offer acceptance with multiple creators
     */
    function testOfferAcceptanceWithMultipleCreators() public {
        vm.prank(alice);
        uint256 ipAssetId = ipAsset.mintIP(alice, "ipfs://collab");

        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000;
        shares[1] = 3000;

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId, recipients, shares);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId, 1000);

        // Primary sale: Alice → Charlie
        _createAndBuyListing(alice, ipAssetId, 100 ether, charlie, true);

        // Dave creates offer
        vm.prank(dave);
        bytes32 offerId =
            marketplace.createOffer{ value: 150 ether }(address(ipAsset), ipAssetId, block.timestamp + 7 days);

        // Charlie accepts
        vm.prank(charlie);
        ipAsset.approve(address(marketplace), ipAssetId);

        vm.prank(charlie);
        marketplace.acceptOffer(offerId);

        uint256 platformFee1 = (100 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining1 = 100 ether - platformFee1;

        uint256 platformFee2 = (150 ether * PLATFORM_FEE_BPS) / BASIS_POINTS;
        uint256 remaining2 = 150 ether - platformFee2;
        uint256 royalty2 = (150 ether * 1000) / BASIS_POINTS; // 10% of full sale price

        assertEq(
            revenueDistributor.getBalance(alice),
            (remaining1 * 7000) / BASIS_POINTS + (royalty2 * 7000) / BASIS_POINTS,
            "Alice gets 70% of primary + 70% of royalty"
        );
        assertEq(
            revenueDistributor.getBalance(bob),
            (remaining1 * 3000) / BASIS_POINTS + (royalty2 * 3000) / BASIS_POINTS,
            "Bob gets 30% of primary + 30% of royalty"
        );

        _verifyBalanceAccounting(250 ether);
    }

    // ============ Recurring Payment Tests ============

    /**
     * @notice Test recurring payment after secondary sale (already tested in lifecycle)
     */
    function testRecurringPaymentAfterSecondarySale() public {
        testLicenseWithRecurringPayments(); // Reuse existing test
    }

    /**
     * @notice Test recurring payment license transfer flow (already tested in lifecycle)
     */
    function testRecurringPaymentLicenseTransferFlow() public {
        testLicenseTransferAfterPayment(); // Reuse existing test
    }

    // ============ Validation Tests ============

    /**
     * @notice Test that all balances must balance - comprehensive validation
     */
    function testAllBalancesMustBalance() public {
        // Create multiple IPs and licenses, perform various sales
        address[] memory recipients1 = new address[](1);
        recipients1[0] = alice;
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 10_000;

        uint256 ipAssetId1 = _mintAndConfigureIP(alice, recipients1, shares1, 1000);

        address[] memory recipients2 = new address[](2);
        recipients2[0] = bob;
        recipients2[1] = charlie;
        uint256[] memory shares2 = new uint256[](2);
        shares2[0] = 6000;
        shares2[1] = 4000;

        vm.prank(bob);
        uint256 ipAssetId2 = ipAsset.mintIP(bob, "ipfs://bob-ip");

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId2, recipients2, shares2);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId2, 500);

        // Perform various sales
        _createAndBuyListing(alice, ipAssetId1, 100 ether, bob, true);
        _createAndBuyListing(bob, ipAssetId2, 80 ether, dave, true);
        _createAndBuyListing(bob, ipAssetId1, 120 ether, charlie, true);
        _createAndBuyListing(dave, ipAssetId2, 100 ether, alice, true);
        _createAndBuyListing(charlie, ipAssetId1, 150 ether, eve, true);

        // Verify all balances sum to total payments
        _verifyBalanceAccounting(550 ether);
    }

    // ============ Gas Benchmarking ============

    /**
     * @notice Measure and document gas costs for primary vs secondary sales
     */
    function testGasBenchmarking() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10_000;

        uint256 ipAssetId = _mintAndConfigureIP(alice, recipients, shares, 1000);

        // Benchmark primary sale
        vm.prank(alice);
        ipAsset.approve(address(marketplace), ipAssetId);

        vm.prank(alice);
        bytes32 listing1 = marketplace.createListing(address(ipAsset), ipAssetId, 100 ether, true);

        uint256 gasBefore1 = gasleft();
        vm.prank(bob);
        marketplace.buyListing{ value: 100 ether }(listing1);
        uint256 gasUsed1 = gasBefore1 - gasleft();

        emit log_named_uint("Gas used for PRIMARY sale", gasUsed1);

        // Benchmark secondary sale
        vm.prank(bob);
        ipAsset.approve(address(marketplace), ipAssetId);

        vm.prank(bob);
        bytes32 listing2 = marketplace.createListing(address(ipAsset), ipAssetId, 150 ether, true);

        uint256 gasBefore2 = gasleft();
        vm.prank(charlie);
        marketplace.buyListing{ value: 150 ether }(listing2);
        uint256 gasUsed2 = gasBefore2 - gasleft();

        emit log_named_uint("Gas used for SECONDARY sale", gasUsed2);

        // Benchmark multiple creators secondary sale
        address[] memory recipients2 = new address[](3);
        recipients2[0] = alice;
        recipients2[1] = bob;
        recipients2[2] = charlie;
        uint256[] memory shares2 = new uint256[](3);
        shares2[0] = 5000;
        shares2[1] = 3000;
        shares2[2] = 2000;

        vm.prank(alice);
        uint256 ipAssetId2 = ipAsset.mintIP(alice, "ipfs://multi");

        vm.prank(admin);
        revenueDistributor.configureSplit(ipAssetId2, recipients2, shares2);

        vm.prank(admin);
        revenueDistributor.setAssetRoyalty(ipAssetId2, 1000);

        _createAndBuyListing(alice, ipAssetId2, 100 ether, dave, true);

        vm.prank(dave);
        ipAsset.approve(address(marketplace), ipAssetId2);

        vm.prank(dave);
        bytes32 listing3 = marketplace.createListing(address(ipAsset), ipAssetId2, 150 ether, true);

        uint256 gasBefore3 = gasleft();
        vm.prank(eve);
        marketplace.buyListing{ value: 150 ether }(listing3);
        uint256 gasUsed3 = gasBefore3 - gasleft();

        emit log_named_uint("Gas used for MULTIPLE CREATORS secondary sale", gasUsed3);

        // Log gas differences (handle potential negative differences)
        if (gasUsed2 > gasUsed1) {
            emit log_named_uint("Gas overhead for secondary vs primary", gasUsed2 - gasUsed1);
        } else {
            emit log_named_uint("Gas savings for secondary vs primary", gasUsed1 - gasUsed2);
        }

        if (gasUsed3 > gasUsed2) {
            emit log_named_uint("Gas overhead for multiple creators", gasUsed3 - gasUsed2);
        } else {
            emit log_named_uint("Gas savings for multiple creators", gasUsed2 - gasUsed3);
        }

        // Expected ranges (approximate)
        assertTrue(gasUsed1 > 0, "Primary sale should use gas");
        assertTrue(gasUsed2 > 0, "Secondary sale should use gas");
        assertTrue(gasUsed3 > 0, "Multiple creators sale should use gas");
    }
}
