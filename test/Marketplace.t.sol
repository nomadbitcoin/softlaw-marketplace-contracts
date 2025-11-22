// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Marketplace.sol";
import "../src/interfaces/IMarketplace.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/base/ERC1967Proxy.sol";

contract MarketplaceTest is Test {
    Marketplace public marketplace;
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    RevenueDistributor public revenueDistributor;
    GovernanceArbitrator public arbitrator;
    
    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public other = address(4);
    address public treasury = address(5);
    
    uint256 public ipTokenId;
    uint256 public licenseId;
    
    event ListingCreated(
        bytes32 indexed listingId,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    event ListingCancelled(bytes32 indexed listingId);
    event OfferCreated(
        bytes32 indexed offerId,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    event OfferAccepted(bytes32 indexed offerId, address indexed seller);
    event OfferCancelled(bytes32 indexed offerId);
    event Sale(
        bytes32 indexed saleId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );
    
    function setUp() public {
        vm.startPrank(admin);

        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset",
            "IPA",
            admin,
            address(0),
            address(0)
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        revenueDistributor = new RevenueDistributor(treasury, 250, 1000, address(ipAsset));
        
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
        
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            admin,
            address(revenueDistributor)
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = Marketplace(address(marketplaceProxy));
        
        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            admin,
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );
        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(address(arbitratorImpl), arbitratorInitData);
        arbitrator = GovernanceArbitrator(address(arbitratorProxy));
        
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        licenseToken.setArbitratorContract(address(arbitrator));
        
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        
        vm.stopPrank();

        vm.prank(seller);
        ipTokenId = ipAsset.mintIP(seller, "ipfs://metadata");
        
        vm.prank(seller);
        licenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            5,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);

        vm.deal(buyer, 100 ether);
        vm.deal(other, 100 ether);
    }

    function testOwnerCanCreateListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        vm.expectEmit(false, true, false, true);
        emit ListingCreated(
            bytes32(0),
            seller,
            address(ipAsset),
            ipTokenId,
            1 ether
        );
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );

        (address listedSeller,,,,bool isActive,) = marketplace.listings(listingId);
        assertEq(listedSeller, seller);
        assertTrue(isActive);
    }
    
    function testNonOwnerCannotCreateListing() public {
        vm.prank(other);
        vm.expectRevert(IMarketplace.NotTokenOwner.selector);
        marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
    }

    function testCannotCreateListingWithZeroPrice() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        vm.expectRevert(IMarketplace.InvalidPrice.selector);
        marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            0,
            true
        );
    }
    
    function testCanCreateListingWithValidPrice() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
        
        (,,,uint256 price,,) = marketplace.listings(listingId);
        assertEq(price, 1 ether);
    }

    function testSellerCanCancelListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
        
        vm.prank(seller);
        vm.expectEmit(true, false, false, false);
        emit ListingCancelled(listingId);
        marketplace.cancelListing(listingId);
        
        (,,,,bool isActive,) = marketplace.listings(listingId);
        assertFalse(isActive);
    }
    
    function testNonSellerCannotCancelListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );

        vm.prank(other);
        vm.expectRevert(IMarketplace.NotSeller.selector);
        marketplace.cancelListing(listingId);
    }

    function testAnyoneCanCreateOffer() public {
        vm.prank(buyer);
        vm.expectEmit(false, true, false, true);
        emit OfferCreated(
            bytes32(0), // We don't know the exact offerId beforehand
            buyer,
            address(ipAsset),
            ipTokenId,
            0.5 ether
        );
        bytes32 offerId = marketplace.createOffer{value: 0.5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        (address offerBuyer,,,,bool isActive,) = marketplace.offers(offerId);
        assertEq(offerBuyer, buyer);
        assertTrue(isActive);
    }
    
    function testCanCreateOfferForNonListedAsset() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 0.5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        (address offerBuyer,,,,bool isActive,) = marketplace.offers(offerId);
        assertEq(offerBuyer, buyer);
        assertTrue(isActive);
    }

    function testOfferLocksFundsInEscrow() public {
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 0.5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        assertEq(buyer.balance, buyerBalanceBefore - 0.5 ether);
        assertEq(marketplace.escrow(offerId), 0.5 ether);
    }
    
    function testCannotCreateOfferWithoutFunds() public {
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InsufficientPayment.selector);
        marketplace.createOffer{value: 0}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
    }

    function testOwnerCanAcceptOffer() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        vm.expectEmit(true, true, false, false);
        emit OfferAccepted(offerId, seller);
        marketplace.acceptOffer(offerId);
        
        assertEq(ipAsset.ownerOf(ipTokenId), buyer);
    }
    
    function testNonOwnerCannotAcceptOffer() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        vm.prank(other);
        vm.expectRevert(IMarketplace.NotTokenOwner.selector);
        marketplace.acceptOffer(offerId);
    }

    function testCannotAcceptExpiredOffer() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 1 days
        );

        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);

        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        vm.expectRevert(IMarketplace.OfferExpired.selector);
        marketplace.acceptOffer(offerId);
    }
    
    function testCanAcceptOfferBeforeExpiry() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        vm.warp(block.timestamp + 3 days);
        
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        marketplace.acceptOffer(offerId);
        
        assertEq(ipAsset.ownerOf(ipTokenId), buyer);
    }

    function testBuyerCanCancelOffer() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.prank(buyer);
        vm.expectEmit(true, false, false, false);
        emit OfferCancelled(offerId);
        marketplace.cancelOffer(offerId);
        
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
        (,,,,bool isActive,) = marketplace.offers(offerId);
        assertFalse(isActive);
    }
    
    function testNonBuyerCannotCancelOffer() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        vm.prank(other);
        vm.expectRevert(IMarketplace.NotOfferBuyer.selector);
        marketplace.cancelOffer(offerId);
    }

    function testEscrowRefundedOnCancel() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        assertEq(marketplace.escrow(offerId), 1 ether);

        vm.prank(buyer);
        marketplace.cancelOffer(offerId);

        assertEq(marketplace.escrow(offerId), 0);
    }

    function testBuyListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
        
        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);
        
        assertEq(ipAsset.ownerOf(ipTokenId), buyer);
    }
    
    function testCannotBuyListingWithInsufficientFunds() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );

        vm.prank(buyer);
        vm.expectRevert(IMarketplace.InsufficientPayment.selector);
        marketplace.buyListing{value: 0.5 ether}(listingId);
    }
    
    function testCannotBuyInactiveListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(buyer);
        vm.expectRevert(IMarketplace.ListingNotActive.selector);
        marketplace.buyListing{value: 1 ether}(listingId);
    }
    
    function testListingERC1155License() public {
        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            licenseId,
            0.1 ether,
            false // ERC1155
        );
        
        (,address nftContract,,,bool isActive,) = marketplace.listings(listingId);
        assertEq(nftContract, address(licenseToken));
        assertTrue(isActive);
    }
    
    function testBuyERC1155License() public {
        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            licenseId,
            0.1 ether,
            false
        );
        
        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);
        
        assertEq(licenseToken.balanceOf(buyer, licenseId), 1);
    }
    
    function testPlatformFeeDeduction() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Platform fee is 2.5% = 0.025 ether
        // Fee is held in RevenueDistributor, treasury can withdraw it
        uint256 treasuryBalance = revenueDistributor.getBalance(treasury);
        assertEq(treasuryBalance, 0.025 ether);

        // Treasury can withdraw the fee
        vm.prank(treasury);
        revenueDistributor.withdraw();
        assertEq(treasury.balance, 0.025 ether);
    }
    
    function testCannotCreateListingWhenPaused() public {
        vm.prank(admin);
        marketplace.pause();
        
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        vm.expectRevert();
        marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
    }
    
    function testCannotBuyListingWhenPaused() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
        
        vm.prank(admin);
        marketplace.pause();
        
        vm.prank(buyer);
        vm.expectRevert();
        marketplace.buyListing{value: 1 ether}(listingId);
    }
    
    function testMultipleOffersForSameAsset() public {
        vm.prank(buyer);
        bytes32 offerId1 = marketplace.createOffer{value: 0.5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        vm.prank(other);
        bytes32 offerId2 = marketplace.createOffer{value: 0.8 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        assertTrue(offerId1 != offerId2);

        // Seller can accept the higher offer
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        marketplace.acceptOffer(offerId2);

        assertEq(ipAsset.ownerOf(ipTokenId), other);
    }

    function testRecurringPaymentTrackingInitialized() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        (uint256 lastPaymentTime, address currentOwner, uint256 baseAmount) =
            marketplace.recurring(recurringLicenseId);
        assertEq(lastPaymentTime, block.timestamp);
        assertEq(currentOwner, buyer);
        assertEq(baseAmount, 0.1 ether);
    }

    function testNoTrackingForONE_TIMELicense() public {
        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            licenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        (uint256 lastPaymentTime,,) = marketplace.recurring(licenseId);
        assertEq(lastPaymentTime, 0);
    }

    function testGetMissedPaymentsCalculation() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 60 days);

        uint256 missed = marketplace.getMissedPayments(address(licenseToken), recurringLicenseId);
        assertEq(missed, 2);
    }

    function testMakeRecurringPaymentOnTime() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 29 days);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);

        (uint256 lastPaymentTime,,) = marketplace.recurring(recurringLicenseId);
        assertEq(lastPaymentTime, block.timestamp);
        assertEq(buyer.balance, buyerBalanceBefore - 0.1 ether);
    }

    function testMakeRecurringPaymentLate() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 32 days);

        // 2 days late = 2 * 86400 seconds overdue
        uint256 secondsOverdue = 2 days;
        uint256 penalty = (0.1 ether * 500 * secondsOverdue) / (10000 * 2592000);
        uint256 totalAmount = 0.1 ether + penalty;

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: totalAmount}(address(licenseToken), recurringLicenseId);

        (uint256 lastPaymentTime,,) = marketplace.recurring(recurringLicenseId);
        assertEq(lastPaymentTime, block.timestamp);
    }

    function testCannotMakeRecurringPaymentForONE_TIME() public {
        vm.prank(buyer);
        vm.expectRevert(IMarketplace.NotRecurringLicense.selector);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), licenseId);
    }

    function testAutoRevokeAfterThreeMissedPayments() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.startPrank(admin);
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));
        vm.stopPrank();

        vm.warp(block.timestamp + 121 days);

        uint256 missedBeforeCall = marketplace.getMissedPayments(address(licenseToken), recurringLicenseId);
        assertEq(missedBeforeCall, 4);

        vm.prank(buyer);
        vm.expectRevert(IMarketplace.LicenseRevokedForMissedPayments.selector);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);
    }

    function testCannotMakePaymentForRevokedLicense() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.startPrank(admin);
        licenseToken.grantRole(licenseToken.ARBITRATOR_ROLE(), admin);
        licenseToken.revokeLicense(recurringLicenseId, "test revocation");
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert(IMarketplace.LicenseNotActive.selector);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);
    }

    function testCannotPayForExpiredLicense() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 60 days,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 61 days);

        vm.prank(buyer);
        licenseToken.markExpired(recurringLicenseId);

        vm.prank(buyer);
        vm.expectRevert(IMarketplace.LicenseNotActive.selector);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyCalculationAccuracy() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.warp(block.timestamp + 37 days);

        // 7 days late = 7 * 86400 seconds overdue
        uint256 secondsOverdue = 7 days;
        uint256 expectedPenalty = (1 ether * 500 * secondsOverdue) / (10000 * 2592000);
        uint256 totalExpected = 1 ether + expectedPenalty;

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: totalExpected}(address(licenseToken), recurringLicenseId);

        assertEq(buyer.balance, buyerBalanceBefore - totalExpected);
    }

    function testNewOwnerCanMakePayment() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.prank(buyer);
        licenseToken.safeTransferFrom(buyer, other, recurringLicenseId, 1, "");

        vm.warp(block.timestamp + 31 days);

        vm.prank(other);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);

        (, address currentOwner,) = marketplace.recurring(recurringLicenseId);
        assertEq(currentOwner, other);
    }

    function testEarlyPaymentAllowed() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 15 days);

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: 0.1 ether}(address(licenseToken), recurringLicenseId);

        (uint256 lastPaymentTime,,) = marketplace.recurring(recurringLicenseId);
        assertEq(lastPaymentTime, block.timestamp);
    }

    function testExcessPaymentRefunded() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            0.1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        vm.warp(block.timestamp + 31 days);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: 0.5 ether}(address(licenseToken), recurringLicenseId);

        uint256 refundedAmount = 0.5 ether - 0.1 ether;
        assertGt(buyer.balance, buyerBalanceBefore - 0.2 ether);
    }

    function testSetPenaltyRate() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(100);

        assertEq(marketplace.penaltyBasisPointsPerMonth(), 100);
    }

    function testCannotSetPenaltyRateAboveMax() public {
        vm.prank(admin);
        vm.expectRevert(IMarketplace.InvalidPenaltyRate.selector);
        marketplace.setPenaltyRate(1001);  // Max is 1000 (10% per month)
    }


    function testGetTotalPaymentDueHelper() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Check on time - no penalty
        (uint256 baseAmount, uint256 penalty, uint256 total) =
            marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);

        assertEq(baseAmount, 1 ether);
        assertEq(penalty, 0);
        assertEq(total, 1 ether);

        // Warp 7 days late
        vm.warp(block.timestamp + 37 days);

        (baseAmount, penalty, total) =
            marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);

        assertEq(baseAmount, 1 ether);
        uint256 secondsOverdue = 7 days;
        uint256 expectedPenalty = (1 ether * 500 * secondsOverdue) / (10000 * 2592000);
        assertEq(penalty, expectedPenalty);
        assertEq(total, 1 ether + expectedPenalty);

        // Frontend can now use this exact amount
        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: total}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyCalculationWithPartialDay() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Warp to 30 days + 1.5 days late (36 hours)
        vm.warp(block.timestamp + 30 days + 36 hours);

        // Calculate penalty for 1.5 days (36 hours = 129600 seconds)
        uint256 secondsOverdue = 36 hours;
        uint256 expectedPenalty = (1 ether * 500 * secondsOverdue) / (10000 * 2592000);

        uint256 actualPenalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(actualPenalty, expectedPenalty);

        // Verify payment works with partial day penalty
        (,uint256 penalty, uint256 total) = marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);
        assertEq(penalty, expectedPenalty);

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: total}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyCalculationWithRandomBlockTime() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Random time: 30 days + 3 days + 7 hours + 23 minutes + 47 seconds
        uint256 randomOverdue = 3 days + 7 hours + 23 minutes + 47 seconds;
        vm.warp(block.timestamp + 30 days + randomOverdue);

        // Calculate penalty for exact seconds overdue
        uint256 expectedPenalty = (1 ether * 500 * randomOverdue) / (10000 * 2592000);

        uint256 actualPenalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(actualPenalty, expectedPenalty);

        // Verify the pro-rata calculation is accurate
        (uint256 baseAmount, uint256 penalty, uint256 total) = marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);
        assertEq(baseAmount, 1 ether);
        assertEq(penalty, expectedPenalty);
        assertEq(total, 1 ether + expectedPenalty);

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: total}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyCalculationWithSingleHour() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Just 1 hour late
        vm.warp(block.timestamp + 30 days + 1 hours);

        uint256 secondsOverdue = 3600; // 1 hour in seconds
        uint256 expectedPenalty = (1 ether * 500 * secondsOverdue) / (10000 * 2592000);

        uint256 actualPenalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(actualPenalty, expectedPenalty);

        // Even 1 hour late should have a penalty
        assertGt(actualPenalty, 0);

        (,, uint256 total) = marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: total}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyCalculationWithArbitrarySeconds() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Arbitrary time: 12345 seconds late (about 3.4 hours)
        uint256 arbitraryOverdue = 12345;
        vm.warp(block.timestamp + 30 days + arbitraryOverdue);

        uint256 expectedPenalty = (1 ether * 500 * arbitraryOverdue) / (10000 * 2592000);

        uint256 actualPenalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(actualPenalty, expectedPenalty);

        // Verify penalty scales linearly with time
        assertGt(actualPenalty, 0);

        (,, uint256 total) = marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);

        vm.prank(buyer);
        marketplace.makeRecurringPayment{value: total}(address(licenseToken), recurringLicenseId);
    }

    function testPenaltyScalesLinearlyOverTime() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);  // 5% per month

        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Get the actual payment time from the contract
        (uint256 lastPaymentTime,,) = marketplace.recurring(recurringLicenseId);
        uint256 paymentDue = lastPaymentTime + 30 days;

        // Check penalty at 1 day late
        vm.warp(paymentDue + 1 days);
        uint256 penaltyAt1Day = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Check penalty at 2 days late
        vm.warp(paymentDue + 2 days);
        uint256 penaltyAt2Days = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Check penalty at 3 days late
        vm.warp(paymentDue + 3 days);
        uint256 penaltyAt3Days = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Penalty should scale linearly: 2 days = 2x penalty of 1 day, 3 days = 3x penalty of 1 day
        // Allow 1 wei tolerance due to rounding in integer division
        assertApproxEqAbs(penaltyAt2Days, penaltyAt1Day * 2, 1);
        assertApproxEqAbs(penaltyAt3Days, penaltyAt1Day * 3, 2); // Allow 2 wei for 3x multiplication

        // Verify penalties are non-zero and reasonable
        assertGt(penaltyAt1Day, 0);
        assertLt(penaltyAt1Day, 0.01 ether); // Penalty for 1 day should be less than 1% of base (reasonable upper bound)
    }

    // ==================== ADMIN FUNCTION TESTS ====================

    function testAdminCanPause() public {
        vm.prank(admin);
        marketplace.pause();
        assertTrue(marketplace.paused());
    }

    function testAdminCanUnpause() public {
        vm.prank(admin);
        marketplace.pause();

        vm.prank(admin);
        marketplace.unpause();
        assertFalse(marketplace.paused());
    }

    function testNonAdminCannotPause() public {
        vm.prank(other);
        vm.expectRevert();
        marketplace.pause();
    }

    function testPausePreventsListingCreation() public {
        vm.prank(admin);
        marketplace.pause();

        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        vm.expectRevert();
        marketplace.createListing(address(ipAsset), ipTokenId, 1 ether, true);
    }

    function testAdminCanSetPenaltyRate() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(750);
        assertEq(marketplace.penaltyBasisPointsPerMonth(), 750);
    }

    // ==================== UUPS UPGRADE TESTS ====================

    function testNonAdminCannotUpgrade() public {
        MarketplaceV2 newImpl = new MarketplaceV2();

        vm.prank(other);
        vm.expectRevert();
        marketplace.upgradeToAndCall(address(newImpl), "");
    }

    function testUpgradePreservesListings() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(address(ipAsset), ipTokenId, 1 ether, true);

        (address sellerBefore, address nftBefore, uint256 tokenIdBefore, uint256 priceBefore, bool activeBefore, bool isERC721Before) = marketplace.listings(listingId);

        MarketplaceV2 newImpl = new MarketplaceV2();
        vm.prank(admin);
        marketplace.upgradeToAndCall(address(newImpl), "");

        MarketplaceV2 marketplaceV2 = MarketplaceV2(address(marketplace));
        (address sellerAfter, address nftAfter, uint256 tokenIdAfter, uint256 priceAfter, bool activeAfter, bool isERC721After) = marketplaceV2.listings(listingId);

        assertEq(sellerBefore, sellerAfter);
        assertEq(nftBefore, nftAfter);
        assertEq(tokenIdBefore, tokenIdAfter);
        assertEq(priceBefore, priceAfter);
        assertEq(activeBefore, activeAfter);
        assertEq(isERC721Before, isERC721After);
    }

    function testUpgradePreservesOffers() public {
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 1 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );

        (address buyerBefore, address nftBefore, uint256 tokenIdBefore, uint256 priceBefore, bool activeBefore, uint256 expiryBefore) = marketplace.offers(offerId);
        uint256 escrowBefore = marketplace.escrow(offerId);

        MarketplaceV2 newImpl = new MarketplaceV2();
        vm.prank(admin);
        marketplace.upgradeToAndCall(address(newImpl), "");

        MarketplaceV2 marketplaceV2 = MarketplaceV2(address(marketplace));
        (address buyerAfter, address nftAfter, uint256 tokenIdAfter, uint256 priceAfter, bool activeAfter, uint256 expiryAfter) = marketplaceV2.offers(offerId);
        uint256 escrowAfter = marketplaceV2.escrow(offerId);

        assertEq(buyerBefore, buyerAfter);
        assertEq(nftBefore, nftAfter);
        assertEq(tokenIdBefore, tokenIdAfter);
        assertEq(priceBefore, priceAfter);
        assertEq(activeBefore, activeAfter);
        assertEq(expiryBefore, expiryAfter);
        assertEq(escrowBefore, escrowAfter);
    }

    function testUpgradePreservesRecurringPayments() public {
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            seller,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "worldwide",
            false,
            30 days
        );

        vm.prank(seller);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(seller);
        bytes32 listingId = marketplace.createListing(address(licenseToken), recurringLicenseId, 0.1 ether, false);

        vm.prank(buyer);
        marketplace.buyListing{value: 0.1 ether}(listingId);

        (uint256 lastPaymentBefore, address ownerBefore, uint256 baseAmountBefore) = marketplace.recurring(recurringLicenseId);

        MarketplaceV2 newImpl = new MarketplaceV2();
        vm.prank(admin);
        marketplace.upgradeToAndCall(address(newImpl), "");

        MarketplaceV2 marketplaceV2 = MarketplaceV2(address(marketplace));
        (uint256 lastPaymentAfter, address ownerAfter, uint256 baseAmountAfter) = marketplaceV2.recurring(recurringLicenseId);

        assertEq(lastPaymentBefore, lastPaymentAfter);
        assertEq(ownerBefore, ownerAfter);
        assertEq(baseAmountBefore, baseAmountAfter);
    }


    function testUpgradedContractFunctional() public {
        MarketplaceV2 newImpl = new MarketplaceV2();
        vm.prank(admin);
        marketplace.upgradeToAndCall(address(newImpl), "");

        MarketplaceV2 marketplaceV2 = MarketplaceV2(address(marketplace));

        vm.prank(seller);
        ipAsset.approve(address(marketplaceV2), ipTokenId);

        vm.prank(seller);
        bytes32 listingId = marketplaceV2.createListing(address(ipAsset), ipTokenId, 1 ether, true);

        vm.prank(buyer);
        marketplaceV2.buyListing{value: 1 ether}(listingId);

        assertEq(ipAsset.ownerOf(ipTokenId), buyer);

        assertEq(marketplaceV2.newFeature(), "upgraded");
    }
}

contract MarketplaceV2 is Marketplace {
    function newFeature() external pure returns (string memory) {
        return "upgraded";
    }
}

