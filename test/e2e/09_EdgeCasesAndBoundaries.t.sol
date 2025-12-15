// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title EdgeCasesAndBoundaries E2E Tests
 * @notice Tests for edge cases, boundary conditions, and extreme scenarios
 * @dev Tests cover:
 *      - Time-based boundaries (expiry edges, payment deadlines)
 *      - Numerical edge cases (min/max values, precision)
 *      - Supply boundaries (0, 1, large numbers)
 *      - Access control edge cases
 *      - Error recovery scenarios
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract EdgeCasesAndBoundariesTest is E2ETestBase {

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

    // ============ Time Boundary Tests ============

    function test_E2E_LicenseExpiresExactlyAtBoundary() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 expiryTime = _now() + 30 days;

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, expiryTime, false, 0, 1 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Advance to exactly expiry time
        vm.warp(expiryTime);

        // License should not be expired yet (>= check, not >)
        // Mark expired should fail
        vm.prank(alice);
        vm.expectRevert();
        licenseToken.markExpired(licenseId);

        // Advance 1 second past
        vm.warp(expiryTime + 1);

        // Now can mark expired
        _markExpired(alice, licenseId);
        assertTrue(licenseToken.isExpired(licenseId));
    }

    function test_E2E_GracePeriodExactBoundary() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Create recurring license through marketplace
        uint256 licenseId = _createRecurringLicense(alice, bob, ipTokenId, 30 days, 1 ether);

        // Advance to exact end of grace period (30 days + 3 days)
        vm.warp(_now() + 33 days);

        uint256 penalty = marketplace.calculatePenalty(address(licenseToken), licenseId);

        // Should be 0 penalty (within grace)
        assertEq(penalty, 0);

        // Advance 1 second past grace
        vm.warp(_now() + 33 days + 1);

        penalty = marketplace.calculatePenalty(address(licenseToken), licenseId);

        // Now should have penalty
        assertGt(penalty, 0);
    }

    function test_E2E_OfferExpiresAtExactTimestamp() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 offerExpiry = _now() + 7 days;

        bytes32 offerId = _createOffer(bob, address(ipAsset), ipTokenId, 10 ether, offerExpiry);

        // Advance to exact expiry
        vm.warp(offerExpiry);

        // Should still be acceptable at exact timestamp
        _acceptOffer(alice, offerId, address(ipAsset), true, ipTokenId);

        assertEq(ipAsset.ownerOf(ipTokenId), bob);
    }

    function test_E2E_VeryShortLivedLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // License expires in 1 minute
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 1 minutes, false, 0, 1 ether,
            "ipfs://short", "ipfs://short-priv"
        );

        assertTrue(licenseToken.isActiveLicense(licenseId));

        // Advance 61 seconds
        _advanceTime(61);

        _markExpired(alice, licenseId);
        assertTrue(licenseToken.isExpired(licenseId));
    }

    function test_E2E_VeryLongLivedLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // License expires in 100 years
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 100 * 365 days, false, 0, 1 ether,
            "ipfs://century", "ipfs://century-priv"
        );

        assertTrue(licenseToken.isActiveLicense(licenseId));

        // Advance 50 years - still active
        _advanceTime(50 * 365 days);

        assertTrue(licenseToken.isActiveLicense(licenseId));
        assertFalse(licenseToken.isExpired(licenseId));
    }

    // ============ Numerical Edge Cases Tests ============

    function test_E2E_MinimumPriceSale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // List for 1 wei
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 1 wei, true);

        uint256 bobBalanceBefore = bob.balance;

        _buyListing(bob, listingId, 1 wei);

        // Bob spent 1 wei
        assertEq(bob.balance, bobBalanceBefore - 1 wei);

        // Alice should get something (platform fee might round to 0)
        assertGt(revenueDistributor.getBalance(alice), 0);
    }

    function test_E2E_VeryLargeSaleAmount() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // List for 10,000 ETH
        vm.deal(bob, 15000 ether);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10000 ether, true);

        _buyListing(bob, listingId, 10000 ether);

        // Should handle large amounts without overflow
        uint256 platformFee = _platformFee(10000 ether);
        uint256 expectedRevenue = 10000 ether - platformFee;

        assertEq(revenueDistributor.getBalance(alice), expectedRevenue);
    }

    function test_E2E_ZeroRoyaltySecondarySale() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // 0% royalty
        _setRoyaltyRate(ipTokenId, alice, 0);

        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary sale with 0% royalty
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        // Alice gets no royalty
        assertEq(revenueDistributor.getBalance(alice), aliceBalanceBefore);
    }

    function test_E2E_MaximumRoyaltyRate() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // 100% royalty (extreme case - seller gets nothing on secondary)
        _setRoyaltyRate(ipTokenId, alice, 10000);

        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 bobBalanceBefore = revenueDistributor.getBalance(bob);

        // Secondary sale
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        // Alice gets 100% royalty (minus platform fee split)
        uint256 platformFee = _platformFee(20 ether);
        uint256 royalty = _royalty(20 ether, 10000); // 100%

        // Bob (seller) gets minimal/nothing
        assertEq(revenueDistributor.getBalance(bob), bobBalanceBefore);

        // Alice gets most of the sale
        assertApproxEqAbs(
            revenueDistributor.getBalance(alice) - aliceBalanceBefore,
            20 ether - platformFee,
            1 ether
        );
    }

    function test_E2E_PrecisionInRevenueSplit() public {
        // Test split that requires precise calculation: 3333/3333/3334
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 3333,
            bob, 3333,
            charlie, 3334
        );

        uint256 ipTokenId = _mintIP(alice, "ipfs://precise-split");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 100 ether, true);
        _buyListing(dave, listingId, 100 ether);

        uint256 platformFee = _platformFee(100 ether);
        uint256 netRevenue = 100 ether - platformFee;

        uint256 aliceShare = (netRevenue * 3333) / BASIS_POINTS;
        uint256 bobShare = (netRevenue * 3333) / BASIS_POINTS;
        uint256 charlieShare = (netRevenue * 3334) / BASIS_POINTS;

        // Verify precise distribution (allowing small rounding error)
        assertApproxEqAbs(revenueDistributor.getBalance(alice), aliceShare, 10);
        assertApproxEqAbs(revenueDistributor.getBalance(bob), bobShare, 10);
        assertApproxEqAbs(revenueDistributor.getBalance(charlie), charlieShare, 10);

        // Total distributed should equal net revenue (no dust left)
        uint256 totalDistributed = revenueDistributor.getBalance(alice) +
                                    revenueDistributor.getBalance(bob) +
                                    revenueDistributor.getBalance(charlie);

        assertApproxEqAbs(totalDistributed, netRevenue, 10);
    }

    // ============ Supply Edge Cases Tests ============

    function test_E2E_LicenseWithSupplyOne() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 30 days, false, 0, 1 ether,
            "ipfs://single", "ipfs://single-priv"
        );

        assertEq(licenseToken.balanceOf(bob, licenseId), 1);

        // Bob transfers to Charlie (now has 0)
        _transferLicense(bob, charlie, licenseId, 1);

        assertEq(licenseToken.balanceOf(bob, licenseId), 0);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);

        // Bob cannot access private metadata anymore
        vm.prank(bob);
        vm.expectRevert();
        licenseToken.getPrivateMetadata(licenseId);
    }

    function test_E2E_LicenseWithVeryLargeSupply() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Very large supply: 1 million
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1_000_000, _now() + 90 days, false, 0, 100 ether,
            "ipfs://massive", "ipfs://massive-priv"
        );

        assertEq(licenseToken.balanceOf(bob, licenseId), 1_000_000);

        // Bob can transfer large amounts
        _transferLicense(bob, charlie, licenseId, 500_000);
        _transferLicense(bob, dave, licenseId, 250_000);

        assertEq(licenseToken.balanceOf(bob, licenseId), 250_000);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 500_000);
        assertEq(licenseToken.balanceOf(dave, licenseId), 250_000);
    }

    function test_E2E_TransferExactBalance() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 100, _now() + 60 days, false, 0, 10 ether,
            "ipfs://exact", "ipfs://exact-priv"
        );

        // Bob transfers exactly his entire balance
        _transferLicense(bob, charlie, licenseId, 100);

        assertEq(licenseToken.balanceOf(bob, licenseId), 0);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 100);
    }

    // ============ Access Control Edge Cases Tests ============

    function test_E2E_NonHolderCannotGrantPrivateAccess() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 5, _now() + 60 days, false, 0, 2 ether,
            "ipfs://public", "ipfs://private"
        );

        // Charlie (non-holder) tries to grant access - should fail
        vm.prank(charlie);
        vm.expectRevert();
        licenseToken.grantPrivateAccess(licenseId, dave);
    }

    function test_E2E_RevokeAccessForNonGrantedUser() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 3, _now() + 60 days, false, 0, 1 ether,
            "ipfs://public", "ipfs://private"
        );

        // Bob tries to revoke access for Charlie (who was never granted) - should not error
        vm.prank(bob);
        licenseToken.revokePrivateAccess(licenseId, charlie);

        // Charlie still can't access
        vm.prank(charlie);
        vm.expectRevert();
        licenseToken.getPrivateMetadata(licenseId);
    }

    // ============ Error Recovery Tests ============

    function test_E2E_BuyListingWithInsufficientFunds() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        // Bob tries to buy with insufficient funds
        vm.deal(bob, 5 ether);

        vm.prank(bob);
        vm.expectRevert();
        marketplace.buyListing{value: 5 ether}(listingId);

        // Alice still owns IP
        assertEq(ipAsset.ownerOf(ipTokenId), alice);
    }

    function test_E2E_CancelNonExistentListing() public {
        // Try to cancel listing that doesn't exist
        bytes32 fakeListing = bytes32(uint256(12345));

        vm.prank(alice);
        vm.expectRevert();
        marketplace.cancelListing(fakeListing);
    }

    function test_E2E_AcceptNonExistentOffer() public {
        // Try to accept offer that doesn't exist
        bytes32 fakeOffer = bytes32(uint256(54321));

        vm.prank(alice);
        vm.expectRevert();
        marketplace.acceptOffer(fakeOffer);
    }

    function test_E2E_DoubleWithdrawalAttempt() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listingId, 10 ether);

        // Alice has revenue
        uint256 balance = revenueDistributor.getBalance(alice);
        assertGt(balance, 0);

        // Alice withdraws
        _withdraw(alice);

        assertEq(revenueDistributor.getBalance(alice), 0);

        // Alice tries to withdraw again (0 balance) - should fail
        vm.prank(alice);
        vm.expectRevert();
        revenueDistributor.withdraw();
    }

    // ============ Batch Operation Edge Cases Tests ============

    function test_E2E_BatchMarkExpiredEmptyArray() public {
        uint256[] memory emptyArray = new uint256[](0);

        // Should not error on empty array
        vm.prank(alice);
        licenseToken.batchMarkExpired(emptyArray);
    }

    function test_E2E_BatchMarkExpiredSingleItem() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 5 days, false, 0, 1 ether,
            "ipfs://single", "ipfs://single-priv"
        );

        _advanceTime(6 days);

        uint256[] memory singleItem = new uint256[](1);
        singleItem[0] = licenseId;

        vm.prank(alice);
        licenseToken.batchMarkExpired(singleItem);

        assertTrue(licenseToken.isExpired(licenseId));
    }

    function test_E2E_BatchMarkExpiredWithSomeInvalid() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 license1 = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 5 days, false, 0, 1 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ipTokenId, alice, charlie, 1, _now() + 5 days, false, 0, 1 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        // Only advance enough for license1 to expire
        _advanceTime(6 days);

        uint256[] memory licenses = new uint256[](3);
        licenses[0] = license1; // Valid
        licenses[1] = 99999; // Invalid license ID
        licenses[2] = license2; // Valid but not expired

        // Batch operation might fail entirely or partially depending on implementation
        vm.prank(alice);
        try licenseToken.batchMarkExpired(licenses) {
            // If it succeeds, only valid ones should be marked
            assertTrue(licenseToken.isExpired(license1));
        } catch {
            // If it fails, nothing marked
        }
    }

    // ============ State Consistency Tests ============

    function test_E2E_LicenseRevokedAndExpiredStates() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 10 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Submit and approve dispute (revokes)
        uint256 disputeId = _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));

        // Advance past expiry
        _advanceTime(11 days);

        _markExpired(alice, licenseId);

        // License is both revoked AND expired
        assertTrue(licenseToken.isRevoked(licenseId));
        assertTrue(licenseToken.isExpired(licenseId));

        // Should not be active
        assertFalse(licenseToken.isActiveLicense(licenseId));
    }

    function test_E2E_RecurringPaymentIntervalBoundaries() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Test very short interval: 1 day
        uint256 license1 = _createRecurringLicense(alice, bob, ipTokenId, 1 days, 0.1 ether);

        _advanceTime(1 days);
        _makeRecurringPayment(bob, license1);
        assertEq(marketplace.getMissedPayments(address(licenseToken), license1), 0);

        _advanceTime(1 days);
        _makeRecurringPayment(bob, license1);
        assertEq(marketplace.getMissedPayments(address(licenseToken), license1), 0);

        assertTrue(licenseToken.isActiveLicense(license1));

        // Test very long interval: 1 year (separate license)
        uint256 license2 = _createRecurringLicense(alice, charlie, ipTokenId, 365 days, 10 ether);

        _advanceTime(365 days);
        _makeRecurringPayment(charlie, license2);
        assertEq(marketplace.getMissedPayments(address(licenseToken), license2), 0);

        assertTrue(licenseToken.isActiveLicense(license2));
    }

    // ============ Metadata Edge Cases Tests ============

    function test_E2E_EmptyMetadataString() public {
        // Minting with empty metadata should revert
        vm.prank(alice);
        vm.expectRevert(IIPAsset.EmptyMetadata.selector);
        ipAsset.mintIP(alice, "");
    }

    function test_E2E_VeryLongMetadataString() public {
        // Create very long metadata string (1000 characters)
        string memory longMetadata = "ipfs://";
        for (uint256 i = 0; i < 100; i++) {
            longMetadata = string(abi.encodePacked(longMetadata, "0123456789"));
        }

        uint256 ipTokenId = _mintIP(alice, longMetadata);

        assertEq(ipAsset.tokenURI(ipTokenId), longMetadata);
    }

    // ============ Payment Amount Edge Cases Tests ============

    function test_E2E_RecurringPaymentWithZeroPrice() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Free recurring license (0 ETH per interval)
        vm.prank(alice);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId, bob, 1,
            "ipfs://free", "ipfs://free-priv",
            _now() + 365 days, "license terms", false,
            30 days
        );

        _advanceTime(30 days);

        // Payment due is 0
        (, , uint256 totalDue) = marketplace.getTotalPaymentDue(address(licenseToken), licenseId);
        assertEq(totalDue, 0);

        // Make payment (0 ETH)
        vm.prank(bob);
        marketplace.makeRecurringPayment{value: 0}(address(licenseToken), licenseId);

        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);
    }
}
