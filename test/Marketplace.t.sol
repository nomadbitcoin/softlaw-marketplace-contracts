// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Marketplace.sol";
import "../src/interfaces/IMarketplace.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

        // 7 days late total, but only 4 days after grace period = 4 * 86400 seconds overdue
        uint256 secondsOverdue = 4 days;
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

        // Warp 7 days late (only 4 days after grace period)
        vm.warp(block.timestamp + 37 days);

        (baseAmount, penalty, total) =
            marketplace.getTotalPaymentDue(address(licenseToken), recurringLicenseId);

        assertEq(baseAmount, 1 ether);
        uint256 secondsOverdue = 4 days; // 7 days late - 3 days grace period
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

        // Warp to 30 days + 4.5 days late (36 hours after grace period ends)
        vm.warp(block.timestamp + 30 days + 3 days + 36 hours);

        // Calculate penalty for 1.5 days AFTER grace period (36 hours = 129600 seconds)
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

        // Random time after grace period: 30 days + 3 days (grace) + 3 days + 7 hours + 23 minutes + 47 seconds
        uint256 timeAfterGrace = 3 days + 7 hours + 23 minutes + 47 seconds;
        vm.warp(block.timestamp + 30 days + 3 days + timeAfterGrace);

        // Calculate penalty for exact seconds overdue AFTER grace period
        uint256 expectedPenalty = (1 ether * 500 * timeAfterGrace) / (10000 * 2592000);

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

        // Just 1 hour late after grace period (3 days + 1 hour)
        vm.warp(block.timestamp + 30 days + 3 days + 1 hours);

        uint256 secondsOverdue = 3600; // 1 hour in seconds AFTER grace period
        uint256 expectedPenalty = (1 ether * 500 * secondsOverdue) / (10000 * 2592000);

        uint256 actualPenalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(actualPenalty, expectedPenalty);

        // Even 1 hour after grace period should have a penalty
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

        // Arbitrary time: 12345 seconds late AFTER grace period (about 3.4 hours)
        uint256 arbitraryOverdue = 12345;
        vm.warp(block.timestamp + 30 days + 3 days + arbitraryOverdue);

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

        // Check penalty at 1 day after grace period (4 days total late)
        vm.warp(paymentDue + 3 days + 1 days);
        uint256 penaltyAt1Day = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Check penalty at 2 days after grace period (5 days total late)
        vm.warp(paymentDue + 3 days + 2 days);
        uint256 penaltyAt2Days = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Check penalty at 3 days after grace period (6 days total late)
        vm.warp(paymentDue + 3 days + 3 days);
        uint256 penaltyAt3Days = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Penalty should scale linearly: 2 days = 2x penalty of 1 day, 3 days = 3x penalty of 1 day
        // Allow 1 wei tolerance due to rounding in integer division
        assertApproxEqAbs(penaltyAt2Days, penaltyAt1Day * 2, 1);
        assertApproxEqAbs(penaltyAt3Days, penaltyAt1Day * 3, 2); // Allow 2 wei for 3x multiplication

        // Verify penalties are non-zero and reasonable
        assertGt(penaltyAt1Day, 0);
        assertLt(penaltyAt1Day, 0.01 ether); // Penalty for 1 day after grace should be less than 1% of base (reasonable upper bound)
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

    // ==================== PENALTY GRACE PERIOD TESTS ====================

    function testNoPenaltyWithinGracePeriod() public {
        // Create recurring license with 30-day interval
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days  // payment interval
        );

        // Set up listing and buy to initialize recurring payment tracking
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        // Set penalty rate
        vm.prank(admin);
        marketplace.setPenaltyRate(500); // 5% per month

        // Advance time to 1 day past due (within 3-day grace period)
        uint256 dueDate = block.timestamp + 30 days;
        vm.warp(dueDate + 1 days);

        // Calculate penalty - should be 0 (within grace period)
        uint256 penalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(penalty, 0, "Penalty should be 0 within grace period");
    }

    function testNoPenaltyAtGracePeriodBoundary() public {
        // Create recurring license
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        // Set up recurring payment
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.prank(admin);
        marketplace.setPenaltyRate(500);

        // Advance time to exactly 3 days past due (at grace period boundary)
        uint256 dueDate = block.timestamp + 30 days;
        vm.warp(dueDate + 3 days);

        // Calculate penalty - should still be 0 (at boundary)
        uint256 penalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);
        assertEq(penalty, 0, "Penalty should be 0 at grace period boundary");
    }

    function testPenaltyAppliesAfterGracePeriod() public {
        // Create recurring license
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        // Set up recurring payment
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.prank(admin);
        marketplace.setPenaltyRate(500); // 5% per month

        // Advance time to 4 days past due (1 day after grace period)
        uint256 dueDate = block.timestamp + 30 days;
        vm.warp(dueDate + 4 days);

        // Calculate penalty - should apply for 1 day
        uint256 penalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Expected: baseAmount * penaltyRate * 1 day in seconds / (BASIS_POINTS * SECONDS_PER_MONTH)
        uint256 baseAmount = 1 ether;
        uint256 secondsLate = 1 days;
        uint256 expectedPenalty = (baseAmount * 500 * secondsLate) / (10_000 * 2_592_000);

        assertEq(penalty, expectedPenalty, "Penalty should apply only for time after grace period");
        assertGt(penalty, 0, "Penalty should be greater than 0 after grace period");
    }

    function testPenaltyCalculationAfterGracePeriod() public {
        // Create recurring license
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        // Set up recurring payment
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.prank(admin);
        marketplace.setPenaltyRate(500);

        // Advance time to 10 days past due (7 days after grace period)
        uint256 dueDate = block.timestamp + 30 days;
        vm.warp(dueDate + 10 days);

        // Calculate penalty - should apply for 7 days only
        uint256 penalty = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Expected: baseAmount * penaltyRate * 7 days in seconds / (BASIS_POINTS * SECONDS_PER_MONTH)
        uint256 baseAmount = 1 ether;
        uint256 secondsLate = 7 days;
        uint256 expectedPenalty = (baseAmount * 500 * secondsLate) / (10_000 * 2_592_000);

        assertEq(penalty, expectedPenalty, "Penalty calculation should exclude grace period");
    }

    function testGracePeriodWithMultipleLatePayments() public {
        vm.prank(admin);
        marketplace.setPenaltyRate(500);

        // Test 1: License with 2-day late payment (within grace period) - no penalty
        vm.prank(seller);
        uint256 license1 = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listing1 = marketplace.createListing(address(licenseToken), license1, 1 ether, false);

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listing1);

        vm.warp(block.timestamp + 30 days + 2 days);
        uint256 penalty1 = marketplace.calculatePenalty(address(licenseToken), license1);
        assertEq(penalty1, 0, "Payment 2 days late within grace period should have no penalty");

        // Test 2: License with 5-day late payment (2 days after grace) - has penalty
        vm.prank(seller);
        uint256 license2 = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        vm.prank(buyer);
        bytes32 listing2 = marketplace.createListing(address(licenseToken), license2, 1 ether, false);

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listing2);

        vm.warp(block.timestamp + 30 days + 5 days);
        uint256 penalty2 = marketplace.calculatePenalty(address(licenseToken), license2);
        assertGt(penalty2, 0, "Payment 5 days late (2 after grace) should have penalty");
    }

    function testEdgeCaseExactlyAtGracePeriod() public {
        // Create recurring license
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        // Set up recurring payment
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.prank(admin);
        marketplace.setPenaltyRate(500);

        uint256 dueDate = block.timestamp + 30 days;

        // Test at exactly grace period end (3 days + 1 second should have penalty)
        vm.warp(dueDate + 3 days);
        assertEq(marketplace.calculatePenalty(address(licenseToken), recurringLicenseId), 0, "At grace period end should be 0");

        // One second after grace period
        vm.warp(dueDate + 3 days + 1 seconds);
        assertGt(marketplace.calculatePenalty(address(licenseToken), recurringLicenseId), 0, "After grace period should have penalty");
    }

    function testBackwardCompatibility() public {
        // Verify existing penalty tests still work with grace period
        // This test ensures the grace period doesn't break existing functionality

        // Create recurring license
        vm.prank(seller);
        uint256 recurringLicenseId = ipAsset.mintLicense(
            ipTokenId,
            buyer,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "recurring terms",
            false,
            30 days
        );

        // Set up recurring payment
        vm.prank(buyer);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(buyer);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            recurringLicenseId,
            1 ether,
            false
        );

        vm.prank(other);
        marketplace.buyListing{value: 1 ether}(listingId);

        vm.prank(admin);
        marketplace.setPenaltyRate(500);

        // Test penalties scale correctly after grace period
        // Get the actual payment time from the contract
        (uint256 lastPaymentTime,,) = marketplace.recurring(recurringLicenseId);
        uint256 paymentDue = lastPaymentTime + 30 days;

        // 4 days late (1 day after grace) = 1 day penalty
        vm.warp(paymentDue + 3 days + 1 days);
        uint256 penalty1 = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // 5 days late (2 days after grace) = 2 days penalty
        vm.warp(paymentDue + 3 days + 2 days);
        uint256 penalty2 = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // 6 days late (3 days after grace) = 3 days penalty
        vm.warp(paymentDue + 3 days + 3 days);
        uint256 penalty3 = marketplace.calculatePenalty(address(licenseToken), recurringLicenseId);

        // Penalties should scale linearly
        assertGt(penalty2, penalty1, "Penalty should increase with time");
        assertGt(penalty3, penalty2, "Penalty should continue to increase");

        // Check linear scaling
        assertApproxEqAbs(penalty2, penalty1 * 2, penalty1 / 100, "Penalties should scale linearly");
        assertApproxEqAbs(penalty3, penalty1 * 3, penalty1 / 100, "Penalties should scale linearly");
    }
}

contract MarketplaceV2 is Marketplace {
    function newFeature() external pure returns (string memory) {
        return "upgraded";
    }
}

