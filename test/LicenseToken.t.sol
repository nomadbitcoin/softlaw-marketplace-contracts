// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LicenseToken.sol";
import "../src/IPAsset.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/RevenueDistributor.sol";
import "../src/base/ERC1967Proxy.sol";

contract LicenseTokenTest is Test {
    LicenseToken public licenseToken;
    IPAsset public ipAsset;
    GovernanceArbitrator public arbitrator;
    RevenueDistributor public revenueDistributor;
    
    address public admin = address(1);
    address public creator = address(2);
    address public licensee = address(3);
    address public other = address(4);
    address public treasury = address(5);
    
    uint256 public ipTokenId;
    
    event LicenseCreated(
        uint256 indexed licenseId,
        uint256 indexed ipAssetId,
        address indexed licensee,
        bool isExclusive
    );
    event LicenseExpired(uint256 indexed licenseId);
    event LicenseRevoked(uint256 indexed licenseId, string reason);
    event PaymentRecorded(uint256 indexed licenseId, uint256 timestamp);
    event AutoRevoked(uint256 indexed licenseId, uint256 missedPayments);
    event PrivateAccessGranted(uint256 indexed licenseId, address indexed account);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy implementations
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();

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
        
        vm.stopPrank();
        
        // Mint an IP asset for testing
        vm.prank(creator);
        ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
    }
    
    // ============ BR-002.1: Licenses MUST be linked to a valid IP asset ============
    
    function testMintLicenseLinksToIPAsset() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        (uint256 linkedIpAssetId,,,,,,,) = licenseToken.licenses(licenseId);
        assertEq(linkedIpAssetId, ipTokenId);
    }
    
    function testCannotMintLicenseWithInvalidIPAsset() public {
        vm.prank(address(ipAsset));
        vm.expectRevert("Invalid IP asset");
        licenseToken.mintLicense(
            licensee,
            999, // Non-existent IP asset
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
    }
    
    // ============ BR-002.2: Exclusive licenses MUST have a supply of exactly 1 ============
    
    function testExclusiveLicenseHasSupplyOne() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            true // exclusive
        );
        
        assertEq(licenseToken.totalSupply(licenseId), 1);
    }
    
    function testCannotMintExclusiveLicenseWithSupplyGreaterThanOne() public {
        vm.prank(address(ipAsset));
        vm.expectRevert("Exclusive license must have supply of 1");
        licenseToken.mintLicense(
            licensee,
            ipTokenId,
            5, // Invalid for exclusive
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            true
        );
    }
    
    // ============ BR-002.3: Non-exclusive licenses MAY have any supply greater than 1 ============
    
    function testNonExclusiveLicenseCanHaveMultipleSupply() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            10,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false // non-exclusive
        );
        
        assertEq(licenseToken.totalSupply(licenseId), 10);
        assertEq(licenseToken.balanceOf(licensee, licenseId), 10);
    }
    
    // ============ BR-002.4: Only one exclusive license MAY exist per IP asset at a time ============
    
    function testCannotMintMultipleExclusiveLicenses() public {
        vm.prank(address(ipAsset));
        licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            true
        );
        
        vm.prank(address(ipAsset));
        vm.expectRevert("Exclusive license already exists for this IP");
        licenseToken.mintLicense(
            other,
            ipTokenId,
            1,
            "ipfs://public2",
            "ipfs://private2",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            true
        );
    }
    
    function testCanMintMultipleNonExclusiveLicenses() public {
        vm.prank(address(ipAsset));
        uint256 licenseId1 = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            5,
            "ipfs://public1",
            "ipfs://private1",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        vm.prank(address(ipAsset));
        uint256 licenseId2 = licenseToken.mintLicense(
            other,
            ipTokenId,
            3,
            "ipfs://public2",
            "ipfs://private2",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        assertTrue(licenseId1 != licenseId2);
    }
    
    // ============ BR-002.5: Licenses MUST have an expiry timestamp ============
    
    function testLicenseHasExpiryTimestamp() public {
        uint256 expiryTime = block.timestamp + 365 days;
        
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            expiryTime,
            1000,
            "worldwide",
            false
        );
        
        (,uint256 storedExpiry,,,,,,) = licenseToken.licenses(licenseId);
        assertEq(storedExpiry, expiryTime);
    }
    
    // ============ BR-002.6: Expired licenses MUST NOT be transferable ============
    
    function testCannotTransferExpiredLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 1 days,
            1000,
            "worldwide",
            false
        );
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);
        
        // Mark as expired
        licenseToken.markExpired(licenseId);
        
        vm.prank(licensee);
        vm.expectRevert("License expired");
        licenseToken.safeTransferFrom(licensee, other, licenseId, 1, "");
    }
    
    // ============ BR-002.7: Revoked licenses MUST NOT be transferable ============
    
    function testCannotTransferRevokedLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Revoke license
        vm.prank(address(arbitrator));
        licenseToken.revokeLicense(licenseId, "Violation");
        
        vm.prank(licensee);
        vm.expectRevert("License revoked");
        licenseToken.safeTransferFrom(licensee, other, licenseId, 1, "");
    }
    
    // ============ BR-002.8: Active licenses MAY only be revoked through dispute resolution ============
    
    function testOnlyArbitratorCanRevokeLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        vm.prank(creator);
        vm.expectRevert();
        licenseToken.revokeLicense(licenseId, "Violation");
        
        vm.prank(address(arbitrator));
        licenseToken.revokeLicense(licenseId, "Violation");
        
        assertTrue(licenseToken.isRevoked(licenseId));
    }
    
    // ============ BR-002.9: Expired licenses MAY be marked inactive by anyone ============
    
    function testAnyoneCanMarkExpiredLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 1 days,
            1000,
            "worldwide",
            false
        );
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 days);
        
        // Anyone can mark as expired
        vm.prank(other);
        vm.expectEmit(true, false, false, false);
        emit LicenseExpired(licenseId);
        licenseToken.markExpired(licenseId);
        
        assertTrue(licenseToken.isExpired(licenseId));
    }
    
    function testCannotMarkNonExpiredLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        vm.prank(other);
        vm.expectRevert("License not yet expired");
        licenseToken.markExpired(licenseId);
    }
    
    function testBatchMarkExpired() public {
        uint256[] memory licenseIds = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(address(ipAsset));
            licenseIds[i] = licenseToken.mintLicense(
                licensee,
                ipTokenId,
                1,
                "ipfs://public",
                "ipfs://private",
                block.timestamp + 1 days,
                1000,
                "worldwide",
                false
            );
        }
        
        vm.warp(block.timestamp + 2 days);
        
        licenseToken.batchMarkExpired(licenseIds);
        
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(licenseToken.isExpired(licenseIds[i]));
        }
    }
    
    // ============ BR-002.10: An automatic revocation happens when there are more than 3 missing payments ============
    
    function testAutoRevokeAfterThreeMissedPayments() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Simulate 3 missed payments
        vm.startPrank(address(licenseToken));
        licenseToken.recordMissedPayment(licenseId);
        licenseToken.recordMissedPayment(licenseId);
        licenseToken.recordMissedPayment(licenseId);
        vm.stopPrank();
        
        // Check should trigger auto-revoke
        vm.expectEmit(true, false, false, true);
        emit AutoRevoked(licenseId, 3);
        licenseToken.checkAndRevokeForMissedPayments(licenseId);
        
        assertTrue(licenseToken.isRevoked(licenseId));
    }
    
    function testRecordPaymentResetsMissedCount() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Simulate 2 missed payments
        vm.startPrank(address(licenseToken));
        licenseToken.recordMissedPayment(licenseId);
        licenseToken.recordMissedPayment(licenseId);
        vm.stopPrank();
        
        // Record successful payment
        vm.prank(licensee);
        vm.expectEmit(true, false, false, true);
        emit PaymentRecorded(licenseId, block.timestamp);
        licenseToken.recordPayment(licenseId);
        
        (,uint256 missedPayments,,) = licenseToken.paymentSchedules(licenseId);
        assertEq(missedPayments, 0);
    }
    
    function testNoAutoRevokeWithThreeOrFewerMissedPayments() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Simulate exactly 3 missed payments (not more than 3)
        vm.startPrank(address(licenseToken));
        licenseToken.recordMissedPayment(licenseId);
        licenseToken.recordMissedPayment(licenseId);
        licenseToken.recordMissedPayment(licenseId);
        vm.stopPrank();
        
        // Should not auto-revoke yet (needs MORE than 3)
        licenseToken.checkAndRevokeForMissedPayments(licenseId);
        assertFalse(licenseToken.isRevoked(licenseId));
        
        // One more missed payment
        vm.prank(address(licenseToken));
        licenseToken.recordMissedPayment(licenseId);
        
        // Now should auto-revoke
        licenseToken.checkAndRevokeForMissedPayments(licenseId);
        assertTrue(licenseToken.isRevoked(licenseId));
    }
    
    // ============ BR-002.11: Each License MUST include two metadata references ============
    
    function testLicenseHasDualMetadata() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public-metadata",
            "ipfs://private-metadata",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        (,,,,,, string memory publicURI, string memory privateURI) = licenseToken.licenses(licenseId);
        assertEq(publicURI, "ipfs://public-metadata");
        assertEq(privateURI, "ipfs://private-metadata");
    }
    
    function testPublicMetadataAccessibleToAll() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public-metadata",
            "ipfs://private-metadata",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Anyone can access public metadata
        vm.prank(other);
        string memory publicMetadata = licenseToken.getPublicMetadata(licenseId);
        assertEq(publicMetadata, "ipfs://public-metadata");
    }
    
    function testPrivateMetadataRestrictedToAuthorized() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public-metadata",
            "ipfs://private-metadata",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Owner can access
        vm.prank(licensee);
        string memory privateMetadata = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateMetadata, "ipfs://private-metadata");
        
        // Non-owner cannot access
        vm.prank(other);
        vm.expectRevert("Not authorized to access private metadata");
        licenseToken.getPrivateMetadata(licenseId);
    }
    
    function testGrantPrivateMetadataAccess() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public-metadata",
            "ipfs://private-metadata",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        // Grant access to another address
        vm.prank(licensee);
        vm.expectEmit(true, true, false, false);
        emit PrivateAccessGranted(licenseId, other);
        licenseToken.grantPrivateAccess(licenseId, other);
        
        // Now other can access
        vm.prank(other);
        string memory privateMetadata = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateMetadata, "ipfs://private-metadata");
    }
    
    // ============ Additional Tests ============
    
    function testOnlyIPAssetCanMintLicense() public {
        vm.prank(creator);
        vm.expectRevert();
        licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
    }
    
    function testLicenseCreatedEvent() public {
        vm.prank(address(ipAsset));
        vm.expectEmit(true, true, true, true);
        emit LicenseCreated(0, ipTokenId, licensee, false);
        licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
    }
    
    function testCanTransferActiveLicense() public {
        vm.prank(address(ipAsset));
        uint256 licenseId = licenseToken.mintLicense(
            licensee,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        vm.prank(licensee);
        licenseToken.safeTransferFrom(licensee, other, licenseId, 1, "");
        
        assertEq(licenseToken.balanceOf(other, licenseId), 1);
        assertEq(licenseToken.balanceOf(licensee, licenseId), 0);
    }
    
    function testSupportsInterface() public {
        // ERC1155
        assertTrue(licenseToken.supportsInterface(0xd9b67a26));
        // AccessControl
        assertTrue(licenseToken.supportsInterface(0x7965db0b));
    }
}

