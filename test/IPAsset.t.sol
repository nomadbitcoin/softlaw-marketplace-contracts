// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/RevenueDistributor.sol";
import "../src/base/ERC1967Proxy.sol";

contract IPAssetTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    GovernanceArbitrator public arbitrator;
    RevenueDistributor public revenueDistributor;
    
    address public admin = address(1);
    address public creator = address(2);
    address public licensee = address(3);
    address public other = address(4);
    address public treasury = address(5);
    
    event IPMinted(uint256 indexed tokenId, address indexed owner, string metadataURI);
    event MetadataUpdated(uint256 indexed tokenId, uint256 version, string newURI);
    event LicenseMinted(uint256 indexed ipTokenId, uint256 indexed licenseId);
    event RevenueSplitConfigured(uint256 indexed tokenId, address[] recipients, uint256[] shares);
    event DisputeStatusChanged(uint256 indexed tokenId, bool hasDispute);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy implementations
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();
        
        // Deploy RevenueDistributor (non-upgradeable)
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000); // 2.5% platform fee, 10% default royalty
        
        // Deploy proxies
        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset",
            "IPA",
            admin,
            address(0), // Will set after licenseToken deployment
            address(0)  // Will set after arbitrator deployment
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));
        
        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://license.uri/",
            admin,
            address(ipAsset),
            address(0), // Will set after arbitrator deployment
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
        
        // Set contract references
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        
        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));
        
        vm.stopPrank();
    }
    
    // ============ BR-001.1: Each IP asset MUST have a unique identifier ============
    
    function testMintIPAssignsUniqueIdentifier() public {
        vm.startPrank(creator);
        
        uint256 tokenId1 = ipAsset.mintIP(creator, "ipfs://metadata1");
        uint256 tokenId2 = ipAsset.mintIP(creator, "ipfs://metadata2");
        
        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertTrue(tokenId1 != tokenId2);
        
        vm.stopPrank();
    }
    
    // ============ BR-001.2: IP assets MUST have exactly one owner at any time ============
    
    function testMintIPAssignsOwner() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        assertEq(ipAsset.ownerOf(tokenId), creator);
    }
    
    function testTransferChangesOwner() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        ipAsset.transferFrom(creator, other, tokenId);
        
        assertEq(ipAsset.ownerOf(tokenId), other);
    }
    
    // ============ BR-001.3: Only the current owner MAY create licenses for an IP asset ============
    
    function testOwnerCanCreateLicense() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            tokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000, // 10% royalty
            "worldwide",
            false
        );
        
        assertTrue(licenseId >= 0);
    }
    
    function testNonOwnerCannotCreateLicense() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(other);
        vm.expectRevert("Not token owner");
        ipAsset.mintLicense(
            tokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
    }
    
    // ============ BR-001.4: Only the current owner MAY update IP metadata ============
    
    function testOwnerCanUpdateMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");
        
        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit MetadataUpdated(tokenId, 1, "ipfs://metadata2");
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
        
        assertEq(ipAsset.metadataVersion(tokenId), 1);
    }
    
    function testNonOwnerCannotUpdateMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");
        
        vm.prank(other);
        vm.expectRevert("Not token owner");
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
    }
    
    function testMetadataVersioning() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");
        
        vm.startPrank(creator);
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
        ipAsset.updateMetadata(tokenId, "ipfs://metadata3");
        vm.stopPrank();
        
        assertEq(ipAsset.metadataVersion(tokenId), 2);
        assertEq(ipAsset.metadataHistory(tokenId, 0), "ipfs://metadata1");
        assertEq(ipAsset.metadataHistory(tokenId, 1), "ipfs://metadata2");
        assertEq(ipAsset.metadataHistory(tokenId, 2), "ipfs://metadata3");
    }
    
    // ============ BR-001.5: Only the current owner MAY configure revenue splits ============
    
    function testOwnerCanConfigureRevenueSplit() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        address[] memory recipients = new address[](2);
        recipients[0] = creator;
        recipients[1] = other;
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%
        
        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit RevenueSplitConfigured(tokenId, recipients, shares);
        ipAsset.configureRevenueSplit(tokenId, recipients, shares);
    }
    
    function testNonOwnerCannotConfigureRevenueSplit() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        address[] memory recipients = new address[](1);
        recipients[0] = creator;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(other);
        vm.expectRevert("Not token owner");
        ipAsset.configureRevenueSplit(tokenId, recipients, shares);
    }
    
    // ============ BR-001.6: IP assets MAY be transferred to any valid address ============
    
    function testTransferToValidAddress() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        ipAsset.transferFrom(creator, other, tokenId);
        
        assertEq(ipAsset.ownerOf(tokenId), other);
    }
    
    function testCannotTransferToZeroAddress() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        vm.expectRevert();
        ipAsset.transferFrom(creator, address(0), tokenId);
    }
    
    // ============ BR-001.7: IP assets MUST NOT be burned while active licenses exist ============
    
    function testCannotBurnWithActiveLicenses() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        ipAsset.mintLicense(
            tokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        vm.prank(creator);
        vm.expectRevert("Cannot burn: active licenses exist");
        ipAsset.burn(tokenId);
    }
    
    function testCanBurnWithoutActiveLicenses() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        ipAsset.burn(tokenId);
        
        vm.expectRevert();
        ipAsset.ownerOf(tokenId);
    }
    
    // ============ BR-001.8: IP assets MUST NOT be burned while in an active dispute resolution process ============
    
    function testCannotBurnWithActiveDispute() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        // Simulate active dispute
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(tokenId, true);
        
        vm.prank(creator);
        vm.expectRevert("Cannot burn: active dispute");
        ipAsset.burn(tokenId);
    }
    
    function testCanBurnAfterDisputeResolved() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        // Simulate active dispute
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(tokenId, true);
        
        // Resolve dispute
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(tokenId, false);
        
        vm.prank(creator);
        ipAsset.burn(tokenId);
        
        vm.expectRevert();
        ipAsset.ownerOf(tokenId);
    }
    
    // ============ Additional Tests ============
    
    function testMintIPEmitsEvent() public {
        vm.prank(creator);
        vm.expectEmit(true, true, false, true);
        emit IPMinted(0, creator, "ipfs://metadata");
        ipAsset.mintIP(creator, "ipfs://metadata");
    }
    
    function testMintIPWhenPaused() public {
        vm.prank(admin);
        ipAsset.pause();
        
        vm.prank(creator);
        vm.expectRevert();
        ipAsset.mintIP(creator, "ipfs://metadata");
    }
    
    function testUpdateMetadataWhenPaused() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");
        
        vm.prank(admin);
        ipAsset.pause();
        
        vm.prank(creator);
        vm.expectRevert();
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
    }
    
    function testLicenseCountTracking() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        assertEq(ipAsset.activeLicenseCount(tokenId), 0);
        
        vm.prank(creator);
        ipAsset.mintLicense(
            tokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            1000,
            "worldwide",
            false
        );
        
        assertEq(ipAsset.activeLicenseCount(tokenId), 1);
    }
    
    function testOnlyLicenseManagerCanUpdateLicenseCount() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(other);
        vm.expectRevert();
        ipAsset.updateActiveLicenseCount(tokenId, 1);
    }
    
    function testOnlyArbitratorCanSetDisputeStatus() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(other);
        vm.expectRevert();
        ipAsset.setDisputeStatus(tokenId, true);
    }
    
    function testSupportsInterface() public {
        // ERC721
        assertTrue(ipAsset.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(ipAsset.supportsInterface(0x5b5e139f));
        // AccessControl
        assertTrue(ipAsset.supportsInterface(0x7965db0b));
    }
}

