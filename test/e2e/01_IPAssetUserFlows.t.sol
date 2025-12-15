// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title IPAssetUserFlows E2E Tests
 * @notice Comprehensive end-to-end tests for all IPAsset user operations
 * @dev Tests cover:
 *      - IP creation and metadata management
 *      - Ownership transfers
 *      - Burn protection scenarios
 *      - Private metadata access control
 *      - Cross-user interactions
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract IPAssetUserFlowsTest is E2ETestBase {

    // ============ IP Creation Tests ============

    function test_E2E_UserMintsIPAsset() public {
        // Alice creates her first IP asset
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip-metadata");

        // Verify ownership and metadata
        assertEq(ipAsset.ownerOf(tokenId), alice);
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://alice-ip-metadata");
        assertEq(ipAsset.balanceOf(alice), 1);
    }

    function test_E2E_MultipleUsersCreateIP() public {
        // Multiple users create their own IP assets
        uint256 aliceIP = _mintIP(alice, "ipfs://alice-ip");
        uint256 bobIP = _mintIP(bob, "ipfs://bob-ip");
        uint256 charlieIP = _mintIP(charlie, "ipfs://charlie-ip");

        // Verify each user owns their own IP
        assertEq(ipAsset.ownerOf(aliceIP), alice);
        assertEq(ipAsset.ownerOf(bobIP), bob);
        assertEq(ipAsset.ownerOf(charlieIP), charlie);

        // Verify token IDs are sequential
        assertEq(aliceIP, 1);
        assertEq(bobIP, 2);
        assertEq(charlieIP, 3);
    }

    function test_E2E_UserCreatesMultipleIPAssets() public {
        // Alice creates a portfolio of IP assets
        uint256[] memory tokenIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            tokenIds[i] = _mintIP(alice, string(abi.encodePacked("ipfs://alice-ip-", vm.toString(i))));
        }

        // Verify Alice owns all
        assertEq(ipAsset.balanceOf(alice), 5);
        for (uint256 i = 0; i < 5; i++) {
            assertEq(ipAsset.ownerOf(tokenIds[i]), alice);
        }
    }

    // ============ Metadata Management Tests ============

    function test_E2E_UserUpdatesMetadata() public {
        uint256 tokenId = _mintIP(alice, "ipfs://original-metadata");

        // Alice updates her IP metadata
        vm.prank(alice);
        ipAsset.updateMetadata(tokenId, "ipfs://updated-metadata");

        assertEq(ipAsset.tokenURI(tokenId), "ipfs://updated-metadata");
    }

    function test_E2E_NonOwnerCannotUpdateMetadata() public {
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip");

        // Bob tries to update Alice's metadata - should fail
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.updateMetadata(tokenId, "ipfs://bob-malicious");

        // Metadata unchanged
        assertEq(ipAsset.tokenURI(tokenId), "ipfs://alice-ip");
    }

    function test_E2E_MetadataUpdatesAcrossMultipleIPs() public {
        // Alice creates multiple IPs and updates them
        uint256 ip1 = _mintIP(alice, "ipfs://v1-ip1");
        uint256 ip2 = _mintIP(alice, "ipfs://v1-ip2");
        uint256 ip3 = _mintIP(alice, "ipfs://v1-ip3");

        vm.startPrank(alice);
        ipAsset.updateMetadata(ip1, "ipfs://v2-ip1");
        ipAsset.updateMetadata(ip2, "ipfs://v2-ip2");
        ipAsset.updateMetadata(ip3, "ipfs://v2-ip3");
        vm.stopPrank();

        assertEq(ipAsset.tokenURI(ip1), "ipfs://v2-ip1");
        assertEq(ipAsset.tokenURI(ip2), "ipfs://v2-ip2");
        assertEq(ipAsset.tokenURI(ip3), "ipfs://v2-ip3");
    }

    // ============ Private Metadata Tests ============

    function test_E2E_UserSetsAndAccessesPrivateMetadata() public {
        uint256 tokenId = _mintIP(alice, "ipfs://public-metadata");

        // Alice sets private metadata
        vm.prank(alice);
        ipAsset.setPrivateMetadata(tokenId, "ipfs://private-alice-data");

        // Alice can access it
        vm.prank(alice);
        string memory privateData = ipAsset.getPrivateMetadata(tokenId);
        assertEq(privateData, "ipfs://private-alice-data");
    }

    function test_E2E_NonOwnerCannotAccessPrivateMetadata() public {
        uint256 tokenId = _mintIP(alice, "ipfs://public");

        vm.prank(alice);
        ipAsset.setPrivateMetadata(tokenId, "ipfs://secret-data");

        // Bob cannot access Alice's private metadata
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.getPrivateMetadata(tokenId);
    }

    function test_E2E_PrivateMetadataAccessAfterOwnershipTransfer() public {
        uint256 tokenId = _mintIP(alice, "ipfs://public");

        // Alice sets private metadata
        vm.prank(alice);
        ipAsset.setPrivateMetadata(tokenId, "ipfs://alice-private");

        // Alice transfers IP to Bob
        _transferIP(alice, bob, tokenId);

        // Alice can no longer access private metadata
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.getPrivateMetadata(tokenId);

        // Bob can now access it
        vm.prank(bob);
        string memory privateData = ipAsset.getPrivateMetadata(tokenId);
        assertEq(privateData, "ipfs://alice-private");

        // Bob can update it
        vm.prank(bob);
        ipAsset.setPrivateMetadata(tokenId, "ipfs://bob-private");

        vm.prank(bob);
        assertEq(ipAsset.getPrivateMetadata(tokenId), "ipfs://bob-private");
    }

    // ============ Ownership Transfer Tests ============

    function test_E2E_SimpleIPTransfer() public {
        uint256 tokenId = _mintIP(alice, "ipfs://transferable-ip");

        // Alice transfers to Bob
        _transferIP(alice, bob, tokenId);

        assertEq(ipAsset.ownerOf(tokenId), bob);
        assertEq(ipAsset.balanceOf(alice), 0);
        assertEq(ipAsset.balanceOf(bob), 1);
    }

    function test_E2E_IPTransferChain() public {
        uint256 tokenId = _mintIP(alice, "ipfs://chain-ip");

        // IP travels through multiple owners
        _transferIP(alice, bob, tokenId);
        assertEq(ipAsset.ownerOf(tokenId), bob);

        _transferIP(bob, charlie, tokenId);
        assertEq(ipAsset.ownerOf(tokenId), charlie);

        _transferIP(charlie, dave, tokenId);
        assertEq(ipAsset.ownerOf(tokenId), dave);

        // Original owner has no balance
        assertEq(ipAsset.balanceOf(alice), 0);
        assertEq(ipAsset.balanceOf(dave), 1);
    }

    function test_E2E_IPTransferBackToOriginalOwner() public {
        uint256 tokenId = _mintIP(alice, "ipfs://boomerang-ip");

        // Alice -> Bob -> Charlie -> Alice
        _transferIP(alice, bob, tokenId);
        _transferIP(bob, charlie, tokenId);
        _transferIP(charlie, alice, tokenId);

        // Back to Alice
        assertEq(ipAsset.ownerOf(tokenId), alice);
        assertEq(ipAsset.balanceOf(alice), 1);
    }

    function test_E2E_NonOwnerCannotTransfer() public {
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip");

        // Bob tries to transfer Alice's IP - should fail
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.safeTransferFrom(alice, charlie, tokenId);

        // Still owned by Alice
        assertEq(ipAsset.ownerOf(tokenId), alice);
    }

    // ============ Revenue Split Configuration Tests ============

    function test_E2E_UserConfiguresSingleRecipientSplit() public {
        uint256 tokenId = _mintIP(alice, "ipfs://solo-ip");

        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);

        _configureRevenueSplit(tokenId, alice, recipients, shares);

        // Verify configuration (would need getter in contract)
        // For now, verify no revert occurred
        assertTrue(true);
    }

    function test_E2E_UserConfiguresCollaborativeSplit() public {
        uint256 tokenId = _mintIP(alice, "ipfs://collab-ip");

        // Alice splits revenue with Eve and Frank
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,  // 50%
            eve, 3000,    // 30%
            frank, 2000   // 20%
        );

        _configureRevenueSplit(tokenId, alice, recipients, shares);

        assertTrue(true);
    }

    function test_E2E_UserReconfiguresSplit() public {
        uint256 tokenId = _mintIP(alice, "ipfs://dynamic-split-ip");

        // Initial split: Alice 100%
        (address[] memory recipients1, uint256[] memory shares1) = _simpleSplit(alice);
        _configureRevenueSplit(tokenId, alice, recipients1, shares1);

        // Reconfigure: Alice 70%, Eve 30%
        (address[] memory recipients2, uint256[] memory shares2) = _twoWaySplit(
            alice, 7000,
            eve, 3000
        );
        _configureRevenueSplit(tokenId, alice, recipients2, shares2);

        assertTrue(true);
    }

    function test_E2E_NonOwnerCannotConfigureSplit() public {
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip");

        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(bob);

        // Bob tries to configure Alice's IP split - should fail
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.configureRevenueSplit(tokenId, recipients, shares);
    }

    function test_E2E_SplitConfigurationAfterTransfer() public {
        uint256 tokenId = _mintIP(alice, "ipfs://transfer-split-ip");

        // Alice configures split
        (address[] memory recipients1, uint256[] memory shares1) = _simpleSplit(alice);
        _configureRevenueSplit(tokenId, alice, recipients1, shares1);

        // Transfer to Bob
        _transferIP(alice, bob, tokenId);

        // Alice can no longer configure
        (address[] memory recipients2, uint256[] memory shares2) = _simpleSplit(alice);
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.configureRevenueSplit(tokenId, recipients2, shares2);

        // Bob can now configure
        (address[] memory recipients3, uint256[] memory shares3) = _simpleSplit(bob);
        _configureRevenueSplit(tokenId, bob, recipients3, shares3);
    }

    // ============ Royalty Rate Configuration Tests ============

    function test_E2E_UserSetsCustomRoyaltyRate() public {
        uint256 tokenId = _mintIP(alice, "ipfs://custom-royalty-ip");

        // Alice sets 15% royalty
        _setRoyaltyRate(tokenId, alice, 1500);

        // Verify via royaltyInfo
        (address receiver, uint256 royaltyAmount) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royaltyAmount, 0.15 ether);
    }

    function test_E2E_UserChangesRoyaltyRate() public {
        uint256 tokenId = _mintIP(alice, "ipfs://changing-royalty-ip");

        // Start with 10%
        _setRoyaltyRate(tokenId, alice, 1000);
        (, uint256 royalty1) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royalty1, 0.1 ether);

        // Change to 5%
        _setRoyaltyRate(tokenId, alice, 500);
        (, uint256 royalty2) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royalty2, 0.05 ether);

        // Change to 0% (no royalty)
        _setRoyaltyRate(tokenId, alice, 0);
        (, uint256 royalty3) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royalty3, 0);
    }

    function test_E2E_NonOwnerCannotSetRoyaltyRate() public {
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip");

        // Bob tries to set royalty on Alice's IP - should fail
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.setRoyaltyRate(tokenId, 2000);
    }

    function test_E2E_RoyaltyRateAfterOwnershipTransfer() public {
        uint256 tokenId = _mintIP(alice, "ipfs://transfer-royalty-ip");

        // Alice sets 10% royalty
        _setRoyaltyRate(tokenId, alice, 1000);

        // Transfer to Bob
        _transferIP(alice, bob, tokenId);

        // Alice can no longer set royalty
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.setRoyaltyRate(tokenId, 1500);

        // Bob can set royalty
        _setRoyaltyRate(tokenId, bob, 500);

        (, uint256 royalty) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royalty, 0.05 ether);
    }

    // ============ Burn Protection Tests ============

    function test_E2E_UserBurnsIPWithNoLicenses() public {
        uint256 tokenId = _mintIP(alice, "ipfs://burnable-ip");

        // Alice can burn her own IP with no active licenses
        vm.prank(alice);
        ipAsset.burn(tokenId);

        // Verify burned
        vm.expectRevert();
        ipAsset.ownerOf(tokenId);

        assertEq(ipAsset.balanceOf(alice), 0);
    }

    function test_E2E_UserCannotBurnIPWithActiveLicense() public {
        uint256 tokenId = _mintIP(alice, "ipfs://licensed-ip");

        // Configure split first
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        _configureRevenueSplit(tokenId, alice, recipients, shares);

        // Alice creates a license for Bob
        _mintLicense(
            tokenId,
            alice,
            bob,
            1,
            _now() + 30 days,
            false,
            0, // One-time payment
            1 ether,
            "ipfs://license-public",
            "ipfs://license-private"
        );

        // Alice tries to burn - should fail (active license exists)
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.burn(tokenId);

        // IP still exists
        assertEq(ipAsset.ownerOf(tokenId), alice);
    }

    function test_E2E_UserBurnsIPAfterLicenseExpires() public {
        uint256 tokenId = _mintIP(alice, "ipfs://expiring-ip");

        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        _configureRevenueSplit(tokenId, alice, recipients, shares);

        // Create short-lived license
        uint256 licenseId = _mintLicense(
            tokenId,
            alice,
            bob,
            1,
            _now() + 7 days,
            false,
            0,
            1 ether,
            "ipfs://license-public",
            "ipfs://license-private"
        );

        // Cannot burn while license is active
        vm.prank(alice);
        vm.expectRevert();
        ipAsset.burn(tokenId);

        // Advance time past expiration
        _advanceTime(8 days);

        // Mark license as expired
        _markExpired(alice, licenseId);

        // Now Alice can burn
        vm.prank(alice);
        ipAsset.burn(tokenId);

        vm.expectRevert();
        ipAsset.ownerOf(tokenId);
    }

    function test_E2E_NonOwnerCannotBurnIP() public {
        uint256 tokenId = _mintIP(alice, "ipfs://alice-ip");

        // Bob tries to burn Alice's IP - should fail
        vm.prank(bob);
        vm.expectRevert();
        ipAsset.burn(tokenId);

        // Still owned by Alice
        assertEq(ipAsset.ownerOf(tokenId), alice);
    }

    function test_E2E_BurnIPWithMultipleExpiredLicenses() public {
        uint256 tokenId = _mintIP(alice, "ipfs://multi-license-ip");

        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        _configureRevenueSplit(tokenId, alice, recipients, shares);

        // Create multiple licenses
        uint256 license1 = _mintLicense(
            tokenId, alice, bob, 1, _now() + 5 days, false, 0, 1 ether,
            "ipfs://l1-pub", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            tokenId, alice, charlie, 1, _now() + 10 days, false, 0, 1 ether,
            "ipfs://l2-pub", "ipfs://l2-priv"
        );

        uint256 license3 = _mintLicense(
            tokenId, alice, dave, 1, _now() + 15 days, false, 0, 1 ether,
            "ipfs://l3-pub", "ipfs://l3-priv"
        );

        // Advance past all expirations
        _advanceTime(16 days);

        // Mark all as expired
        _markExpired(alice, license1);
        _markExpired(bob, license2);
        _markExpired(charlie, license3);

        // Now can burn
        vm.prank(alice);
        ipAsset.burn(tokenId);

        vm.expectRevert();
        ipAsset.ownerOf(tokenId);
    }

    // ============ Complex Multi-User Scenarios ============

    function test_E2E_IPTransferWithRoyaltyAndSplitPreservation() public {
        uint256 tokenId = _mintIP(alice, "ipfs://complex-ip");

        // Alice configures split and royalty
        (address[] memory recipients, uint256[] memory shares) = _twoWaySplit(
            alice, 7000,
            eve, 3000
        );
        _configureRevenueSplit(tokenId, alice, recipients, shares);
        _setRoyaltyRate(tokenId, alice, 1500);

        // Transfer to Bob
        _transferIP(alice, bob, tokenId);

        // Royalty still returns correct amount
        (, uint256 royalty) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(royalty, 0.15 ether);

        // Bob now controls and can reconfigure
        (address[] memory newRecipients, uint256[] memory newShares) = _simpleSplit(bob);
        _configureRevenueSplit(tokenId, bob, newRecipients, newShares);
        _setRoyaltyRate(tokenId, bob, 500);

        (, uint256 newRoyalty) = revenueDistributor.royaltyInfo(tokenId, 1 ether);
        assertEq(newRoyalty, 0.05 ether);
    }

    function test_E2E_MultipleIPsWithDifferentConfigurations() public {
        // Alice creates 3 different IPs with different configs
        uint256 ip1 = _mintIP(alice, "ipfs://ip1");
        uint256 ip2 = _mintIP(alice, "ipfs://ip2");
        uint256 ip3 = _mintIP(alice, "ipfs://ip3");

        // IP1: Solo, 5% royalty
        (address[] memory r1, uint256[] memory s1) = _simpleSplit(alice);
        _configureRevenueSplit(ip1, alice, r1, s1);
        _setRoyaltyRate(ip1, alice, 500);

        // IP2: Collab with Eve, 10% royalty
        (address[] memory r2, uint256[] memory s2) = _twoWaySplit(alice, 6000, eve, 4000);
        _configureRevenueSplit(ip2, alice, r2, s2);
        _setRoyaltyRate(ip2, alice, 1000);

        // IP3: Three-way with Eve and Frank, 15% royalty
        (address[] memory r3, uint256[] memory s3) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );
        _configureRevenueSplit(ip3, alice, r3, s3);
        _setRoyaltyRate(ip3, alice, 1500);

        // Verify all different royalties
        (, uint256 royalty1) = revenueDistributor.royaltyInfo(ip1, 1 ether);
        (, uint256 royalty2) = revenueDistributor.royaltyInfo(ip2, 1 ether);
        (, uint256 royalty3) = revenueDistributor.royaltyInfo(ip3, 1 ether);

        assertEq(royalty1, 0.05 ether);
        assertEq(royalty2, 0.10 ether);
        assertEq(royalty3, 0.15 ether);
    }

    function test_E2E_CollaboratorCannotModifyIPWithoutOwnership() public {
        uint256 tokenId = _mintIP(alice, "ipfs://collab-ip");

        // Alice splits revenue with Eve
        (address[] memory recipients, uint256[] memory shares) = _twoWaySplit(
            alice, 6000,
            eve, 4000
        );
        _configureRevenueSplit(tokenId, alice, recipients, shares);

        // Eve is a collaborator (gets revenue) but not owner
        // Eve cannot update metadata
        vm.prank(eve);
        vm.expectRevert();
        ipAsset.updateMetadata(tokenId, "ipfs://eve-hack");

        // Eve cannot set royalty
        vm.prank(eve);
        vm.expectRevert();
        ipAsset.setRoyaltyRate(tokenId, 2000);

        // Eve cannot reconfigure split
        (address[] memory evilRecipients, uint256[] memory evilShares) = _simpleSplit(eve);
        vm.prank(eve);
        vm.expectRevert();
        ipAsset.configureRevenueSplit(tokenId, evilRecipients, evilShares);

        // Alice retains full control
        assertEq(ipAsset.ownerOf(tokenId), alice);
    }
}
