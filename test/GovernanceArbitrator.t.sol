// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/interfaces/IGovernanceArbitrator.sol";
import "../src/LicenseToken.sol";
import "../src/IPAsset.sol";
import "../src/RevenueDistributor.sol";
import "../src/base/ERC1967Proxy.sol";

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
    event DisputeResolved(
        uint256 indexed disputeId,
        bool approved,
        address indexed resolver,
        string reason
    );
    event LicenseRevoked(uint256 indexed licenseId, uint256 indexed disputeId);
    event DisputeOverdue(uint256 indexed disputeId, uint256 daysOverdue);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy contracts
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

        // Deploy proxies (need to deploy IPAsset proxy first to get address for RevenueDistributor)
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

        // Deploy RevenueDistributor with IPAsset address
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
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        arbitrator.grantRole(arbitrator.ARBITRATOR_ROLE(), arbitratorRole);
        
        vm.stopPrank();
        
        // Setup test license
        vm.prank(ipOwner);
        ipTokenId = ipAsset.mintIP(ipOwner, "ipfs://metadata");
        
        vm.prank(ipOwner);
        licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);
    }
    
    // ============ BR-005.1: Any party MAY submit disputes, and optional proof (document) may be included ============
    
    function testIPOwnerCanSubmitDispute() public {
        vm.prank(ipOwner);
        vm.expectEmit(true, true, true, true);
        emit DisputeSubmitted(0, licenseId, ipOwner, "License violation");
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "License violation",
            "ipfs://proof"
        );
        
        (,address submitter,,,,,,,,) = arbitrator.disputes(disputeId);
        assertEq(submitter, ipOwner);
    }
    
    function testLicenseeCanSubmitDispute() public {
        vm.prank(licensee);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Unfair terms",
            ""
        );
        
        (,address submitter,,,,,,,,) = arbitrator.disputes(disputeId);
        assertEq(submitter, licensee);
    }
    
    function testThirdPartyCanSubmitDispute() public {
        vm.prank(thirdParty);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Observed violation",
            "ipfs://evidence"
        );
        
        (,address submitter,,,,,,,,) = arbitrator.disputes(disputeId);
        assertEq(submitter, thirdParty);
    }
    
    function testSubmitDisputeWithOptionalProof() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            "ipfs://proof-document"
        );
        
        (,,,,string memory proofURI,,,,,) = arbitrator.disputes(disputeId);
        assertEq(proofURI, "ipfs://proof-document");
    }
    
    function testSubmitDisputeWithoutProof() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            "" // Empty proof
        );
        
        (,,,,string memory proofURI,,,,,) = arbitrator.disputes(disputeId);
        assertEq(proofURI, "");
    }
    
    // ============ BR-005.2: Disputes MAY only target active licenses ============
    
    function testCannotSubmitDisputeForInactiveLicense() public {
        // Revoke the license first
        vm.prank(address(arbitrator));
        licenseToken.revokeLicense(licenseId, "Test revocation");
        
        vm.prank(ipOwner);
        vm.expectRevert("License not active");
        arbitrator.submitDispute(licenseId, "Violation", "");
    }
    
    function testCannotSubmitDisputeForExpiredLicense() public {
        // Create expired license
        vm.prank(ipOwner);
        uint256 expiredLicenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 1 days,
            "worldwide",
            false, 0);
        
        vm.warp(block.timestamp + 2 days);
        licenseToken.markExpired(expiredLicenseId);
        
        vm.prank(ipOwner);
        vm.expectRevert("License not active");
        arbitrator.submitDispute(expiredLicenseId, "Violation", "");
    }
    
    // ============ BR-005.3: Disputes MUST include a reason ============
    
    function testCannotSubmitDisputeWithoutReason() public {
        vm.prank(ipOwner);
        vm.expectRevert("Reason required");
        arbitrator.submitDispute(licenseId, "", "ipfs://proof");
    }
    
    function testSubmitDisputeWithReason() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Unauthorized commercial use",
            ""
        );
        
        (,,,string memory reason,,,,,,) = arbitrator.disputes(disputeId);
        assertEq(reason, "Unauthorized commercial use");
    }
    
    // ============ BR-005.4: Only authorized arbitrators MAY resolve disputes ============
    
    function testOnlyArbitratorCanResolveDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        vm.prank(ipOwner);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        (,,,,,, IGovernanceArbitrator.DisputeStatus status,,,) = arbitrator.disputes(disputeId);
        assertTrue(status == IGovernanceArbitrator.DisputeStatus.Approved);
    }
    
    // ============ BR-005.5: Approved disputes MUST result in license revocation ============
    
    function testApprovedDisputeResultsInRevocation() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Violation confirmed");
        
        vm.prank(arbitratorRole);
        vm.expectEmit(true, true, false, false);
        emit LicenseRevoked(licenseId, disputeId);
        arbitrator.executeRevocation(disputeId);
        
        assertTrue(licenseToken.isRevoked(licenseId));
    }
    
    // ============ BR-005.6: Rejected disputes MUST NOT affect license status ============
    
    function testRejectedDisputeDoesNotAffectLicense() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );

        // Check license is not revoked before resolution
        assertFalse(licenseToken.isRevoked(licenseId));

        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "No evidence of violation");

        // Check license is still not revoked after rejection
        assertFalse(licenseToken.isRevoked(licenseId));
    }
    
    // ============ BR-005.7: Executed revocations MUST be permanent ============
    
    function testRevokedLicenseCannotBeReactivated() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);

        assertTrue(licenseToken.isRevoked(licenseId));
    }
    
    // ============ BR-005.8: Dispute resolutions MUST occur within 30 days ============
    
    function testCanResolveDisputeWithin30Days() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        // Fast forward 29 days
        vm.warp(block.timestamp + 29 days);
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        (,,,,,, IGovernanceArbitrator.DisputeStatus status,,,) = arbitrator.disputes(disputeId);
        assertTrue(status == IGovernanceArbitrator.DisputeStatus.Approved);
    }
    
    function testCannotResolveDisputeAfter30Days() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        // Fast forward 31 days
        vm.warp(block.timestamp + 31 days);
        
        vm.prank(arbitratorRole);
        vm.expectRevert("Dispute resolution overdue");
        arbitrator.resolveDispute(disputeId, true, "Approved");
    }
    
    function testIsDisputeOverdue() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        assertFalse(arbitrator.isDisputeOverdue(disputeId));
        
        vm.warp(block.timestamp + 31 days);
        
        assertTrue(arbitrator.isDisputeOverdue(disputeId));
    }
    
    function testGetTimeRemaining() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            ""
        );
        
        uint256 timeRemaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(timeRemaining, 30 days);
        
        vm.warp(block.timestamp + 10 days);
        
        timeRemaining = arbitrator.getTimeRemaining(disputeId);
        assertEq(timeRemaining, 20 days);
    }
    
    function testGetOverdueDisputes() public {
        // Create multiple disputes
        vm.prank(ipOwner);
        uint256 disputeId1 = arbitrator.submitDispute(licenseId, "Violation 1", "");
        
        vm.warp(block.timestamp + 1 days);
        
        vm.prank(ipOwner);
        uint256 disputeId2 = arbitrator.submitDispute(licenseId, "Violation 2", "");
        
        // Fast forward past deadline for first dispute
        vm.warp(block.timestamp + 30 days);
        
        uint256[] memory overdueDisputes = arbitrator.getOverdueDisputes();
        
        assertEq(overdueDisputes.length, 1);
        assertEq(overdueDisputes[0], disputeId1);
    }
    
    // ============ Additional Tests ============
    
    function testDisputeSubmittedEvent() public {
        vm.prank(ipOwner);
        vm.expectEmit(true, true, true, true);
        emit DisputeSubmitted(0, licenseId, ipOwner, "Violation");
        arbitrator.submitDispute(licenseId, "Violation", "ipfs://proof");
    }
    
    function testDisputeResolvedEvent() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        vm.prank(arbitratorRole);
        vm.expectEmit(true, false, false, true);
        emit DisputeResolved(disputeId, true, arbitratorRole, "Approved");
        arbitrator.resolveDispute(disputeId, true, "Approved");
    }
    
    function testGetDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Violation",
            "ipfs://proof"
        );
        
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);

        assertEq(dispute.licenseId, licenseId);
        assertEq(dispute.submitter, ipOwner);
        assertEq(dispute.reason, "Violation");
        assertEq(dispute.proofURI, "ipfs://proof");
        assertTrue(dispute.status == IGovernanceArbitrator.DisputeStatus.Pending);
    }
    
    function testGetDisputesForLicense() public {
        vm.prank(ipOwner);
        uint256 disputeId1 = arbitrator.submitDispute(licenseId, "Violation 1", "");
        
        vm.prank(licensee);
        uint256 disputeId2 = arbitrator.submitDispute(licenseId, "Violation 2", "");
        
        uint256[] memory disputes = arbitrator.getDisputesForLicense(licenseId);
        
        assertEq(disputes.length, 2);
        assertEq(disputes[0], disputeId1);
        assertEq(disputes[1], disputeId2);
    }
    
    function testCannotExecuteRevocationForRejectedDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");
        
        vm.prank(arbitratorRole);
        vm.expectRevert("Dispute not approved");
        arbitrator.executeRevocation(disputeId);
    }
    
    function testCannotExecuteRevocationForPendingDispute() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        vm.prank(arbitratorRole);
        vm.expectRevert("Dispute not approved");
        arbitrator.executeRevocation(disputeId);
    }
    
    function testCannotExecuteRevocationTwice() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
        
        vm.prank(arbitratorRole);
        vm.expectRevert("Already executed");
        arbitrator.executeRevocation(disputeId);
    }
    
    function testDisputeSetsIPAssetDisputeStatus() public {
        assertFalse(ipAsset.hasActiveDispute(ipTokenId));
        
        vm.prank(ipOwner);
        arbitrator.submitDispute(licenseId, "Violation", "");
        
        assertTrue(ipAsset.hasActiveDispute(ipTokenId));
    }
    
    function testResolvedDisputeClearsIPAssetDisputeStatus() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        assertTrue(ipAsset.hasActiveDispute(ipTokenId));
        
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, false, "Rejected");
        
        assertFalse(ipAsset.hasActiveDispute(ipTokenId));
    }
    
    function testCannotSubmitDisputeWhenPaused() public {
        vm.prank(admin);
        arbitrator.pause();
        
        vm.prank(ipOwner);
        vm.expectRevert();
        arbitrator.submitDispute(licenseId, "Violation", "");
    }
    
    function testCannotResolveDisputeWhenPaused() public {
        vm.prank(ipOwner);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        vm.prank(admin);
        arbitrator.pause();
        
        vm.prank(arbitratorRole);
        vm.expectRevert();
        arbitrator.resolveDispute(disputeId, true, "Approved");
    }
}

