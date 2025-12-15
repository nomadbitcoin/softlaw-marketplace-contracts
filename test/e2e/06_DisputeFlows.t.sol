// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title DisputeFlows E2E Tests
 * @notice Comprehensive end-to-end tests for dispute resolution functionality
 * @dev Tests cover:
 *      - Dispute submission by users
 *      - Dispute lifecycle (submitted, resolved, executed)
 *      - Multiple disputes on same license
 *      - Resolution outcomes (approve/reject)
 *      - Overdue disputes
 *      - Dispute validation
 *      NOTE: Resolution requires arbitrator role (production-like: external arbitrator)
 */
contract DisputeFlowsTest is E2ETestBase {

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

    // ============ Dispute Submission Tests ============

    function test_E2E_LicenseeSubmitsDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob submits dispute
        uint256 disputeId = _submitDispute(
            bob,
            licenseId,
            "IP owner violated license terms",
            "ipfs://evidence-proof"
        );

        // Verify dispute created
        assertEq(disputeId, 1);

        // Query dispute info
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.licenseId, licenseId);
        assertEq(dispute.submitter, bob);
        assertTrue(dispute.status == IGovernanceArbitrator.DisputeStatus.Pending);
    }

    function test_E2E_IPOwnerSubmitsDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Alice (IP owner) submits dispute
        uint256 disputeId = _submitDispute(
            alice,
            licenseId,
            "Licensee violated usage terms",
            "ipfs://violation-evidence"
        );

        assertEq(disputeId, 1);

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.submitter, alice);
    }

    function test_E2E_ThirdPartyCannotSubmitDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Charlie (unrelated party) tries to submit dispute - should fail
        vm.prank(charlie);
        vm.expectRevert();
        arbitrator.submitDispute(licenseId, "Irrelevant dispute", "ipfs://fake-proof");
    }

    function test_E2E_CannotDisputeNonExistentLicense() public {
        // Try to dispute license that doesn't exist
        vm.prank(bob);
        vm.expectRevert();
        arbitrator.submitDispute(99999, "Fake dispute", "ipfs://proof");
    }

    function test_E2E_CannotDisputeExpiredLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 7 days, false, 0, 1 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Advance past expiry and mark expired
        _advanceTime(8 days);
        _markExpired(alice, licenseId);

        // Bob tries to dispute expired license - should fail
        vm.prank(bob);
        vm.expectRevert();
        arbitrator.submitDispute(licenseId, "Dispute expired license", "ipfs://proof");
    }

    // ============ Multiple Disputes Tests ============

    function test_E2E_MultipleDisputesOnSameLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob submits first dispute
        uint256 dispute1 = _submitDispute(bob, licenseId, "Violation 1", "ipfs://proof1");

        // Alice submits second dispute
        uint256 dispute2 = _submitDispute(alice, licenseId, "Violation 2", "ipfs://proof2");

        assertEq(dispute1, 1);
        assertEq(dispute2, 2);

        // Query disputes for license
        uint256[] memory disputes = arbitrator.getDisputesForLicense(licenseId);
        assertEq(disputes.length, 2);
        assertEq(disputes[0], dispute1);
        assertEq(disputes[1], dispute2);
    }

    function test_E2E_SequentialDisputeResolution() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Submit 3 disputes
        uint256 dispute1 = _submitDispute(bob, licenseId, "Issue 1", "ipfs://proof1");
        uint256 dispute2 = _submitDispute(alice, licenseId, "Issue 2", "ipfs://proof2");
        uint256 dispute3 = _submitDispute(bob, licenseId, "Issue 3", "ipfs://proof3");

        // Arbitrator resolves dispute 1 (reject)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute1, false, "Rejected");

        IGovernanceArbitrator.Dispute memory d1 = arbitrator.getDispute(dispute1);
        assertTrue(d1.status == IGovernanceArbitrator.DisputeStatus.Rejected);

        // Arbitrator resolves dispute 2 (approve - revokes license)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute2, true, "Approved");

        // License should be revoked now
        assertTrue(licenseToken.isRevoked(licenseId));

        // Dispute 3 still pending (but license already revoked)
        IGovernanceArbitrator.Dispute memory d3 = arbitrator.getDispute(dispute3);
        assertFalse(d3.status != IGovernanceArbitrator.DisputeStatus.Pending);
    }

    // ============ Dispute Resolution Tests ============

    function test_E2E_DisputeApprovedRevokesLicense() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // License is active
        assertTrue(licenseToken.isActiveLicense(licenseId));
        assertFalse(licenseToken.isRevoked(licenseId));

        // Arbitrator approves dispute
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // License is now revoked
        assertTrue(licenseToken.isRevoked(licenseId));
        assertFalse(licenseToken.isActiveLicense(licenseId));

        // Dispute is resolved
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertTrue(dispute.status != IGovernanceArbitrator.DisputeStatus.Pending);
        assertTrue(dispute.status == IGovernanceArbitrator.DisputeStatus.Approved);
    }

    function test_E2E_DisputeRejectedLicenseStaysActive() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "False claim", "ipfs://weak-proof");

        // Arbitrator rejects dispute
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        // License stays active
        assertTrue(licenseToken.isActiveLicense(licenseId));
        assertFalse(licenseToken.isRevoked(licenseId));

        // Dispute is resolved
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertTrue(dispute.status != IGovernanceArbitrator.DisputeStatus.Pending);
        assertFalse(dispute.status == IGovernanceArbitrator.DisputeStatus.Approved);
    }

    function test_E2E_NonArbitratorCannotResolveDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Charlie (not arbitrator) tries to resolve - should fail
        vm.prank(charlie);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // Alice (IP owner) tries to resolve her own dispute - should fail
        vm.prank(alice);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        // Bob (disputant) tries to resolve - should fail
        vm.prank(bob);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // Dispute remains unresolved
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertFalse(dispute.status != IGovernanceArbitrator.DisputeStatus.Pending);
    }

    function test_E2E_CannotResolveAlreadyResolvedDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Arbitrator resolves
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // Try to resolve again - should fail
        vm.prank(arbitratorRole);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, false, "Rejected");
    }

    // ============ Dispute Timing Tests ============

    function test_E2E_DisputeResolvedBeforeDeadline() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Check dispute not overdue
        assertFalse(arbitrator.isDisputeOverdue(disputeId));

        // Advance 15 days (within 30-day resolution period)
        _advanceTime(15 days);

        assertFalse(arbitrator.isDisputeOverdue(disputeId));

        // Arbitrator resolves
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(arbitrator.getDispute(disputeId).status != IGovernanceArbitrator.DisputeStatus.Pending);
    }

    function test_E2E_DisputeBecomesOverdue() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Not overdue initially
        assertFalse(arbitrator.isDisputeOverdue(disputeId));

        // Advance 31 days (past 30-day deadline)
        _advanceTime(31 days);

        // Now overdue
        assertTrue(arbitrator.isDisputeOverdue(disputeId));

        // Can still be resolved even if overdue
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        assertTrue(arbitrator.getDispute(disputeId).status != IGovernanceArbitrator.DisputeStatus.Pending);
    }

    function test_E2E_QueryTimeRemainingForDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Initially ~30 days remaining
        uint256 timeRemaining = arbitrator.getTimeRemaining(disputeId);
        assertApproxEqAbs(timeRemaining, 30 days, 1);

        // Advance 10 days
        _advanceTime(10 days);

        // ~20 days remaining
        timeRemaining = arbitrator.getTimeRemaining(disputeId);
        assertApproxEqAbs(timeRemaining, 20 days, 1);

        // Advance 21 more days (past deadline)
        _advanceTime(21 days);

        // 0 time remaining (overdue)
        timeRemaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(timeRemaining, 0);
    }

    // ============ Dispute Impact on Operations Tests ============

    function test_E2E_CannotBurnIPWithPendingDispute() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 30 days, false, 0, 1 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Submit dispute
        _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Alice tries to burn IP - should fail (pending dispute)
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.burn(ipTokenId);

        // IP still exists
        assertEq(ipAsset.ownerOf(ipTokenId), alice);
    }

    function test_E2E_CanBurnIPAfterDisputeResolved() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 7 days, false, 0, 1 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(bob, licenseId, "Violation", "ipfs://proof");

        // Arbitrator resolves and revokes license
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // License expired and marked
        _advanceTime(8 days);
        _markExpired(alice, licenseId);

        // Now Alice can burn (dispute resolved, license expired)
        vm.prank(alice);
        ipAsset.burn(ipTokenId);

        vm.expectRevert();
        ipAsset.ownerOf(ipTokenId);
    }

    function test_E2E_RevokedLicenseFromDisputeCannotBeUsed() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 10, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 disputeId = _submitDispute(alice, licenseId, "Violation", "ipfs://proof");

        // Bob can transfer before revocation
        _transferLicense(bob, charlie, licenseId, 3);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 3);

        // Dispute approved - license revoked
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));

        // Bob cannot transfer revoked license
        vm.prank(bob);
        vm.expectRevert();
        licenseToken.safeTransferFrom(bob, dave, licenseId, 2, "");

        // Charlie cannot transfer either
        vm.prank(charlie);
        vm.expectRevert();
        licenseToken.safeTransferFrom(charlie, dave, licenseId, 1, "");
    }

    // ============ Dispute Query Tests ============

    function test_E2E_GetDisputeCountIncreases() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 license1 = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 2 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ipTokenId, alice, charlie, 1, _now() + 90 days, false, 0, 3 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        uint256 initialCount = arbitrator.getDisputeCount();

        _submitDispute(bob, license1, "Dispute 1", "ipfs://proof1");
        assertEq(arbitrator.getDisputeCount(), initialCount + 1);

        _submitDispute(charlie, license2, "Dispute 2", "ipfs://proof2");
        assertEq(arbitrator.getDisputeCount(), initialCount + 2);

        _submitDispute(alice, license1, "Dispute 3", "ipfs://proof3");
        assertEq(arbitrator.getDisputeCount(), initialCount + 3);
    }

    function test_E2E_GetDisputesForLicenseReturnsAll() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Submit multiple disputes
        uint256 d1 = _submitDispute(bob, licenseId, "Dispute 1", "ipfs://proof1");
        uint256 d2 = _submitDispute(alice, licenseId, "Dispute 2", "ipfs://proof2");
        uint256 d3 = _submitDispute(bob, licenseId, "Dispute 3", "ipfs://proof3");

        // Get all disputes for license
        uint256[] memory disputes = arbitrator.getDisputesForLicense(licenseId);

        assertEq(disputes.length, 3);
        assertEq(disputes[0], d1);
        assertEq(disputes[1], d2);
        assertEq(disputes[2], d3);
    }

    function test_E2E_GetDisputesForDifferentLicenses() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 license1 = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 2 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ipTokenId, alice, charlie, 1, _now() + 90 days, false, 0, 3 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        // License 1: 2 disputes
        _submitDispute(bob, license1, "L1 Dispute 1", "ipfs://l1-proof1");
        _submitDispute(alice, license1, "L1 Dispute 2", "ipfs://l1-proof2");

        // License 2: 1 dispute
        _submitDispute(charlie, license2, "L2 Dispute 1", "ipfs://l2-proof1");

        // Verify separate dispute lists
        uint256[] memory disputes1 = arbitrator.getDisputesForLicense(license1);
        uint256[] memory disputes2 = arbitrator.getDisputesForLicense(license2);

        assertEq(disputes1.length, 2);
        assertEq(disputes2.length, 1);
    }

    // ============ Complex Dispute Scenarios ============

    function test_E2E_DisputeOnRecurringLicenseAfterMissedPayments() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        // Recurring license - create through marketplace
        uint256 licenseId = _createRecurringLicense(alice, bob, ipTokenId, 30 days, 1 ether);

        // Bob makes 2 late payments - each resets consecutive count to 0
        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);
        _makeRecurringPayment(bob, licenseId);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        _advanceTime(30 days + 4 days);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 1);
        _makeRecurringPayment(bob, licenseId);
        assertEq(marketplace.getMissedPayments(address(licenseToken), licenseId), 0);

        // Alice submits dispute for payment violations
        uint256 disputeId = _submitDispute(alice, licenseId, "Repeated late payments", "ipfs://payment-proof");

        // Arbitrator approves dispute - revokes license
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        // License revoked, can't make more payments
        assertTrue(licenseToken.isRevoked(licenseId));

        _advanceTime(30 days);
        vm.prank(bob);
        vm.expectRevert();
        marketplace.makeRecurringPayment{value: 1 ether}(address(licenseToken), licenseId);
    }

    function test_E2E_DisputeDuringMarketplaceListing() public {
        uint256 ipTokenId = _createIPWithSplit(alice);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob lists license for sale
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);

        // Alice submits dispute
        uint256 disputeId = _submitDispute(alice, licenseId, "License violation", "ipfs://proof");

        // Charlie tries to buy - should succeed (dispute not yet resolved)
        _buyListing(charlie, listingId, 8 ether);

        // Charlie now owns the license
        assertEq(licenseToken.balanceOf(charlie, licenseId), 1);

        // Dispute gets resolved - revokes license (now affects Charlie)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        assertTrue(licenseToken.isRevoked(licenseId));

        // Charlie cannot transfer revoked license
        vm.prank(charlie);
        vm.expectRevert();
        licenseToken.safeTransferFrom(charlie, dave, licenseId, 1, "");
    }
}
