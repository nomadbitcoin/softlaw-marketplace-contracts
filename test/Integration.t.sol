// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/Marketplace.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/interfaces/IGovernanceArbitrator.sol";
import "../src/base/ERC1967Proxy.sol";

contract IntegrationTest is Test {
    IPAsset public ipAsset;
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    RevenueDistributor public revenueDistributor;
    GovernanceArbitrator public arbitrator;
    
    address public admin = address(1);
    address public creator = address(2);
    address public licensee = address(3);
    address public buyer = address(4);
    address public collaborator = address(5);
    address public treasury = address(6);
    address public arbitratorRole = address(7);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy all contracts
        IPAsset ipAssetImpl = new IPAsset();
        LicenseToken licenseTokenImpl = new LicenseToken();
        Marketplace marketplaceImpl = new Marketplace();
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

        // Deploy RevenueDistributor after IPAsset proxy
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
        
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            admin,
            address(revenueDistributor),
            250,
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
        
        // Set contract references
        ipAsset.setLicenseTokenContract(address(licenseToken));
        ipAsset.setArbitratorContract(address(arbitrator));
        licenseToken.setArbitratorContract(address(arbitrator));
        
        // Grant roles
        ipAsset.grantRole(ipAsset.LICENSE_MANAGER_ROLE(), address(licenseToken));
        ipAsset.grantRole(ipAsset.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.ARBITRATOR_ROLE(), address(arbitrator));
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));
        arbitrator.grantRole(arbitrator.ARBITRATOR_ROLE(), arbitratorRole);
        revenueDistributor.grantRole(revenueDistributor.CONFIGURATOR_ROLE(), admin);
        
        vm.stopPrank();
        
        // Fund accounts
        vm.deal(buyer, 100 ether);
        vm.deal(licensee, 100 ether);
    }
    
    // ============ Full IP Creation to Licensing Workflow ============
    
    function testCompleteIPCreationAndLicensingWorkflow() public {
        // 1. Creator mints IP asset
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://ip-metadata");
        assertEq(ipAsset.ownerOf(ipTokenId), creator);
        
        // 2. Creator configures revenue split
        address[] memory recipients = new address[](2);
        recipients[0] = creator;
        recipients[1] = collaborator;
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%
        
        vm.prank(admin);
        revenueDistributor.configureSplit(ipTokenId, recipients, shares);
        
        // 3. Creator creates license
        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            5,
            "ipfs://public-terms",
            "ipfs://private-terms",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);
        
        assertEq(licenseToken.balanceOf(licensee, licenseId), 5);
        
        // 4. Verify license details
        // Struct: ipAssetId, supply, expiryTime, terms, isExclusive, isRevoked, publicMetadataURI, privateMetadataURI, paymentInterval
        (uint256 linkedIpAssetId,,,,,, string memory publicURI, string memory privateURI,) =
            licenseToken.licenses(licenseId);
        assertEq(linkedIpAssetId, ipTokenId);
        assertEq(publicURI, "ipfs://public-terms");
        assertEq(privateURI, "ipfs://private-terms");
    }
    
    // ============ Marketplace Sale with Royalty Distribution ============
    
    function testMarketplaceSaleWithRoyaltyAndInterest() public {
        // 1. Setup: Create IP and configure revenue split
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        address[] memory recipients = new address[](2);
        recipients[0] = creator;
        recipients[1] = collaborator;
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%
        
        vm.prank(admin);
        revenueDistributor.configureSplit(ipTokenId, recipients, shares);
        
        // 2. Creator lists IP for sale
        vm.prank(creator);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(creator);
        bytes32 listingId = marketplace.createListing(
            address(ipAsset),
            ipTokenId,
            10 ether,
            true
        );
        
        // 3. Buyer purchases
        vm.prank(buyer);
        marketplace.buyListing{value: 10 ether}(listingId);
        
        assertEq(ipAsset.ownerOf(ipTokenId), buyer);
        
        // 4. Check revenue distribution (after platform fee)
        // 10 ether - 2.5% platform fee = 9.75 ether
        // Creator gets 60% = 5.85 ether
        // Collaborator gets 40% = 3.9 ether
        uint256 creatorBalance = revenueDistributor.getBalance(creator);
        uint256 collaboratorBalance = revenueDistributor.getBalance(collaborator);

        assertEq(creatorBalance, 5.85 ether);
        assertEq(collaboratorBalance, 3.9 ether);

        // 5. Withdraw
        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        revenueDistributor.withdraw();

        assertEq(creator.balance, creatorBalanceBefore + creatorBalance);
    }
    
    // ============ Complete Dispute Resolution Flow ============
    
    function testCompleteDisputeResolutionFlow() public {
        // 1. Setup: Create IP and license
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);
        
        // 2. IP owner submits dispute
        vm.prank(creator);
        uint256 disputeId = arbitrator.submitDispute(
            licenseId,
            "Unauthorized commercial use",
            "ipfs://evidence"
        );
        
        // Verify dispute status
        IGovernanceArbitrator.Dispute memory dispute = arbitrator.getDispute(disputeId);
        assertEq(dispute.submitter, creator);
        assertTrue(dispute.status == IGovernanceArbitrator.DisputeStatus.Pending);

        // 3. Arbitrator reviews and approves
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Evidence confirms violation");

        dispute = arbitrator.getDispute(disputeId);
        assertTrue(dispute.status == IGovernanceArbitrator.DisputeStatus.Approved);
        
        // 4. Execute revocation
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
        
        // 5. Verify license is revoked
        assertTrue(licenseToken.isRevoked(licenseId));
        
        // 6. Verify revoked license cannot be transferred
        vm.prank(licensee);
        vm.expectRevert("License revoked");
        licenseToken.safeTransferFrom(licensee, buyer, licenseId, 1, "");
    }
    
    // ============ Automatic Revocation Flow ============
    
    function testAutomaticRevocationAfterMissedPayments() public {
        // 1. Setup: Create IP and license
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");

        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);

        // 2. NOTE: Missed payments are now calculated on-demand by Marketplace
        //    based on: (block.timestamp - lastPaymentTime) / paymentInterval
        //    This test simulates Marketplace calling revokeForMissedPayments()
        //    Marketplace would calculate missed payments and call this function

        // 3. Marketplace calculates 4 missed payments and triggers auto-revoke
        vm.prank(address(marketplace));
        licenseToken.revokeForMissedPayments(licenseId, 4);

        // 4. Verify license is revoked
        assertTrue(licenseToken.isRevoked(licenseId));
        
        // 5. Verify cannot transfer
        vm.prank(licensee);
        vm.expectRevert(ILicenseToken.CannotTransferRevokedLicense.selector);
        licenseToken.safeTransferFrom(licensee, buyer, licenseId, 1, "");
    }
    
    // ============ License Transfer and Metadata Access ============
    
    function testLicenseTransferAndMetadataAccess() public {
        // 1. Setup: Create IP and license
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public-metadata",
            "ipfs://private-metadata",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);
        
        // 2. Licensee can access both metadata
        vm.prank(licensee);
        string memory publicMetadata = licenseToken.getPublicMetadata(licenseId);
        assertEq(publicMetadata, "ipfs://public-metadata");
        
        vm.prank(licensee);
        string memory privateMetadata = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateMetadata, "ipfs://private-metadata");
        
        // 3. Transfer license to buyer
        vm.prank(licensee);
        licenseToken.safeTransferFrom(licensee, buyer, licenseId, 1, "");
        
        // 4. Buyer can now access private metadata
        vm.prank(buyer);
        privateMetadata = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateMetadata, "ipfs://private-metadata");
        
        // 5. Original licensee can no longer access private metadata
        vm.prank(licensee);
        vm.expectRevert("Not authorized to access private metadata");
        licenseToken.getPrivateMetadata(licenseId);
    }
    
    // ============ Marketplace Offer Flow ============
    
    function testCompleteMarketplaceOfferFlow() public {
        // 1. Setup: Create IP
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        // 2. Buyer creates offer
        vm.prank(buyer);
        bytes32 offerId = marketplace.createOffer{value: 5 ether}(
            address(ipAsset),
            ipTokenId,
            block.timestamp + 7 days
        );
        
        // 3. Verify funds are escrowed
        assertEq(marketplace.escrow(offerId), 5 ether);
        
        // 4. Creator accepts offer
        vm.prank(creator);
        ipAsset.approve(address(marketplace), ipTokenId);
        
        vm.prank(creator);
        marketplace.acceptOffer(offerId);
        
        // 5. Verify ownership transferred
        assertEq(ipAsset.ownerOf(ipTokenId), buyer);
    }
    
    // ============ Burn Protection ============
    
    function testCannotBurnIPWithActiveLicenseOrDispute() public {
        // 1. Setup: Create IP and license
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        vm.prank(creator);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "worldwide",
            false, 0);
        
        // 2. Cannot burn with active license
        vm.prank(creator);
        vm.expectRevert("Cannot burn: active licenses exist");
        ipAsset.burn(ipTokenId);
        
        // 3. Submit dispute
        vm.prank(creator);
        uint256 disputeId = arbitrator.submitDispute(licenseId, "Violation", "");
        
        // 4. Revoke license
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(disputeId, true, "Approved");
        
        vm.prank(arbitratorRole);
        arbitrator.executeRevocation(disputeId);
        
        // 5. Still cannot burn (active dispute)
        vm.prank(creator);
        vm.expectRevert("Cannot burn: active dispute");
        ipAsset.burn(ipTokenId);
        
        // 6. Resolve dispute
        // (In real implementation, dispute would be marked as resolved)
        vm.prank(address(arbitrator));
        ipAsset.setDisputeStatus(ipTokenId, false);
        
        // 7. Now can burn
        vm.prank(creator);
        ipAsset.burn(ipTokenId);
        
        vm.expectRevert();
        ipAsset.ownerOf(ipTokenId);
    }
    
    // ============ Upgrade Test ============
    
    function testContractUpgrade() public {
        // 1. Create IP before upgrade
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        // 2. Deploy new implementation
        vm.prank(admin);
        IPAsset newImpl = new IPAsset();
        
        // 3. Upgrade
        vm.prank(admin);
        ipAsset.upgradeToAndCall(address(newImpl), "");
        
        // 4. Verify data preserved
        assertEq(ipAsset.ownerOf(ipTokenId), creator);
        assertEq(ipAsset.tokenURI(ipTokenId), "ipfs://metadata");
    }
    
    // ============ Pause/Unpause Test ============
    
    function testPauseUnpauseWorkflow() public {
        // 1. Normal operation
        vm.prank(creator);
        uint256 ipTokenId = ipAsset.mintIP(creator, "ipfs://metadata");
        
        // 2. Pause
        vm.prank(admin);
        ipAsset.pause();
        
        // 3. Cannot mint when paused
        vm.prank(creator);
        vm.expectRevert();
        ipAsset.mintIP(creator, "ipfs://metadata2");
        
        // 4. Unpause
        vm.prank(admin);
        ipAsset.unpause();
        
        // 5. Can mint again
        vm.prank(creator);
        uint256 ipTokenId2 = ipAsset.mintIP(creator, "ipfs://metadata2");
        
        assertEq(ipAsset.ownerOf(ipTokenId2), creator);
    }
}

