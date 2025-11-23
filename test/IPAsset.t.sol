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
    event MetadataUpdated(uint256 indexed tokenId, string oldURI, string newURI, uint256 timestamp);
    event LicenseMinted(uint256 indexed ipTokenId, uint256 indexed licenseId);
    event LicenseRegistered(
        uint256 indexed ipTokenId,
        uint256 indexed licenseId,
        address indexed licensee,
        uint256 supply,
        bool isExclusive
    );
    event RevenueSplitConfigured(uint256 indexed tokenId, address[] recipients, uint256[] shares);
    event DisputeStatusChanged(uint256 indexed tokenId, bool hasDispute);
    event LicenseTokenContractSet(address indexed newContract);
    event ArbitratorContractSet(address indexed newContract);
    event RevenueDistributorSet(address indexed newContract);
    
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
            address(0), // Will set after licenseToken deployment
            address(0)  // Will set after arbitrator deployment
        );
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        ipAsset = IPAsset(address(ipAssetProxy));

        // Deploy RevenueDistributor with IPAsset address (non-upgradeable)
        revenueDistributor = new RevenueDistributor(treasury, 250, 1000, address(ipAsset)); // 2.5% platform fee, 10% default royalty
        
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
        ipAsset.setRevenueDistributorContract(address(revenueDistributor));
        
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

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
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
    
    // ============ BR-001.4: Only the current owner MAY update IP metadata ============
    
    function testOwnerCanUpdateMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");

        vm.prank(creator);
        vm.expectEmit(true, false, false, false);
        emit MetadataUpdated(tokenId, "ipfs://metadata1", "ipfs://metadata2", block.timestamp);
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");

        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata2");
    }
    
    function testNonOwnerCannotUpdateMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.NotTokenOwner.selector));
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
    }
    
    function testMetadataUpdates() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");

        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata1");

        vm.startPrank(creator);
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata2");

        ipAsset.updateMetadata(tokenId, "ipfs://metadata3");
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata3");
        vm.stopPrank();
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
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.NotTokenOwner.selector));
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

        // Simulate active license by setting count directly (via LICENSE_MANAGER_ROLE)
        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 1);

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveLicenses.selector, tokenId, 1));
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
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveDispute.selector, tokenId));
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
        emit IPMinted(1, creator, "ipfs://metadata");
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
    
    function testLicenseCountTrackingViaRole() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        assertEq(ipAsset.activeLicenseCount(tokenId), 0);

        // Simulate license minting by updating count via LICENSE_MANAGER_ROLE
        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 1);

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


    function testMintIPRevertsOnZeroAddress() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.InvalidAddress.selector));
        ipAsset.mintIP(address(0), "ipfs://metadata");
    }

    function testMintIPRevertsOnEmptyMetadata() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.EmptyMetadata.selector));
        ipAsset.mintIP(creator, "");
    }

    function testUpdateMetadataRevertsOnEmptyMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.EmptyMetadata.selector));
        ipAsset.updateMetadata(tokenId, "");
    }

    function testTokenURIReturnsCurrentMetadata() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata1");

        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata1");

        vm.prank(creator);
        ipAsset.updateMetadata(tokenId, "ipfs://metadata2");

        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata2");
    }

    function testNonOwnerCannotBurn() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.NotTokenOwner.selector));
        ipAsset.burn(tokenId);
    }

    function testBurnCleansUpState() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        // Set up some state
        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 5);

        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(tokenId, true);

        // Verify state is set
        assertEq(ipAsset.activeLicenseCount(tokenId), 5);
        assertTrue(ipAsset.hasActiveDispute(tokenId));

        // Clear state to allow burn
        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, -5);

        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(tokenId, false);

        // Burn token
        vm.prank(creator);
        ipAsset.burn(tokenId);

        // Verify cleanup - token should not exist
        vm.expectRevert();
        ipAsset.ownerOf(tokenId);
    }

    function testDisputeStatusChangedEvent() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(address(arbitrator));
        vm.expectEmit(true, false, false, true);
        emit DisputeStatusChanged(tokenId, true);
        ipAsset.setDisputeStatus(tokenId, true);

        assertTrue(ipAsset.hasActiveDispute(tokenId));
    }

    function testUpdateActiveLicenseCountIncrement() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 3);

        assertEq(ipAsset.activeLicenseCount(tokenId), 3);
    }

    function testUpdateActiveLicenseCountDecrement() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 5);

        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, -2);

        assertEq(ipAsset.activeLicenseCount(tokenId), 3);
    }

    function testUpdateActiveLicenseCountUnderflowProtection() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(address(licenseToken));
        ipAsset.updateActiveLicenseCount(tokenId, 3);

        vm.prank(address(licenseToken));
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.LicenseCountUnderflow.selector, tokenId, 3, 5));
        ipAsset.updateActiveLicenseCount(tokenId, -5);
    }

    function testOwnerCanCreateLicense() public {
        vm.startPrank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.expectEmit(true, true, true, true);
        emit LicenseRegistered(tokenId, 0, licensee, 5, false);

        uint256 licenseId = ipAsset.mintLicense(
            tokenId,
            licensee,
            5, // supply
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,            "Commercial use license",
            false, // non-exclusive
            0 // one-time payment
        );

        assertEq(licenseId, 0); // Phase 1 returns placeholder
        assertEq(ipAsset.activeLicenseCount(tokenId), 5); // Count tracks supply
        vm.stopPrank();
    }

    function testNonOwnerCannotCreateLicense() public {
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(other);
        vm.expectRevert(IIPAsset.NotTokenOwner.selector);
        ipAsset.mintLicense(
            tokenId,
            licensee,
            5,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Commercial use license",
            false,
            0);
    }

    function testLicenseCountTracking() public {
        vm.startPrank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        assertEq(ipAsset.activeLicenseCount(tokenId), 0);

        ipAsset.mintLicense(tokenId, licensee, 5, "ipfs://public", "ipfs://private", block.timestamp + 365 days, "License 1", false, 0);
        assertEq(ipAsset.activeLicenseCount(tokenId), 5);

        ipAsset.mintLicense(tokenId, other, 3, "ipfs://public2", "ipfs://private2", block.timestamp + 365 days, "License 2", false, 0);
        assertEq(ipAsset.activeLicenseCount(tokenId), 8);

        vm.expectRevert(abi.encodeWithSelector(IIPAsset.HasActiveLicenses.selector, tokenId, 8));
        ipAsset.burn(tokenId);

        vm.stopPrank();
    }

    function testCannotMintLicenseWhenPaused() public {
        vm.startPrank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        vm.stopPrank();

        vm.prank(admin);
        ipAsset.pause();

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        ipAsset.mintLicense(
            tokenId,
            licensee,
            5,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "License",
            false, 0);
    }

    function testCannotMintLicenseToZeroAddress() public {
        vm.startPrank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.expectRevert(IIPAsset.InvalidAddress.selector);
        ipAsset.mintLicense(
            tokenId,
            address(0), // invalid licensee
            5,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "License",
            false,
            0
        );
        vm.stopPrank();
    }

    function testPauseUnpauseWorkflow() public {
        // Initially not paused
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        // Admin pauses
        vm.prank(admin);
        ipAsset.pause();

        // All state-changing functions blocked when paused
        vm.prank(creator);
        vm.expectRevert();
        ipAsset.mintIP(creator, "ipfs://metadata2");

        vm.prank(creator);
        vm.expectRevert();
        ipAsset.updateMetadata(tokenId, "ipfs://new");

        vm.prank(creator);
        vm.expectRevert();
        ipAsset.burn(tokenId);

        // Admin unpauses
        vm.prank(admin);
        ipAsset.unpause();

        // Operations work again
        vm.prank(creator);
        ipAsset.updateMetadata(tokenId, "ipfs://updated");
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://updated");
    }

    function testOnlyAdminCanPause() public {
        vm.prank(other);
        vm.expectRevert();
        ipAsset.pause();

        vm.prank(admin);
        ipAsset.pause(); // Should succeed
    }

    function testOnlyAdminCanUnpause() public {
        vm.prank(admin);
        ipAsset.pause();

        vm.prank(other);
        vm.expectRevert();
        ipAsset.unpause();

        vm.prank(admin);
        ipAsset.unpause(); // Should succeed
    }

    function testUpgrade() public {
        // Mint a token with original implementation
        vm.prank(creator);
        uint256 tokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        // Deploy new implementation
        IPAsset newImpl = new IPAsset();

        // Upgrade (only DEFAULT_ADMIN_ROLE can do this)
        vm.prank(admin);
        ipAsset.upgradeToAndCall(address(newImpl), "");

        // Verify state is preserved
        assertEq(ipAsset.ownerOf(tokenId), creator);
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://metadata");
    }

    function testOnlyAdminCanUpgrade() public {
        IPAsset newImpl = new IPAsset();

        vm.prank(other);
        vm.expectRevert();
        ipAsset.upgradeToAndCall(address(newImpl), "");

        vm.prank(admin);
        ipAsset.upgradeToAndCall(address(newImpl), ""); // Should succeed
    }

    function testSetLicenseTokenContract() public {
        address newLicenseToken = address(0x999);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit LicenseTokenContractSet(newLicenseToken);
        ipAsset.setLicenseTokenContract(newLicenseToken);

        assertEq(ipAsset.licenseTokenContract(), newLicenseToken);
    }

    function testSetLicenseTokenContractRevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.InvalidContractAddress.selector, address(0)));
        ipAsset.setLicenseTokenContract(address(0));
    }

    function testOnlyAdminCanSetLicenseTokenContract() public {
        address newLicenseToken = address(0x999);

        vm.prank(other);
        vm.expectRevert();
        ipAsset.setLicenseTokenContract(newLicenseToken);

        vm.prank(admin);
        ipAsset.setLicenseTokenContract(newLicenseToken); // Should succeed
    }

    function testSetArbitratorContract() public {
        address newArbitrator = address(0x888);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ArbitratorContractSet(newArbitrator);
        ipAsset.setArbitratorContract(newArbitrator);

        assertEq(ipAsset.arbitratorContract(), newArbitrator);
    }

    function testSetArbitratorContractRevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.InvalidContractAddress.selector, address(0)));
        ipAsset.setArbitratorContract(address(0));
    }

    function testOnlyAdminCanSetArbitratorContract() public {
        address newArbitrator = address(0x888);

        vm.prank(other);
        vm.expectRevert();
        ipAsset.setArbitratorContract(newArbitrator);

        vm.prank(admin);
        ipAsset.setArbitratorContract(newArbitrator); // Should succeed
    }

    function testSetRevenueDistributor() public {
        address newDistributor = address(0x777);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit RevenueDistributorSet(newDistributor);
        ipAsset.setRevenueDistributorContract(newDistributor);

        assertEq(ipAsset.revenueDistributor(), newDistributor);
    }

    function testSetRevenueDistributorRevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IIPAsset.InvalidContractAddress.selector, address(0)));
        ipAsset.setRevenueDistributorContract(address(0));
    }

    function testOnlyAdminCanSetRevenueDistributor() public {
        address newDistributor = address(0x777);

        vm.prank(other);
        vm.expectRevert();
        ipAsset.setRevenueDistributorContract(newDistributor);

        vm.prank(admin);
        ipAsset.setRevenueDistributorContract(newDistributor); // Should succeed
    }
}

