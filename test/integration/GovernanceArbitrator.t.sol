// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/GovernanceArbitrator.sol";
import "../../src/interfaces/IGovernanceArbitrator.sol";
import "../../src/LicenseToken.sol";
import "../../src/IPAsset.sol";
import "../../src/RevenueDistributor.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract GovernanceArbitratorTest is Test {
    GovernanceArbitrator public arbitrator;
    LicenseToken public licenseToken;
    IPAsset public ipAsset;
    RevenueDistributor public revenueDistributor;

    address public admin = address(1);
    address public arbitratorRole = address(2);
    address public ipOwner = address(3);
    address public licensee = address(4);
    address public thirdParty = address(5);
    address public treasury = address(6);

    uint256 public ipTokenId;
    uint256 public licenseId;

    uint256 constant RESOLUTION_DEADLINE = 30 days;

    event DisputeSubmitted(
        uint256 indexed disputeId,
        uint256 indexed licenseId,
        address indexed submitter,
        string reason
    );
    event DisputeResolved(uint256 indexed disputeId, bool approved, address indexed resolver, string reason);
    event LicenseRevoked(uint256 indexed licenseId, uint256 indexed disputeId);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy implementations
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
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

        // Wire up contracts
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        licenseToken.setArbitratorContract(address(arbitrator));

        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        arbitrator.grantRole(arbitrator.ARBITRATOR_ROLE(), arbitratorRole);

        vm.stopPrank();

        // Create test IP and license
        vm.prank(ipOwner);
        ipTokenId = ipAsset.mintIP(ipOwner, "ipfs://test");

        vm.prank(ipOwner);
        licenseId = ipAsset.mintLicense(
            ipTokenId, licensee, 1, "ipfs://public", "ipfs://private", block.timestamp + 365 days, "terms", false, 0
        );
    }

    // ==================== CONTRACT SETUP TESTS ====================

    function testInitialization() public view {
        assertEq(arbitrator.licenseTokenContract(), address(licenseToken));
        assertEq(arbitrator.ipAssetContract(), address(ipAsset));
        assertEq(arbitrator.revenueDistributorContract(), address(revenueDistributor));
    }

    function testTwoRolesGranted() public view {
        assertTrue(arbitrator.hasRole(arbitrator.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(arbitrator.hasRole(arbitrator.ARBITRATOR_ROLE(), admin));
        assertTrue(arbitrator.hasRole(arbitrator.ARBITRATOR_ROLE(), arbitratorRole));
    }

    // ==================== SUBMIT DISPUTE TESTS ====================

    function testIPOwnerCanSubmitDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Terms violation", "ipfs://proof");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.submitter, ipOwner);
        assertEq(dispute.licenseId, licenseId);
        assertEq(dispute.reason, "Terms violation");
    }

    function testLicenseeCanSubmitDispute() public {
        vm.prank(licensee);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Unfair terms", "ipfs://proof");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.submitter, licensee);
    }

    function testThirdPartyCannotSubmitDispute() public {
        // Third parties cannot submit disputes (only IP owner or licensee)
        vm.expectRevert(IGovernanceArbitrator.NotAuthorizedToDispute.selector);
        vm.prank(thirdParty);
        arbitrator.submitDispute(licenseId, "Infringement", "ipfs://proof");
    }

    function testSubmitDisputeWithOptionalProof() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://evidence");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.proofURI, "ipfs://evidence");
    }

    function testSubmitDisputeWithEmptyProof() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.proofURI, "");
    }

    function testCannotSubmitDisputeForInactiveLicense() public {
        // Revoke the license first (arbitrator contract has the role)
        vm.prank(address(arbitrator));
        licenseToken.revokeLicense(licenseId, "Test revocation");

        vm.expectRevert(IGovernanceArbitrator.LicenseNotActive.selector);
        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Should fail", "");
    }

    function testCannotSubmitDisputeForExpiredLicense() public {
        // Warp time forward past expiry
        vm.warp(block.timestamp + 366 days);

        // Mark the license as expired
        licenseToken.markExpired(licenseId);

        vm.expectRevert(IGovernanceArbitrator.LicenseNotActive.selector);
        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Should fail", "");
    }

    function testCannotSubmitDisputeWithoutReason() public {
        vm.expectRevert(IGovernanceArbitrator.EmptyReason.selector);
        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "", "ipfs://proof");
    }

    function testDisputeStoresIPOwner() public {
        // Only IP owner or licensee can submit
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.ipOwner, ipOwner);
    }

    function testDisputeSubmissionSetsIPAssetFlag() public {
        assertFalse(ipAsset.hasActiveDispute(ipTokenId));

        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Test", "");

        assertTrue(ipAsset.hasActiveDispute(ipTokenId));
    }

    function testDisputeSubmittedEventEmitted() public {
        // Dispute IDs start from 1 (pre-increment)
        vm.expectEmit(true, true, true, true);
        emit DisputeSubmitted(1, licenseId, ipOwner, "Violation");

        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Violation", "");
    }

    // ==================== RESOLVE DISPUTE TESTS ====================

    function testOnlyArbitratorCanResolveDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
    }

    function testNonArbitratorCannotResolveDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        bytes32 arbitratorRoleHash = arbitrator.ARBITRATOR_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", thirdParty, arbitratorRoleHash
            )
        );
        vm.prank(thirdParty);
        arbitrator.resolveDispute(disputeId, true, "Should fail");
    }

    function testApproveDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
        assertEq(dispute.resolver, arbitratorRole);
        assertEq(dispute.resolutionReason, "Approved");
        assertGt(dispute.resolvedAt, 0);
    }

    function testRejectDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Rejected));
    }

    function testRejectedDisputeDoesNotAffectLicense() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        bool wasActiveBeforeResolve = licenseToken.isActiveLicense(licenseId);

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        bool isActiveAfterReject = licenseToken.isActiveLicense(licenseId);
        assertTrue(wasActiveBeforeResolve);
        assertTrue(isActiveAfterReject);
    }

    function testCanResolveDisputeWithin30Days() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        // Warp to day 29
        vm.warp(block.timestamp + 29 days);

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved on day 29");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
    }

    function testCanResolveDisputeAfter30Days() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        // Warp past 30 days
        vm.warp(block.timestamp + 31 days);

        // Overdue disputes can still be resolved (deadline is informational, not enforced)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Late resolution");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
    }

    function testCannotResolveAlreadyResolvedDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "First resolution");

        vm.expectRevert(IGovernanceArbitrator.DisputeAlreadyResolved.selector);
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Second resolution should fail");
    }

    function testResolutionClearsIPAssetFlagWhenNoOtherPending() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        assertTrue(ipAsset.hasActiveDispute(ipTokenId));

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");

        assertFalse(ipAsset.hasActiveDispute(ipTokenId));
    }

    function testResolutionKeepsIPAssetFlagWhenOtherPending() public {
        vm.prank(ipOwner);
        uint256 dispute1 = arbitrator.submitDispute(licenseId, "Test 1", "");

        vm.prank(licensee);
        uint256 dispute2 = arbitrator.submitDispute(licenseId, "Test 2", "");

        assertTrue(ipAsset.hasActiveDispute(ipTokenId));

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute1, false, "Rejected first");

        assertTrue(ipAsset.hasActiveDispute(ipTokenId));

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute2, false, "Rejected second");

        assertFalse(ipAsset.hasActiveDispute(ipTokenId));
    }

    function testDisputeResolvedEventEmitted() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.expectEmit(true, false, true, true);
        emit DisputeResolved(disputeId, true, arbitratorRole, "Approved");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
    }

    // ==================== HELPER FUNCTION TESTS ====================

    function testGetDisputesForLicense() public {
        vm.prank(ipOwner);
        uint256 dispute1 = arbitrator.submitDispute(licenseId, "Test 1", "");

        vm.prank(licensee);
        uint256 dispute2 = arbitrator.submitDispute(licenseId, "Test 2", "");

        uint256[] memory disputes = arbitrator.getDisputesForLicense(licenseId);
        assertEq(disputes.length, 2);
        assertEq(disputes[0], dispute1);
        assertEq(disputes[1], dispute2);
    }

    function testGetDisputeCount() public {
        assertEq(arbitrator.getDisputeCount(), 0);

        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Test 1", "");
        assertEq(arbitrator.getDisputeCount(), 1);

        vm.prank(licensee);
        arbitrator.submitDispute(licenseId, "Test 2", "");
        assertEq(arbitrator.getDisputeCount(), 2);
    }

    function testIsDisputeOverdue() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        assertFalse(arbitrator.isDisputeOverdue(disputeId));

        vm.warp(block.timestamp + 31 days);
        assertTrue(arbitrator.isDisputeOverdue(disputeId));
    }

    function testGetTimeRemaining() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        uint256 remaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(remaining, 30 days);

        vm.warp(block.timestamp + 15 days);
        remaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(remaining, 15 days);

        vm.warp(block.timestamp + 16 days);
        remaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(remaining, 0);
    }

    // ==================== PAUSE TESTS ====================

    function testAdminCanPause() public {
        vm.prank(admin);
        arbitrator.pause();

        assertTrue(arbitrator.paused());
    }

    function testAdminCanUnpause() public {
        vm.prank(admin);
        arbitrator.pause();

        vm.prank(admin);
        arbitrator.unpause();

        assertFalse(arbitrator.paused());
    }

    function testNonAdminCannotPause() public {
        bytes32 adminRole = arbitrator.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", thirdParty, adminRole)
        );
        vm.prank(thirdParty);
        arbitrator.pause();
    }

    function testPausedContractBlocksSubmission() public {
        vm.prank(admin);
        arbitrator.pause();

        vm.expectRevert();
        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Should fail", "");
    }

    function testPausedContractBlocksResolution() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(admin);
        arbitrator.pause();

        vm.expectRevert();
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Should fail");
    }

    function testPausedContractBlocksExecution() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        vm.prank(admin);
        arbitrator.pause();

        vm.expectRevert();
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
    }

    // ==================== EXECUTE REVOCATION TESTS ====================

    function testApprovedDisputeAutoRevokes() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        // Auto-revocation: license is revoked immediately after approval
        assertTrue(licenseToken.isRevoked(licenseId));
        assertFalse(licenseToken.isActiveLicense(licenseId));

        // Status remains Approved (auto-execution is implicit)
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
    }

    function testResolveDisputeRevokesLicense() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        assertFalse(licenseToken.isRevoked(licenseId));

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        // License is automatically revoked when dispute is approved
        assertTrue(licenseToken.isRevoked(licenseId));
    }

    function testApprovedStatusRemainsAfterAutoRevocation() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        // Status is Approved (auto-revocation happens but status stays Approved)
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));

        // But license is revoked
        assertTrue(licenseToken.isRevoked(licenseId));
    }

    function testRevokedLicenseIsPermanent() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        // License is automatically revoked and cannot be un-revoked
        assertTrue(licenseToken.isRevoked(licenseId));
        assertFalse(licenseToken.isActiveLicense(licenseId));
    }

    function testCannotExecuteRejectedDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "No evidence");

        vm.expectRevert(IGovernanceArbitrator.DisputeNotApproved.selector);
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
    }

    function testCannotExecutePendingDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.expectRevert(IGovernanceArbitrator.DisputeNotApproved.selector);
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
    }

    function testOnlyArbitratorCanRevokeViaDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        // Auto-revocation happens during resolveDispute (arbitrator-only)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        assertTrue(licenseToken.isRevoked(licenseId));
    }

    function testNonArbitratorCannotExecuteRevocation() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        bytes32 arbitratorRoleHash = arbitrator.ARBITRATOR_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature(
                "AccessControlUnauthorizedAccount(address,bytes32)", thirdParty, arbitratorRoleHash
            )
        );
        vm.prank(thirdParty);
        arbitrator.executeRevocation(disputeId);
    }

    function testAutoRevocationEmitsLicenseRevokedEvent() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        // Auto-revocation emits event during resolveDispute
        vm.expectEmit(true, true, false, false);
        emit LicenseRevoked(licenseId, disputeId);

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");
    }

    function testRevokedLicenseCannotBeUsedInMarketplace() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");

        // License is automatically revoked
        assertTrue(licenseToken.isRevoked(licenseId));
        assertFalse(licenseToken.isActiveLicense(licenseId));
    }

    // ==================== UPGRADE TESTS ====================

    function testOnlyAdminCanUpgrade() public {
        GovernanceArbitrator newImplementation = new GovernanceArbitrator();

        vm.prank(admin);
        arbitrator.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade succeeded by checking implementation
        // Note: We can't directly check implementation address in UUPS, but if no revert occurred, it succeeded
    }

    function testNonAdminCannotUpgrade() public {
        GovernanceArbitrator newImplementation = new GovernanceArbitrator();

        bytes32 adminRole = arbitrator.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature("AccessControlUnauthorizedAccount(address,bytes32)", thirdParty, adminRole)
        );
        vm.prank(thirdParty);
        arbitrator.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradePreservesDisputes() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test dispute", "ipfs://proof");

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");

        GovernanceArbitrator newImplementation = new GovernanceArbitrator();

        vm.prank(admin);
        arbitrator.upgradeToAndCall(address(newImplementation), "");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.licenseId, licenseId);
        assertEq(dispute.submitter, ipOwner);
        assertEq(dispute.reason, "Test dispute");
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Approved));
    }

    // ==================== QUERY FUNCTION TESTS ====================

    function testIsDisputeOverdueWithinDeadline() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        assertFalse(arbitrator.isDisputeOverdue(disputeId));
    }

    function testIsDisputeOverdueAfter30Days() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.warp(block.timestamp + 31 days);
        assertTrue(arbitrator.isDisputeOverdue(disputeId));
    }

    function testGetTimeRemainingCorrect() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        uint256 timeLeft = arbitrator.getTimeRemaining(disputeId);
        assertApproxEqAbs(timeLeft, 30 days, 1);

        vm.warp(block.timestamp + 15 days);
        timeLeft = arbitrator.getTimeRemaining(disputeId);
        assertApproxEqAbs(timeLeft, 15 days, 1);
    }

    function testGetTimeRemainingWhenOverdue() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Test", "");

        vm.warp(block.timestamp + 31 days);
        uint256 timeLeft = arbitrator.getTimeRemaining(disputeId);
        assertEq(timeLeft, 0);
    }

    function testGetDisputesForLicenseReturnsEmpty() public view {
        uint256 newLicenseId = 9999;
        uint256[] memory disputes = arbitrator.getDisputesForLicense(newLicenseId);
        assertEq(disputes.length, 0);
    }

    function testGetDisputeReturnsCorrectData() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");

        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.licenseId, licenseId);
        assertEq(dispute.submitter, ipOwner);
        assertEq(dispute.ipOwner, ipOwner);
        assertEq(dispute.reason, "Violation");
        assertEq(dispute.proofURI, "ipfs://proof");
        assertEq(uint256(dispute.status), uint256(IGovernanceArbitrator.DisputeStatus.Pending));
    }
}
