// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/Marketplace.sol";
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
        uint256 price,
        uint256 platformFee,
        uint256 royalty
    );
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();
        
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000);
        
        // Deploy proxies
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
            address(revenueDistributor),
            250, // 2.5% platform fee
            treasury
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
        
        // Setup test assets
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
            1000,
            "worldwide",
            false
        );
        
        // Give buyer some ETH
        vm.deal(buyer, 100 ether);
        vm.deal(other, 100 ether);
    }
    
    // ============ BR-003.1: Only asset owners MAY create listings ============
    
    function testOwnerCanCreateListing() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        vm.expectEmit(true, true, false, true);
        emit ListingCreated(
            keccak256(abi.encodePacked(address(ipAsset), ipTokenId, seller, uint256(0))),
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
        vm.expectRevert("Not token owner");
        marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            1 ether,
            true
        );
    }
    
    // ============ BR-003.2: Listings MUST have a price greater than zero ============
    
    function testCannotCreateListingWithZeroPrice() public {
        vm.prank(seller);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(seller);
        vm.expectRevert("Price must be greater than zero");
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
    
    // ============ BR-003.3: Only the seller MAY cancel a listing ============
    
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
        vm.expectRevert("Not the seller");
        marketplace.cancelListing(listingId);
    }
    
    // ============ BR-003.4: Anyone MAY create an offer for any asset ============
    
    function testAnyoneCanCreateOffer() public {
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit OfferCreated(
            keccak256(abi.encodePacked(address(ipAsset), ipTokenId, buyer, uint256(0))),
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
    
    // ============ BR-003.5: Offers MUST lock buyer funds in escrow ============
    
    function testOfferLocksFundsInEscrow() public {
        uint256 buyerBalanceBefore = buyer.balance;
        
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 0.5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        assertEq(buyer.balance, buyerBalanceBefore - 0.5 ether);
        assertEq(marketplace.escrowBalances(offerId), 0.5 ether);
    }
    
    function testCannotCreateOfferWithoutFunds() public {
        vm.prank(buyer);
        vm.expectRevert("Insufficient funds");
        marketplace.createOffer{value: 0}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
    }
    
    // ============ BR-003.6: Only the asset owner MAY accept an offer ============
    
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
        vm.expectRevert("Not token owner");
        marketplace.acceptOffer(offerId);
    }
    
    // ============ BR-003.7: Expired offers MUST NOT be acceptable ============
    
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
        vm.expectRevert("Offer expired");
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
    
    // ============ BR-003.8: Only the buyer MAY cancel their own offer ============
    
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
        vm.expectRevert("Not the buyer");
        marketplace.cancelOffer(offerId);
    }
    
    // ============ Additional Marketplace Tests ============
    
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
        vm.expectRevert("Insufficient payment");
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
        vm.expectRevert("Listing not active");
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
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.prank(buyer);
        marketplace.buyListing{value: 1 ether}(listingId);
        
        // Platform fee is 2.5% = 0.025 ether
        assertEq(treasury.balance, treasuryBalanceBefore + 0.025 ether);
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
}

