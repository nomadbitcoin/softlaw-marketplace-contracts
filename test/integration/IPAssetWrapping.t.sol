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
 * @title IPAssetWrappingIntegrationTest
 * @notice Integration tests for wrapped NFT interactions with other contracts
 */
contract IPAssetWrappingIntegrationTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    GovernanceArbitrator public arbitrator;
    RevenueDistributor public revenueDistributor;
    MockNFT public mockNFT;

    address public admin = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public charlie = address(4);
    address public dave = address(5);
    address public treasury = address(6);

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
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000, address(ipAsset)); // 2.5% platform, 10% royalty

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

        // Deploy mock NFT
        mockNFT = new MockNFT("Mock NFT", "MNFT");

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(dave, 100 ether);
    }

    // ========== Integration Test 1: Wrap and License ==========

    function testIntegration_WrapAndLicense() public {
        // Alice wraps her NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Alice mints a license for the wrapped NFT
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            bob,
            1,
            "ipfs://license-pub",
            "ipfs://license-priv",
            block.timestamp + 30 days,
            "Standard license",
            false,
            0
        );

        vm.stopPrank();

        // Verify license was created
        assertEq(licenseToken.balanceOf(bob, licenseId), 1);
        assertTrue(licenseToken.isActiveLicense(licenseId));
        assertEq(ipAsset.activeLicenseCount(ipTokenId), 1);

        // Verify licensee can access private metadata
        vm.prank(bob);
        string memory privateMetadata = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateMetadata, "ipfs://license-priv");
    }

    // ========== Integration Test 2: Wrap, Configure, and Sell ==========

    function testIntegration_WrapConfigureAndSell() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Alice configures revenue split
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%
        ipAsset.configureRevenueSplit(ipTokenId, recipients, shares);

        // Alice lists on marketplace
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 listingId = marketplace.createListing(address(ipAsset), ipTokenId, 10 ether, true);
        vm.stopPrank();

        // Charlie buys the wrapped IPAsset
        vm.prank(charlie);
        marketplace.buyListing{value: 10 ether}(listingId);

        // Verify ownership transferred
        assertEq(ipAsset.ownerOf(ipTokenId), charlie);

        // Verify payments distributed correctly (pull-based system)
        uint256 platformFee = (10 ether * 250) / 10000; // 2.5%
        uint256 remaining = 10 ether - platformFee;
        uint256 aliceShare = (remaining * 6000) / 10000; // 60%
        uint256 bobShare = (remaining * 4000) / 10000; // 40%

        assertEq(revenueDistributor.getBalance(treasury), platformFee);
        assertEq(revenueDistributor.getBalance(alice), aliceShare);
        assertEq(revenueDistributor.getBalance(bob), bobShare);
    }

    // ========== Integration Test 3: Wrap, License, and Unwrap ==========

    function testIntegration_WrapLicenseAndUnwrap() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Alice mints license with short expiry
        uint256 expiryTime = block.timestamp + 1 days;
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId, bob, 1, "ipfs://pub", "ipfs://priv", expiryTime, "Short license", false, 0
        );
        vm.stopPrank();

        // Verify license is active
        assertTrue(licenseToken.isActiveLicense(licenseId));
        assertEq(ipAsset.activeLicenseCount(ipTokenId), 1);

        // Fast forward past expiry
        vm.warp(expiryTime + 1);

        // Mark license as expired
        vm.prank(bob);
        licenseToken.markExpired(licenseId);

        // Verify license count decremented
        assertEq(ipAsset.activeLicenseCount(ipTokenId), 0);

        // Alice can now unwrap
        vm.prank(alice);
        ipAsset.unwrapNFT(ipTokenId);

        // Verify Alice got her NFT back
        assertEq(mockNFT.ownerOf(nftTokenId), alice);
    }

    // ========== Integration Test 4: Wrapped NFT Revenue Distribution ==========

    function testIntegration_WrappedNFTRevenueDistribution() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Configure revenue split (Alice 70%, Bob 30%)
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000;
        shares[1] = 3000;
        ipAsset.configureRevenueSplit(ipTokenId, recipients, shares);

        // List for sale
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 listingId = marketplace.createListing(address(ipAsset), ipTokenId, 20 ether, true);
        vm.stopPrank();

        // Charlie buys
        vm.prank(charlie);
        marketplace.buyListing{value: 20 ether}(listingId);

        // Verify revenue split (pull-based system)
        uint256 platformFee = (20 ether * 250) / 10000;
        uint256 remaining = 20 ether - platformFee;
        uint256 expectedAlice = (remaining * 7000) / 10000;
        uint256 expectedBob = (remaining * 3000) / 10000;

        assertEq(revenueDistributor.getBalance(alice), expectedAlice);
        assertEq(revenueDistributor.getBalance(bob), expectedBob);
        assertEq(revenueDistributor.getBalance(treasury), platformFee);
    }

    // ========== Integration Test 5: Wrapped NFT Secondary Royalties ==========

    function testIntegration_WrappedNFTSecondaryRoyalties() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Set 15% royalty
        ipAsset.setRoyaltyRate(ipTokenId, 1500);

        // Configure revenue split (Alice 60%, Bob 40%)
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000;
        shares[1] = 4000;
        ipAsset.configureRevenueSplit(ipTokenId, recipients, shares);

        // Alice lists (primary sale)
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 listing1 = marketplace.createListing(address(ipAsset), ipTokenId, 10 ether, true);
        vm.stopPrank();

        // Charlie buys (primary sale - no royalty)
        vm.prank(charlie);
        marketplace.buyListing{value: 10 ether}(listing1);

        // Charlie lists for resale (secondary sale)
        vm.startPrank(charlie);
        ipAsset.approve(address(marketplace), ipTokenId);
        bytes32 listing2 = marketplace.createListing(address(ipAsset), ipTokenId, 15 ether, true);
        vm.stopPrank();

        // Dave buys (secondary sale - royalty applies)
        vm.prank(dave);
        marketplace.buyListing{value: 15 ether}(listing2);

        // Verify royalty distribution (pull-based system)
        // Primary sale (10 ether): platform 0.25, Alice 5.85, Bob 3.9
        // Secondary sale (15 ether): platform 0.375, royalty 2.25 (on full amount), seller gets remaining minus royalty

        uint256 primaryPlatformFee = (10 ether * 250) / 10000; // 0.25 ether
        uint256 primaryRemaining = 10 ether - primaryPlatformFee; // 9.75 ether
        uint256 alicePrimarySale = (primaryRemaining * 6000) / 10000; // 5.85 ether
        uint256 bobPrimarySale = (primaryRemaining * 4000) / 10000; // 3.9 ether

        uint256 secondaryPlatformFee = (15 ether * 250) / 10000; // 0.375 ether
        uint256 secondaryRemaining = 15 ether - secondaryPlatformFee; // 14.625 ether
        uint256 royaltyAmount = (15 ether * 1500) / 10000; // 2.25 ether (calculated on FULL amount)
        uint256 aliceRoyalty = (royaltyAmount * 6000) / 10000; // 1.35 ether
        uint256 bobRoyalty = (royaltyAmount * 4000) / 10000; // 0.9 ether
        uint256 charlieSellerAmount = secondaryRemaining - royaltyAmount; // 12.375 ether

        // Total balances in revenue distributor
        assertEq(revenueDistributor.getBalance(treasury), primaryPlatformFee + secondaryPlatformFee);
        assertEq(revenueDistributor.getBalance(alice), alicePrimarySale + aliceRoyalty);
        assertEq(revenueDistributor.getBalance(bob), bobPrimarySale + bobRoyalty);
        assertEq(revenueDistributor.getBalance(charlie), charlieSellerAmount);
        assertEq(ipAsset.ownerOf(ipTokenId), dave);
    }

    // ========== Integration Test 6: Cannot Unwrap With Active License ==========

    function testIntegration_CannotUnwrapWithActiveLicense() public {
        // Alice wraps NFT
        vm.startPrank(alice);
        uint256 nftTokenId = mockNFT.mint(alice);
        mockNFT.approve(address(ipAsset), nftTokenId);
        uint256 ipTokenId = ipAsset.wrapNFT(address(mockNFT), nftTokenId, "ipfs://wrapped-metadata");

        // Alice mints license
        uint256 expiryTime = block.timestamp + 7 days;
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId, bob, 1, "ipfs://pub", "ipfs://priv", expiryTime, "License", false, 0
        );

        // Try to unwrap - should fail
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveLicenses.selector, ipTokenId, 1));
        ipAsset.unwrapNFT(ipTokenId);
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(expiryTime + 1);

        // Mark as expired
        vm.prank(bob);
        licenseToken.markExpired(licenseId);

        // Now unwrap should succeed
        vm.prank(alice);
        ipAsset.unwrapNFT(ipTokenId);

        // Verify NFT returned
        assertEq(mockNFT.ownerOf(nftTokenId), alice);
    }
}
