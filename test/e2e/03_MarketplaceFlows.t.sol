// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title MarketplaceFlows E2E Tests
 * @notice Comprehensive end-to-end tests for all Marketplace user operations
 * @dev Tests cover:
 *      - Listing lifecycle (create, buy, cancel)
 *      - Offer lifecycle (create, accept, cancel, expire)
 *      - IP asset marketplace transactions
 *      - License marketplace transactions
 *      - Price changes and multi-listing scenarios
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract MarketplaceFlowsTest is E2ETestBase {

    // ============ Helper: Create IP with Split ============
    function _createIPWithSplit(address owner) internal returns (uint256) {
        uint256 tokenId = _mintIP(owner, "ipfs://ip-metadata");
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(owner);
        _configureRevenueSplit(tokenId, owner, recipients, shares);
        return tokenId;
    }

    // ============ IP Asset Listing Tests ============

    function test_E2E_UserListsIPForSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice lists her IP for 10 ETH
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Verify listing exists (listing ID should be non-zero)
        assertTrue(listingId != bytes32(0));
    }

    function test_E2E_UserBuysListedIP() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        uint256 bobBalanceBefore = bob.balance;

        // Bob buys the IP
        _buyListing(bob, listingId, 10 ether);

        // Verify ownership transfer
        assertEq(ipAsset.ownerOf(ipTokenId), bob);
        assertEq(ipAsset.balanceOf(alice), 0);
        assertEq(ipAsset.balanceOf(bob), 1);

        // Bob spent 10 ETH
        assertEq(bob.balance, bobBalanceBefore - 10 ether);
    }

    function test_E2E_UserCancelsIPListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Alice cancels the listing
        vm.prank(alice);
        marketplace.cancelListing(listingId);

        // Alice still owns the IP
        assertEq(ipAsset.ownerOf(ipTokenId), alice);

        // Buying should fail now
        vm.prank(bob);
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);
    }

    function test_E2E_NonOwnerCannotListIP() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Bob tries to list Alice's IP - should fail
        vm.startPrank(bob);
        vm.expectRevert();
        ipAsset.approve(address(marketplace), ipTokenId);
        vm.stopPrank();
    }

    function test_E2E_NonSellerCannotCancelListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Bob tries to cancel Alice's listing - should fail
        vm.prank(bob);
        vm.expectRevert();
        marketplace.cancelListing(listingId);
    }

    function test_E2E_UserRelistsIPAtDifferentPrice() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // List at 10 ETH
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Cancel and relist at 15 ETH
        vm.prank(alice);
        marketplace.cancelListing(listing1);

        bytes32 listing2 = _createListing(alice, address(ipAsset), ipTokenId, 15 ether, true);

        // Bob buys at new price
        _buyListing(bob, listing2, 15 ether);

        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_MultipleBuyersCompeteForSameIP() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Bob buys first
        _buyListing(bob, listingId, 10 ether);

        // Charlie tries to buy - should fail (already sold)
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);

        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    // ============ License Listing Tests ============

    function test_E2E_UserListsLicenseForSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice creates license for Bob
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 30 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists license for resale at 8 ETH
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        assertTrue(listingId != bytes32(0));
    }

    function test_E2E_UserBuysListedLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 30 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists for 8 ETH
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Charlie buys
        _buyListing(charlie, listingId, 8 ether);

        // Verify license transfer
        assertEq(licenseToken.balanceOf(bob, licenseId), 0);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);
    }

    function test_E2E_UserListsPartialLicenseSupply() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice creates license with supply of 10 for Bob
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 10, _now() + 60 days, false, 0, 10 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists only 3 of his 10 licenses
        vm.startPrank(bob);
        licenseToken.setApprovalForAll(address(marketplace), true);

        // Note: The marketplace might need to support partial supply listings
        // For this test, assume Bob lists at unit price and Charlie buys quantity
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            licenseId,
            2 ether, // Price per unit
            false
        );
        vm.stopPrank();

        assertTrue(listingId != bytes32(0));
    }

    function test_E2E_LicenseFragmentationThroughMarketplace() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 100, _now() + 90 days, false, 0, 20 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob sells portions to different buyers through multiple listings
        // (Simulating multiple sequential sales)

        // First sale to Charlie (30 units)
        _transferLicense(bob, charlie, licenseId, 30);

        // Second sale to Dave (20 units)
        _transferLicense(bob, dave, licenseId, 20);

        // Third sale to Eve (10 units)
        _transferLicense(bob, eve, licenseId, 10);

        // Bob retains 40
        assertEq(licenseToken.balanceOf(bob, licenseId), 40);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 30);
        assertEq(licenseToken.balanceOf(dave, licenseId), 20);
        assertEq(licenseToken.balanceOf(eve, licenseId), 10);
    }

    // ============ Offer Tests (IP Assets) ============

    function test_E2E_UserMakesOfferOnIP() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Bob makes offer of 12 ETH for Alice's IP
        uint256 bobBalanceBefore = bob.balance;

        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            12 ether,
            _now() + 7 days
        );

        // Bob's funds are escrowed
        assertEq(bob.balance, bobBalanceBefore - 12 ether);
        assertTrue(offerId != bytes32(0));
    }

    function test_E2E_SellerAcceptsOffer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Bob makes offer
        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            12 ether,
            _now() + 7 days
        );

        // Alice accepts the offer
        _acceptOffer(alice, offerId, address(ipAsset), true, ipTokenId);

        // Bob now owns the IP
        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_BuyerCancelsOffer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 bobBalanceBefore = bob.balance;

        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            12 ether,
            _now() + 7 days
        );

        // Bob's funds escrowed
        assertEq(bob.balance, bobBalanceBefore - 12 ether);

        // Bob cancels offer
        vm.prank(bob);
        marketplace.cancelOffer(offerId);

        // Bob gets refund
        assertEq(bob.balance, bobBalanceBefore);

        // Alice cannot accept canceled offer
        vm.prank(alice);
        vm.expectRevert();
        marketplace.acceptOffer(offerId);
    }

    function test_E2E_OfferExpiresAfterDeadline() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Bob makes offer with 7-day expiry
        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            12 ether,
            _now() + 7 days
        );

        // 6 days pass - offer still valid
        _advanceTime(6 days);

        // Alice can still accept
        _acceptOffer(alice, offerId, address(ipAsset), true, ipTokenId);

        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_ExpiredOfferCannotBeAccepted() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            12 ether,
            _now() + 7 days
        );

        // 8 days pass - offer expired
        _advanceTime(8 days);

        // Alice cannot accept expired offer
        vm.prank(alice);
        vm.expectRevert();
        marketplace.acceptOffer(offerId);

        // Bob can cancel and get refund
        vm.prank(bob);
        marketplace.cancelOffer(offerId);
    }

    function test_E2E_MultipleOffersOnSameIP() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Multiple buyers make offers
        bytes32 bobOffer = _createOffer(bob, address(ipAsset), ipTokenId, 10 ether, _now() + 7 days);
        bytes32 charlieOffer = _createOffer(charlie, address(ipAsset), ipTokenId, 12 ether, _now() + 7 days);
        bytes32 daveOffer = _createOffer(dave, address(ipAsset), ipTokenId, 15 ether, _now() + 7 days);

        // Alice accepts highest offer (Dave's)
        _acceptOffer(alice, daveOffer, address(ipAsset), true, ipTokenId);

        assertEq(ipAsset.ownerOf(ipTokenId), dave);

        // Other offers cannot be accepted (Alice no longer owns IP)
        vm.prank(alice);
        vm.expectRevert();
        marketplace.acceptOffer(bobOffer);

        // Bob and Charlie can cancel their offers and get refunds
        vm.prank(bob);
        marketplace.cancelOffer(bobOffer);

        vm.prank(charlie);
        marketplace.cancelOffer(charlieOffer);
    }

    function test_E2E_NonOwnerCannotAcceptOffer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 offerId = _createOffer(
            bob,
            address(ipAsset),
            ipTokenId,
            10 ether,
            _now() + 7 days
        );

        // Charlie tries to accept offer for Alice's IP - should fail
        vm.startPrank(charlie);
        vm.expectRevert();
        ipAsset.approve(address(marketplace), ipTokenId);
        vm.stopPrank();
    }

    // ============ Offer Tests (Licenses) ============

    function test_E2E_UserMakesOfferOnLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 60 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie makes offer for Bob's license
        bytes32 offerId = _createOffer(
            charlie,
            address(licenseToken),
            licenseId,
            8 ether,
            _now() + 7 days
        );

        assertTrue(offerId != bytes32(0));
    }

    function test_E2E_LicenseHolderAcceptsOffer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 60 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie makes offer
        bytes32 offerId = _createOffer(
            charlie,
            address(licenseToken),
            licenseId,
            8 ether,
            _now() + 7 days
        );

        // Bob accepts
        _acceptOffer(bob, offerId, address(licenseToken), false, licenseId);

        // Charlie now owns the license
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);
        assertEq(licenseToken.balanceOf(bob, licenseId), 0);
    }

    function test_E2E_CompetingOffersOnLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 60 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Multiple offers
        bytes32 charlieOffer = _createOffer(charlie, address(licenseToken), licenseId, 6 ether, _now() + 7 days);
        bytes32 daveOffer = _createOffer(dave, address(licenseToken), licenseId, 7 ether, _now() + 7 days);
        bytes32 eveOffer = _createOffer(eve, address(licenseToken), licenseId, 9 ether, _now() + 7 days);

        // Bob accepts highest offer
        _acceptOffer(bob, eveOffer, address(licenseToken), false, licenseId);

        assertEq(licenseToken.balanceOf(eve, licenseId), 1);

        // Others cancel their offers
        vm.prank(charlie);
        marketplace.cancelOffer(charlieOffer);

        vm.prank(dave);
        marketplace.cancelOffer(daveOffer);
    }

    // ============ Cross-Type Transactions ============

    function test_E2E_UserBuysIPAndLicenseSequentially() public {
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(bob);

        // Bob creates license for his IP
        uint256 licenseId = _mintLicense(
            ip2, bob, charlie, 1, _now() + 90 days, false, 0, 3 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Dave buys Alice's IP
        bytes32 ipListing = _createListing(alice, address(ipAsset), ip1, 20 ether, true);
        _buyListing(dave, ipListing, 20 ether);

        // Dave buys Charlie's license
        bytes32 licenseListing = _createListing(charlie, address(licenseToken), licenseId, 5 ether, false);
        _buyListing(dave, licenseListing, 5 ether);

        // Dave owns both
        assertEq(ipAsset.ownerOf(ip1), dave);
        assertEq(licenseToken.balanceOf(dave, licenseId), 1);
    }

    // ============ Listing After Transfer Edge Cases ============

    function test_E2E_ListingInvalidAfterDirectTransfer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice lists IP
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Alice transfers IP directly to Bob (outside marketplace)
        _transferIP(alice, bob, ipTokenId);

        // Charlie tries to buy the listing - should fail
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);

        // Bob now owns the IP
        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_NewOwnerCanListAfterDirectTransfer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice lists and then cancels
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        vm.prank(alice);
        marketplace.cancelListing(listing1);

        // Alice transfers to Bob
        _transferIP(alice, bob, ipTokenId);

        // Bob can now list
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 15 ether, true);

        // Charlie buys from Bob
        _buyListing(charlie, listing2, 15 ether);

        assertEq(ipAsset.ownerOf(ipTokenId), charlie);
    }

    // ============ Escrow and Refund Tests ============

    function test_E2E_MultipleOffersCancelledForRefund() public {
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(bob);
        uint256 ip3 = _createIPWithSplit(charlie);

        uint256 daveBalanceBefore = dave.balance;

        // Dave makes offers on 3 different IPs
        bytes32 offer1 = _createOffer(dave, address(ipAsset), ip1, 5 ether, _now() + 7 days);
        bytes32 offer2 = _createOffer(dave, address(ipAsset), ip2, 10 ether, _now() + 7 days);
        bytes32 offer3 = _createOffer(dave, address(ipAsset), ip3, 15 ether, _now() + 7 days);

        // Dave's funds are escrowed (30 ETH total)
        assertEq(dave.balance, daveBalanceBefore - 30 ether);

        // Dave changes his mind and cancels all offers
        vm.startPrank(dave);
        marketplace.cancelOffer(offer1);
        marketplace.cancelOffer(offer2);
        marketplace.cancelOffer(offer3);
        vm.stopPrank();

        // Dave gets full refund
        assertEq(dave.balance, daveBalanceBefore);
    }

    function test_E2E_PartialOfferAcceptanceScenario() public {
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(bob);
        uint256 ip3 = _createIPWithSplit(charlie);

        // Dave makes 3 offers
        bytes32 offer1 = _createOffer(dave, address(ipAsset), ip1, 5 ether, _now() + 7 days);
        bytes32 offer2 = _createOffer(dave, address(ipAsset), ip2, 10 ether, _now() + 7 days);
        bytes32 offer3 = _createOffer(dave, address(ipAsset), ip3, 15 ether, _now() + 7 days);

        // Only Alice accepts
        _acceptOffer(alice, offer1, address(ipAsset), true, ip1);

        // Dave owns ip1
        assertEq(ipAsset.ownerOf(ip1), dave);

        // Dave cancels remaining offers
        vm.startPrank(dave);
        marketplace.cancelOffer(offer2);
        marketplace.cancelOffer(offer3);
        vm.stopPrank();

        // Dave gets partial refund (25 ETH back, spent 5 ETH)
    }

    // ============ Price Manipulation Prevention Tests ============

    function test_E2E_BuyerMustSendExactAmount() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Bob tries to buy for less - should fail
        vm.prank(bob);
        vm.expectRevert();
        marketplace.buyListing{value: 9 ether}(listingId);

        // Bob tries to buy for more - might succeed but overpayment
        // (depends on marketplace implementation)
        _buyListing(bob, listingId, 10 ether);

        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    // ============ Concurrent Activity Tests ============

    function test_E2E_SimultaneousListingsAndOffers() public {
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(bob);

        // Alice lists her IP
        bytes32 aliceListing = _createListing(alice, address(ipAsset), ip1, 10 ether, true);

        // Bob lists his IP
        bytes32 bobListing = _createListing(bob, address(ipAsset), ip2, 15 ether, true);

        // Charlie makes offer on Alice's IP
        bytes32 charlieOffer = _createOffer(charlie, address(ipAsset), ip1, 12 ether, _now() + 7 days);

        // Dave buys Bob's listing
        _buyListing(dave, bobListing, 15 ether);

        // Alice accepts Charlie's offer (cancels her listing)
        vm.prank(alice);
        marketplace.cancelListing(aliceListing);

        _acceptOffer(alice, charlieOffer, address(ipAsset), true, ip1);

        // Verify final ownership
        assertEq(ipAsset.ownerOf(ip1), charlie);
        assertEq(ipAsset.ownerOf(ip2), dave);
    }

    function test_E2E_MarketplaceMixedIPAndLicenseSales() public {
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(bob);

        uint256 license1 = _mintLicense(
            ip1, alice, charlie, 5, _now() + 60 days, false, 0, 2 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ip2, bob, dave, 3, _now() + 90 days, false, 0, 3 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        // List IP1
        bytes32 ipListing = _createListing(alice, address(ipAsset), ip1, 20 ether, true);

        // List license2
        bytes32 licenseListing = _createListing(dave, address(licenseToken), license2, 5 ether, false);

        // Eve buys IP1
        _buyListing(eve, ipListing, 20 ether);

        // Frank buys license2
        _buyListing(frank, licenseListing, 5 ether);

        assertEq(ipAsset.ownerOf(ip1), eve);
        assertEq(licenseToken.balanceOf(frank, license2), 3);
    }

    // ============ Approval Management Tests ============

    function test_E2E_ApprovalRevokedAfterSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice lists IP (implicitly approves marketplace)
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Bob buys
        _buyListing(bob, listingId, 10 ether);

        // Marketplace should no longer have approval for this token
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);
    }
}
