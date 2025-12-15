// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/IPAsset.sol";
import "../../src/LicenseToken.sol";
import "../../src/Marketplace.sol";
import "../../src/GovernanceArbitrator.sol";
import "../../src/RevenueDistributor.sol";
import "../mocks/MockNFT.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title WrappedNFTUserFlowsTest
 * @notice End-to-end tests for complete wrapped NFT user journeys
 */
contract WrappedNFTUserFlowsTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    GovernanceArbitrator public arbitrator;
    RevenueDistributor public revenueDistributor;
    MockNFT public boredApes;
    MockNFT public cryptoPunks;
    MockNFT public doodles;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public dave = address(5);
    address public eve = address(6);
    address public frank = address(7);
    address public grace = address(8);
    address public treasury = address(9);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementations
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

        // Deploy IPAsset proxy
        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector, "IP Asset", "IPA", admin, address(0), address(0)
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        // Deploy RevenueDistributor
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000, address(ipAsset));

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

        // Deploy GovernanceArbitrator proxy
        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            admin,
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );
        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(address(arbitratorImpl), arbitratorInitData);
        arbitrator = GovernanceArbitrator(address(arbitratorProxy));

        // Deploy Marketplace proxy
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            admin,
            address(revenueDistributor)
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = Marketplace(address(marketplaceProxy));

        // Set contract references
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        ipAsset.setRevenueDistributorContract(address(revenueDistributor));
        licenseToken.setArbitratorContract(address(arbitrator));

        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));

        vm.stopPrank();

        // Deploy mock NFT collections
        boredApes = new MockNFT("Bored Ape Yacht Club", "BAYC");
        cryptoPunks = new MockNFT("CryptoPunks", "PUNK");
        doodles = new MockNFT("Doodles", "DOODLE");

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(dave, 100 ether);
        vm.deal(eve, 100 ether);
        vm.deal(frank, 100 ether);
        vm.deal(grace, 100 ether);
    }

    // ========== E2E Test 1: Complete Wrapped NFT Lifecycle ==========

    function testE2E_CompleteWrappedNFTLifecycle() public {
        // === ACT 1: Wrap and Configure ===
        vm.startPrank(alice);
        uint256 apeTokenId = boredApes.mint(alice);
        boredApes.approve(address(ipAsset), apeTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(boredApes), apeTokenId, "ipfs://bored-ape-1234");

        // Alice configures revenue split (Alice 60%, Bob 40%)
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000;
        shares[1] = 4000;
        ipAsset.configureRevenueSplit(ipTokenId, recipients, shares);

        // Alice sets 15% royalty
        ipAsset.setRoyaltyRate(ipTokenId, 1500);
        vm.stopPrank();

        // === ACT 2: License ===
        vm.startPrank(alice);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            charlie,
            1,
            "ipfs://license-pub",
            "ipfs://license-priv",
            block.timestamp + 30 days,
            "Standard license",
            false,
            0
        );
        vm.stopPrank();

        // Verify Charlie received license
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);
        assertTrue(licenseToken.isActiveLicense(licenseId));

        // === ACT 3: Primary Sale ===
        vm.startPrank(alice);
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 primaryListing = marketplace.createListing(address(ipAsset), ipTokenId, 10 ether, true);
        vm.stopPrank();

        vm.prank(dave);
        marketplace.buyListing{value: 10 ether}(primaryListing);

        // Verify primary sale payments (pull-based system)
        uint256 platformFee = (10 ether * 250) / 10000; // 2.5%
        uint256 remaining = 10 ether - platformFee;
        uint256 aliceShare = (remaining * 6000) / 10000; // 60%
        uint256 bobShare = (remaining * 4000) / 10000; // 40%

        assertEq(revenueDistributor.getBalance(alice), aliceShare);
        assertEq(revenueDistributor.getBalance(bob), bobShare);
        assertEq(ipAsset.ownerOf(ipTokenId), dave);

        // === ACT 4: Secondary Sale ===
        vm.startPrank(dave);
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 secondaryListing = marketplace.createListing(address(ipAsset), ipTokenId, 15 ether, true);
        vm.stopPrank();

        vm.prank(eve);
        marketplace.buyListing{value: 15 ether}(secondaryListing);

        // Verify secondary sale payments (with royalty, pull-based system)
        uint256 secondaryPlatformFee = (15 ether * 250) / 10000; // 0.375 ether
        uint256 secondaryRemaining = 15 ether - secondaryPlatformFee; // 14.625 ether
        uint256 royalty = (15 ether * 1500) / 10000; // 2.25 ether (calculated on FULL amount)
        uint256 sellerAmount = secondaryRemaining - royalty; // 12.375 ether

        uint256 aliceRoyalty = (royalty * 6000) / 10000; // 1.35 ether
        uint256 bobRoyalty = (royalty * 4000) / 10000; // 0.9 ether

        // Total accumulated in revenue distributor
        assertEq(revenueDistributor.getBalance(alice), aliceShare + aliceRoyalty);
        assertEq(revenueDistributor.getBalance(bob), bobShare + bobRoyalty);
        assertEq(revenueDistributor.getBalance(dave), sellerAmount);
        assertEq(ipAsset.ownerOf(ipTokenId), eve);

        // === ACT 5: Unwrap ===
        // Charlie's license expires
        vm.warp(block.timestamp + 31 days);
        vm.prank(charlie);
        licenseToken.markExpired(licenseId);

        assertEq(ipAsset.activeLicenseCount(ipTokenId), 0);

        // Eve unwraps to get original Bored Ape
        vm.prank(eve);
        ipAsset.unwrapNFT(ipTokenId);

        assertEq(boredApes.ownerOf(apeTokenId), eve);
        vm.expectRevert();
        ipAsset.ownerOf(ipTokenId); // IPAsset burned
    }

    // ========== E2E Test 2: Wrapped License Resale Journey ==========

    function testE2E_WrappedLicenseResaleJourney() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 punkTokenId = cryptoPunks.mint(alice);
        cryptoPunks.approve(address(ipAsset), punkTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(cryptoPunks), punkTokenId, "ipfs://punk-metadata");

        // Configure split (Alice 50%, Bob 50%)
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000;
        shares[1] = 5000;
        ipAsset.configureRevenueSplit(ipTokenId, recipients, shares);

        // Set 20% royalty on licenses
        ipAsset.setRoyaltyRate(ipTokenId, 2000);

        // Mint license
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            frank,
            1,
            "ipfs://license-pub",
            "ipfs://license-priv",
            block.timestamp + 60 days,
            "Premium license",
            false,
            0
        );
        vm.stopPrank();

        // === Frank sells license to Grace (primary) ===
        vm.startPrank(frank);
        licenseToken.setApprovalForAll(address(marketplace), true);
        bytes32 primaryListing =
            marketplace.createListing(address(licenseToken), licenseId, 5 ether, false);
        vm.stopPrank();

        vm.prank(grace);
        marketplace.buyListing{value: 5 ether}(primaryListing);

        // Verify Grace got license
        assertEq(licenseToken.balanceOf(grace, licenseId), 1);
        assertEq(licenseToken.balanceOf(frank, licenseId), 0);

        // Primary sale payments to alice and bob from license sale
        uint256 primaryPlatformFee = (5 ether * 250) / 10000;
        uint256 primaryRemaining = 5 ether - primaryPlatformFee;
        uint256 alicePrimaryShare = (primaryRemaining * 5000) / 10000;
        uint256 bobPrimaryShare = (primaryRemaining * 5000) / 10000;

        // === Grace resells license (secondary - royalty applies) ===
        vm.startPrank(grace);
        licenseToken.setApprovalForAll(address(marketplace), true);
        bytes32 secondaryListing =
            marketplace.createListing(address(licenseToken), licenseId, 8 ether, false);
        vm.stopPrank();

        vm.prank(charlie);
        marketplace.buyListing{value: 8 ether}(secondaryListing);

        // Verify royalty distribution on license resale (pull-based system)
        uint256 secondaryPlatformFee = (8 ether * 250) / 10000;
        uint256 secondaryRemaining = 8 ether - secondaryPlatformFee;
        uint256 royalty = (8 ether * 2000) / 10000; // 2 ether (calculated on FULL amount)
        uint256 sellerAmount = secondaryRemaining - royalty;

        uint256 aliceRoyalty = (royalty * 5000) / 10000;
        uint256 bobRoyalty = (royalty * 5000) / 10000;

        // Total accumulated in revenue distributor
        assertEq(revenueDistributor.getBalance(alice), alicePrimaryShare + aliceRoyalty);
        assertEq(revenueDistributor.getBalance(bob), bobPrimaryShare + bobRoyalty);
        assertEq(revenueDistributor.getBalance(grace), sellerAmount);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);
    }

    // ========== E2E Test 3: Multiple Wrapped NFTs Independent Lifecycles ==========

    function testE2E_MultipleWrappedNFTsIndependentLifecycles() public {
        // === Alice wraps CryptoPunk #5555 ===
        vm.startPrank(alice);
        uint256 punkTokenId = cryptoPunks.mint(alice);
        cryptoPunks.approve(address(ipAsset), punkTokenId);
        uint256 ipTokenId1 = ipAsset.wrapNFT(address(cryptoPunks), punkTokenId, "ipfs://punk-5555");

        // Configure 10% royalty
        ipAsset.setRoyaltyRate(ipTokenId1, 1000);

        address[] memory recipients1 = new address[](1);
        recipients1[0] = alice;
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 10000;
        ipAsset.configureRevenueSplit(ipTokenId1, recipients1, shares1);
        vm.stopPrank();

        // === Bob wraps Doodle #7777 ===
        vm.startPrank(bob);
        uint256 doodleTokenId = doodles.mint(bob);
        doodles.approve(address(ipAsset), doodleTokenId);
        uint256 ipTokenId2 = ipAsset.wrapNFT(address(doodles), doodleTokenId, "ipfs://doodle-7777");

        // Configure 20% royalty (different from Alice)
        ipAsset.setRoyaltyRate(ipTokenId2, 2000);

        address[] memory recipients2 = new address[](1);
        recipients2[0] = bob;
        uint256[] memory shares2 = new uint256[](1);
        shares2[0] = 10000;
        ipAsset.configureRevenueSplit(ipTokenId2, recipients2, shares2);
        vm.stopPrank();

        // === Both mint licenses ===
        vm.prank(alice);
        uint256 license1 = ipAsset.mintLicense(
            ipTokenId1,
            charlie,
            1,
            "ipfs://l1-pub",
            "ipfs://l1-priv",
            block.timestamp + 30 days,
            "License 1",
            false,
            0
        );

        vm.prank(bob);
        uint256 license2 = ipAsset.mintLicense(
            ipTokenId2,
            dave,
            1,
            "ipfs://l2-pub",
            "ipfs://l2-priv",
            block.timestamp + 30 days,
            "License 2",
            false,
            0
        );

        // === Both sell on marketplace ===
        vm.startPrank(alice);
        ipAsset.approve(address(marketplace), ipTokenId1);
        bytes32 listing1 = marketplace.createListing(address(ipAsset), ipTokenId1, 5 ether, true);
        vm.stopPrank();

        vm.startPrank(bob);
        ipAsset.approve(address(marketplace), ipTokenId2);
        bytes32 listing2 = marketplace.createListing(address(ipAsset), ipTokenId2, 8 ether, true);
        vm.stopPrank();

        // === Eve buys Alice's NFT ===
        vm.prank(eve);
        marketplace.buyListing{value: 5 ether}(listing1);
        assertEq(ipAsset.ownerOf(ipTokenId1), eve);

        // === Frank buys Bob's NFT ===
        vm.prank(frank);
        marketplace.buyListing{value: 8 ether}(listing2);
        assertEq(ipAsset.ownerOf(ipTokenId2), frank);

        // === Verify no interference between assets ===
        // Get alice and bob balances after primary sales
        uint256 aliceBalance1 = revenueDistributor.getBalance(alice);
        uint256 bobBalance1 = revenueDistributor.getBalance(bob);

        // Eve resells with 10% royalty
        vm.startPrank(eve);
        ipAsset.approve(address(marketplace), ipTokenId1);
        bytes32 resale1 = marketplace.createListing(address(ipAsset), ipTokenId1, 6 ether, true);
        vm.stopPrank();

        vm.prank(grace);
        marketplace.buyListing{value: 6 ether}(resale1);

        uint256 platformFee1 = (6 ether * 250) / 10000;
        uint256 royalty1 = (6 ether * 1000) / 10000; // 10% on FULL amount

        // Alice should receive 10% royalty
        assertEq(revenueDistributor.getBalance(alice), aliceBalance1 + royalty1);

        // Frank resells with 20% royalty
        vm.startPrank(frank);
        ipAsset.approve(address(marketplace), ipTokenId2);
        bytes32 resale2 = marketplace.createListing(address(ipAsset), ipTokenId2, 10 ether, true);
        vm.stopPrank();

        vm.prank(grace);
        marketplace.buyListing{value: 10 ether}(resale2);

        uint256 platformFee2 = (10 ether * 250) / 10000;
        uint256 royalty2 = (10 ether * 2000) / 10000; // 20% on FULL amount

        // Bob should receive 20% royalty
        assertEq(revenueDistributor.getBalance(bob), bobBalance1 + royalty2);

        // === Verify each uses correct royalty rate ===
        assertTrue(ipTokenId1 != ipTokenId2);
        assertTrue(license1 != license2);
    }
}
