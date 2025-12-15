// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title CrossContractInteractions E2E Tests
 * @notice Tests for complex interactions between multiple contracts
 * @dev Tests cover critical state synchronization scenarios:
 *      - License expiration during marketplace transactions
 *      - License revocation during transfers
 *      - IP ownership changes affecting active listings
 *      - Dispute resolution impact on marketplace
 *      - Recurring payments across contract boundaries
 *      - Revenue distribution state consistency
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract CrossContractInteractionsTest is E2ETestBase {

    // ============ Helper: Create IP with Split ============
    function _createIPWithSplit(address owner) internal returns (uint256) {
        uint256 tokenId = _mintIP(owner, "ipfs://ip-metadata");
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(owner);
        _configureRevenueSplit(tokenId, owner, recipients, shares);
        return tokenId;
    }

    // ============ Helper: Create Recurring License ============
    function _createRecurringLicense(
        address ipOwner,
        address licensee,
        uint256 ipTokenId,
        uint256 interval,
        uint256 price
    ) internal returns (uint256) {
        // 1. Mint license to IP owner (seller) first
        vm.prank(ipOwner);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            ipOwner,  // Mint to seller first
            1,
            "ipfs://recurring-license",
            "ipfs://recurring-license-priv",
            _now() + 365 days,
            "license terms",
            false,
            interval
        );

        // 2. List license on marketplace with price
        vm.prank(ipOwner);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(ipOwner);
        bytes32 listingId = marketplace.createListing(
            address(licenseToken),
            licenseId,
            price,
            false  // ERC1155
        );

        // 3. Licensee purchases through marketplace (initializes recurring payment data)
        vm.prank(licensee);
        marketplace.buyListing{value: price}(listingId);

        return licenseId;
    }

    // ============ License Expiration + Marketplace Tests ============

    function test_E2E_LicenseExpiresWhileListed() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Create short-lived license
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 10 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists the license
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Advance time past expiration
        _advanceTime(11 days);

        // Mark license as expired
        _markExpired(alice, licenseId);

        // Charlie tries to buy expired license - should fail
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 8 ether}(listingId);

        // License still with Bob (sale failed)
        assertEq(licenseToken.balanceOf(bob, licenseId), 1);
        assertTrue(licenseToken.isExpired(licenseId));
    }

    function test_E2E_LicenseExpiresAfterOfferBeforeAcceptance() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 10 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie makes offer with 15-day expiry
        bytes32 offerId = _createOffer(
            charlie,
            address(licenseToken),
            licenseId,
            8 ether,
            _now() + 15 days
        );

        // License expires before Bob accepts
        _advanceTime(11 days);
        _markExpired(alice, licenseId);

        // Bob tries to accept offer for expired license - should fail
        vm.prank(bob);
        vm.expectRevert();
        marketplace.acceptOffer(offerId);

        // Charlie can cancel and get refund
        vm.prank(charlie);
        marketplace.cancelOffer(offerId);
    }

    function test_E2E_BatchExpireInvalidatesAllListings() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Create 3 licenses expiring at same time
        uint256[] memory licenseIds = new uint256[](3);
        bytes32[] memory listingIds = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            licenseIds[i] = _mintLicense(
                ipTokenId, alice, bob, 1, _now() + 7 days, false, 0, (i + 1) * 1 ether,
                string(abi.encodePacked("ipfs://l", vm.toString(i))),
                string(abi.encodePacked("ipfs://l", vm.toString(i), "-priv"))
            );

            // Bob lists each
            listingIds[i] = _createListing(
                bob,
                address(licenseToken),
                licenseIds[i],
                (i + 2) * 1 ether,
                false
            );
        }

        // Advance past expiration
        _advanceTime(8 days);

        // Batch mark expired
        vm.prank(alice);
        licenseToken.batchMarkExpired(licenseIds);

        // All listings should fail
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(charlie);
            vm.expectRevert();
            marketplace.buyListing{value: (i + 2) * 1 ether}(listingIds[i]);
        }
    }

    // ============ License Revocation + Marketplace Tests ============

    function test_E2E_DisputeRevokesLicenseDuringListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists license
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Alice submits dispute and arbitrator approves (revokes)
        uint256 disputeId = _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));

        // Charlie tries to buy revoked license - should fail
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 8 ether}(listingId);
    }

    function test_E2E_MissedPaymentsRevokeBeforeMarketplaceSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Recurring license - create through marketplace
        uint256 licenseId = _createRecurringLicense(alice, bob, ipTokenId, 30 days, 1 ether);

        // Bob misses 3 CONSECUTIVE payments (doesn't pay them)
        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);

        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 2);

        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 3);

        // Bob lists license before realizing it can be revoked
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 10 ether, false);

        // Alice triggers auto-revocation
        vm.prank(alice);
        licenseToken.revokeForMissedPayments(licenseId, 3);

        assertTrue(licenseToken.isRevoked(licenseId));

        // Charlie tries to buy - should fail
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);
    }

    // ============ IP Ownership + Marketplace Tests ============

    function test_E2E_IPTransferInvalidatesListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice lists IP
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Alice transfers IP to Bob directly (outside marketplace)
        _transferIP(alice, bob, ipTokenId);

        // Charlie tries to buy from listing - should fail (Alice no longer owns)
        vm.prank(charlie);
        vm.expectRevert();
        marketplace.buyListing{value: 10 ether}(listingId);

        // Bob owns the IP
        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_IPSaleThroughMarketplaceUpdatesRevenueSplit() public {
        // Alice creates IP with collaborators
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );

        uint256 ipTokenId = _mintIP(alice, "ipfs://ip-metadata");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);
        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Primary sale through marketplace
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(bob, listing1, 20 ether);

        // Bob (new owner) reconfigures split
        (address[] memory newRecipients, uint256[] memory newShares) = _simpleSplit(bob);
        _configureRevenueSplit(ipTokenId, bob, newRecipients, newShares);

        uint256 bobBalanceBefore = revenueDistributor.getBalance(bob);

        // Secondary sale - NEW split applies (bob is 100% of split now)
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 30 ether, true);
        _buyListing(charlie, listing2, 30 ether);

        // Bob gets seller proceeds AND royalty (since he's 100% of the NEW split)
        // Royalty = 10% of 30 ETH = 3 ETH (goes to current split = bob)
        // Seller proceeds = 30 ETH - platform fee (2.5%) - royalty (3 ETH) = ~26.25 ETH
        uint256 platformFee = _platformFee(30 ether);
        uint256 royalty = _royalty(30 ether, 1000);
        uint256 expectedTotal = 30 ether - platformFee; // Bob gets both royalty and proceeds

        assertEq(revenueDistributor.getBalance(bob) - bobBalanceBefore, expectedTotal);
    }

    // ============ Recurring Payments + License Transfers Tests ============

    function test_E2E_RecurringPaymentAfterLicenseMarketplaceSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Recurring license - create through marketplace to initialize payment tracking
        uint256 licenseId = _createRecurringLicense(alice, bob, ipTokenId, 30 days, 1 ether);

        // Bob makes first payment
        _advanceTime(30 days);
        _makeRecurringPayment(bob, licenseId);

        // Bob sells license to Charlie
        _transferLicense(bob, charlie, licenseId, 1);

        // Charlie must make next payment (ownership transferred)
        _advanceTime(30 days);

        vm.prank(bob);
        vm.expectRevert(); // Bob cannot pay anymore
        marketplace.makeRecurringPayment{value: 2 ether}(address(licenseToken), licenseId);

        // Charlie makes payment
        _makeRecurringPayment(charlie, licenseId);

        // Payment goes to Alice (IP owner)
        assertGt(revenueDistributor.getBalance(alice), 0);
    }

    function test_E2E_MissedPaymentsDoNotPersistThroughMarketplaceSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Recurring license - create through marketplace
        uint256 licenseId = _createRecurringLicense(alice, bob, ipTokenId, 30 days, 1 ether);

        // Bob makes 2 late payments - each resets consecutive count to 0
        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);
        _makeRecurringPayment(bob, licenseId);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        _advanceTime(30 days + 5 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);
        _makeRecurringPayment(bob, licenseId);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        // Bob sells to Charlie (consecutive count is 0, does NOT persist)
        _transferLicense(bob, charlie, licenseId, 1);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        // Charlie would need to miss 3 CONSECUTIVE payments to trigger revocation
        // Charlie makes next payment late but pays it (count remains 0)
        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);
        _makeRecurringPayment(charlie, licenseId);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        // Cannot be revoked (consecutive count reset)
        vm.prank(alice);
        vm.expectRevert();
        licenseToken.revokeForMissedPayments(licenseId, 0);

        assertFalse(licenseToken.isRevoked(licenseId));
    }

    // ============ Dispute + Marketplace + Revenue Tests ============

    function test_E2E_DisputeResolutionDuringMultiContractFlow() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Alice mints and sells license to Bob through marketplace (primary sale)
        vm.prank(alice);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            alice,  // Mint to alice first
            1,
            "ipfs://license",
            "ipfs://license-priv",
            _now() + 90 days,
            "license terms",
            false,
            0
        );

        vm.prank(alice);
        licenseToken.setApprovalForAll(address(marketplace), true);

        vm.prank(alice);
        bytes32 primaryListing = marketplace.createListing(address(licenseToken), licenseId, 5 ether, false);

        vm.deal(bob, 10 ether);
        vm.prank(bob);
        marketplace.buyListing{value: 5 ether}(primaryListing);

        // Now Bob owns the license after primary sale
        assertEq(licenseToken.balanceOf(bob, licenseId), 1);

        // Charlie makes offer for secondary sale
        bytes32 offerId = _createOffer(
            charlie,
            address(licenseToken),
            licenseId,
            8 ether,
            _now() + 7 days
        );

        // Alice submits dispute
        uint256 disputeId = _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        // Bob accepts offer (before dispute resolved) - secondary sale
        _acceptOffer(bob, offerId, address(licenseToken), false, licenseId);

        // Charlie owns license
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);

        // Bob received revenue from secondary sale
        assertGt(revenueDistributor.getBalance(bob), 0);

        // Dispute resolved - revokes license (now affects Charlie)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));

        // Charlie cannot transfer or use revoked license
        vm.prank(charlie);
        vm.expectRevert();
        licenseToken.safeTransferFrom(charlie, dave, licenseId, 1, "");
    }

    // ============ IP Burn Protection Across Contracts Tests ============

    function test_E2E_CannotBurnIPWithActiveLicenseAndListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists license
        _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Alice tries to burn IP - should fail (active license exists)
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.burn(ipTokenId);
    }

    function test_E2E_CannotBurnIPWithPendingDisputeAndOffer() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 30 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie makes offer
        _createOffer(charlie, address(licenseToken), licenseId, 8 ether, _now() + 7 days);

        // Submit dispute
        _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Alice tries to burn - should fail (pending dispute)
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.burn(ipTokenId);
    }

    function test_E2E_BurnIPAfterAllContractStatesCleared() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 7 days, false, 0, 1 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Submit dispute
        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Resolve dispute
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // License revoked and expired
        _advanceTime(8 days);
        _markExpired(alice, licenseId);

        // Now Alice can burn (all states cleared)
        vm.prank(alice);
        ipAsset.burn(ipTokenId);

        vm.expectRevert();
        ipAsset.ownerOf(ipTokenId);
    }

    // ============ Metadata Access Across Contract Boundaries Tests ============

    function test_E2E_PrivateMetadataAccessAfterMarketplaceSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 5, _now() + 60 days, false, 0, 5 ether,
            "ipfs://public", "ipfs://private-secret"
        );

        // Bob grants access to Charlie
        _grantPrivateAccess(bob, licenseId, charlie);

        // Charlie can access
        vm.prank(charlie);
        licenseToken.getPrivateMetadata(licenseId);

        // Bob sells all licenses to Dave
        _transferLicense(bob, dave, licenseId, 5);

        // Bob can no longer access (no balance)
        vm.prank(bob);
        vm.expectRevert();
        licenseToken.getPrivateMetadata(licenseId);

        // Dave (new holder) can access
        vm.prank(dave);
        licenseToken.getPrivateMetadata(licenseId);

        // Charlie's explicit grant may or may not persist (test current behavior)
        // If grants are separate from ownership, Charlie might still have access
    }

    // ============ Revenue Distribution Across Sales Tests ============

    function test_E2E_MultipleIPAndLicenseSalesAccumulateRevenue() public {
        // Alice creates 2 IPs
        uint256 ip1 = _createIPWithSplit(alice);
        uint256 ip2 = _createIPWithSplit(alice);

        _setRoyaltyRate(ip1, alice, 1000);
        _setRoyaltyRate(ip2, alice, 500);

        // Create licenses
        uint256 license1 = _mintLicense(
            ip1, alice, bob, 1, _now() + 90 days, false, 0, 3 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ip2, alice, charlie, 1, _now() + 90 days, false, 0, 2 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Sell IP1 (primary)
        bytes32 listing1 = _createListing(alice, address(ipAsset), ip1, 10 ether, true);
        _buyListing(dave, listing1, 10 ether);

        // Sell IP2 (primary)
        bytes32 listing2 = _createListing(alice, address(ipAsset), ip2, 15 ether, true);
        _buyListing(eve, listing2, 15 ether);

        // Bob sells license1 (secondary)
        bytes32 listing3 = _createListing(bob, address(licenseToken), license1, 5 ether, false);
        _buyListing(frank, listing3, 5 ether);

        // Charlie sells license2 (secondary)
        bytes32 listing4 = _createListing(charlie, address(licenseToken), license2, 4 ether, false);
        _buyListing(grace, listing4, 4 ether);

        // Alice accumulated revenue from multiple sources
        uint256 totalRevenue = revenueDistributor.getBalance(alice) - aliceBalanceBefore;
        assertGt(totalRevenue, 20 ether); // At least primary sales minus fees
    }

    // ============ Concurrent State Changes Tests ============

    function test_E2E_SimultaneousListingAndDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists license
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Simultaneously, Alice submits dispute
        _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        // License listed and disputed simultaneously
        // Charlie can still buy (dispute not resolved yet)
        _buyListing(charlie, listingId, 8 ether);

        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);

        // Dispute resolution affects Charlie now
    }

    function test_E2E_ExpiredLicenseWithPendingOfferAndDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 10 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie makes offer
        bytes32 offerId = _createOffer(
            charlie,
            address(licenseToken),
            licenseId,
            8 ether,
            _now() + 15 days
        );

        // Alice submits dispute
        _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        // License expires
        _advanceTime(11 days);
        _markExpired(alice, licenseId);

        // Bob cannot accept expired license offer
        vm.prank(bob);
        vm.expectRevert();
        marketplace.acceptOffer(offerId);

        // Charlie cancels offer
        vm.prank(charlie);
        marketplace.cancelOffer(offerId);

        // Dispute can still be resolved (affects expired state)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(1, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));
        assertTrue(licenseToken.isExpired(licenseId));
    }
}
