// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title MultiUserScenarios E2E Tests
 * @notice Complex scenarios involving multiple users and concurrent operations
 * @dev Tests cover:
 *      - Collaborator workflows and revenue sharing
 *      - IP ownership chains
 *      - License fragmentation and consolidation
 *      - Concurrent marketplace activities
 *      - Multi-party revenue distribution
 *      - Complex user interaction patterns
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract MultiUserScenariosTest is E2ETestBase {

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

    // ============ Collaborator Workflows Tests ============

    function test_E2E_ThreeCreatorsCollaborateOnIP() public {
        // Alice, Eve, Frank collaborate 50/30/20
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );

        uint256 ipTokenId = _mintIP(alice, "ipfs://collaborative-ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);
        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Primary sale
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 100 ether, true);
        _buyListing(bob, listing1, 100 ether);

        uint256 platformFee = _platformFee(100 ether);
        uint256 netRevenue = 100 ether - platformFee;

        // Verify each collaborator got their share
        uint256 aliceRevenue = revenueDistributor.getBalance(alice);
        uint256 eveRevenue = revenueDistributor.getBalance(eve);
        uint256 frankRevenue = revenueDistributor.getBalance(frank);

        assertEq(aliceRevenue, (netRevenue * 5000) / BASIS_POINTS);
        assertEq(eveRevenue, (netRevenue * 3000) / BASIS_POINTS);
        assertEq(frankRevenue, (netRevenue * 2000) / BASIS_POINTS);

        // Each can withdraw independently
        _withdraw(alice);
        _withdraw(eve);
        _withdraw(frank);

        // All balances cleared
        assertEq(revenueDistributor.getBalance(alice), 0);
        assertEq(revenueDistributor.getBalance(eve), 0);
        assertEq(revenueDistributor.getBalance(frank), 0);
    }

    function test_E2E_CollaboratorSplitChangesAfterPrimarySale() public {
        // Initial: Alice 100%
        (address[] memory r1, uint256[] memory s1) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://evolving-ip");
        _configureRevenueSplit(ipTokenId, alice, r1, s1);
        _setRoyaltyRate(ipTokenId, alice, 1500);

        // Primary sale
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        // Bob adds collaborators for royalties
        (address[] memory r2, uint256[] memory s2) = _threeWaySplit(
            bob, 4000,
            charlie, 4000,
            dave, 2000
        );
        _configureRevenueSplit(ipTokenId, bob, r2, s2);

        // Secondary sale - new split applies to royalties
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(eve, listing2, 20 ether);

        uint256 totalRoyalty = _royalty(20 ether, 1500);

        // Verify royalty split among Bob, Charlie, Dave
        uint256 bobRoyalty = (totalRoyalty * 4000) / BASIS_POINTS;
        uint256 charlieRoyalty = (totalRoyalty * 4000) / BASIS_POINTS;
        uint256 daveRoyalty = (totalRoyalty * 2000) / BASIS_POINTS;

        assertApproxEqAbs(revenueDistributor.getBalance(bob), bobRoyalty + (20 ether - _platformFee(20 ether) - totalRoyalty), 10);
        assertApproxEqAbs(revenueDistributor.getBalance(charlie), charlieRoyalty, 10);
        assertApproxEqAbs(revenueDistributor.getBalance(dave), daveRoyalty, 10);
    }

    function test_E2E_MultipleCollaboratorIPsWithSharedMembers() public {
        // IP1: Alice 60%, Eve 40%
        (address[] memory r1, uint256[] memory s1) = _twoWaySplit(alice, 6000, eve, 4000);
        uint256 ip1 = _mintIP(alice, "ipfs://ip1");
        _configureRevenueSplit(ip1, alice, r1, s1);

        // IP2: Eve 50%, Frank 50%
        (address[] memory r2, uint256[] memory s2) = _twoWaySplit(eve, 5000, frank, 5000);
        uint256 ip2 = _mintIP(eve, "ipfs://ip2");
        _configureRevenueSplit(ip2, eve, r2, s2);

        // IP3: Alice 33%, Eve 33%, Frank 34%
        (address[] memory r3, uint256[] memory s3) = _threeWaySplit(
            alice, 3333,
            eve, 3333,
            frank, 3334
        );
        uint256 ip3 = _mintIP(alice, "ipfs://ip3");
        _configureRevenueSplit(ip3, alice, r3, s3);

        // Sell all three
        bytes32 l1 = _createListing(alice, address(ipAsset), ip1, 10 ether, true);
        _buyListing(bob, l1, 10 ether);

        bytes32 l2 = _createListing(eve, address(ipAsset), ip2, 15 ether, true);
        _buyListing(charlie, l2, 15 ether);

        bytes32 l3 = _createListing(alice, address(ipAsset), ip3, 20 ether, true);
        _buyListing(dave, l3, 20 ether);

        // Eve should have revenue from all three IPs
        uint256 eveTotal = revenueDistributor.getBalance(eve);
        assertGt(eveTotal, 10 ether); // From multiple sources

        // Alice from IP1 and IP3
        uint256 aliceTotal = revenueDistributor.getBalance(alice);
        assertGt(aliceTotal, 8 ether);

        // Frank from IP2 and IP3
        uint256 frankTotal = revenueDistributor.getBalance(frank);
        assertGt(frankTotal, 7 ether);
    }

    // ============ IP Ownership Chain Tests ============

    function test_E2E_IPThroughFiveOwners() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://traveling-ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);
        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Alice -> Bob
        bytes32 l1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, l1, 10 ether);
        assertEq(ipAsset.ownerOf(ipTokenId), bob);

        // Bob -> Charlie
        bytes32 l2 = _createListing(bob, address(ipAsset), ipTokenId, 12 ether, true);
        _buyListing(charlie, l2, 12 ether);
        assertEq(ipAsset.ownerOf(ipTokenId), charlie);

        // Charlie -> Dave
        bytes32 l3 = _createListing(charlie, address(ipAsset), ipTokenId, 15 ether, true);
        _buyListing(dave, l3, 15 ether);
        assertEq(ipAsset.ownerOf(ipTokenId), dave);

        // Dave -> Eve
        bytes32 l4 = _createListing(dave, address(ipAsset), ipTokenId, 18 ether, true);
        _buyListing(eve, l4, 18 ether);
        assertEq(ipAsset.ownerOf(ipTokenId), eve);

        // Eve -> Frank
        bytes32 l5 = _createListing(eve, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(frank, l5, 20 ether);
        assertEq(ipAsset.ownerOf(ipTokenId), frank);

        // Alice accumulated primary sale proceeds + royalties from all secondary sales
        uint256 aliceBalance = revenueDistributor.getBalance(alice);
        uint256 primaryProceeds = 10 ether - _platformFee(10 ether);
        uint256 secondaryRoyalties = _royalty(12 ether, 1000) + _royalty(15 ether, 1000) +
                                      _royalty(18 ether, 1000) + _royalty(20 ether, 1000);
        assertEq(aliceBalance, primaryProceeds + secondaryRoyalties);
    }

    function test_E2E_IPBoomerangBackToOriginalOwner() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://boomerang-ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);
        _setRoyaltyRate(ipTokenId, alice, 500);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Alice -> Bob -> Charlie -> Alice
        bytes32 l1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, l1, 10 ether);

        bytes32 l2 = _createListing(bob, address(ipAsset), ipTokenId, 12 ether, true);
        _buyListing(charlie, l2, 12 ether);

        bytes32 l3 = _createListing(charlie, address(ipAsset), ipTokenId, 15 ether, true);
        _buyListing(alice, l3, 15 ether);

        // Alice owns it again
        assertEq(ipAsset.ownerOf(ipTokenId), alice);

        // Alice got:
        // - Primary sale proceeds
        // - Royalties from Bob->Charlie and Charlie->Alice sales
        // - Paid for final purchase
        uint256 aliceBalanceAfter = revenueDistributor.getBalance(alice);

        uint256 primaryRevenue = 10 ether - _platformFee(10 ether);
        uint256 royalty1 = _royalty(12 ether, 500);
        uint256 royalty2 = _royalty(15 ether, 500);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, primaryRevenue + royalty1 + royalty2);
    }

    // ============ License Fragmentation Tests ============

    function test_E2E_LicenseDistributedAcrossTenUsers() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        // Create license with supply of 100
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 100, _now() + 90 days, false, 0, 50 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Bob distributes to 10 users (10 each)
        address[9] memory users = [charlie, dave, eve, frank, grace, henry, ivy, jack, alice];

        for (uint256 i = 0; i < 9; i++) {
            _transferLicense(bob, users[i], licenseId, 10);
        }

        // Bob retains 10
        assertEq(licenseToken.balanceOf(bob, licenseId), 10);

        // Verify each got 10
        for (uint256 i = 0; i < 9; i++) {
            assertEq(licenseToken.balanceOf(users[i], licenseId), 10);
        }

        // All can access private metadata
        for (uint256 i = 0; i < 9; i++) {
            vm.prank(users[i]);
            licenseToken.getPrivateMetadata(licenseId);
        }
    }

    function test_E2E_LicenseConsolidationAfterFragmentation() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 100, _now() + 90 days, false, 0, 20 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        // Fragment: Bob -> Charlie, Dave, Eve (25 each, Bob keeps 25)
        _transferLicense(bob, charlie, licenseId, 25);
        _transferLicense(bob, dave, licenseId, 25);
        _transferLicense(bob, eve, licenseId, 25);

        assertEq(licenseToken.balanceOf(bob, licenseId), 25);

        // Consolidate to Frank
        _transferLicense(bob, frank, licenseId, 25);
        _transferLicense(charlie, frank, licenseId, 25);
        _transferLicense(dave, frank, licenseId, 25);
        _transferLicense(eve, frank, licenseId, 25);

        // Frank has all 100
        assertEq(licenseToken.balanceOf(frank, licenseId), 100);

        // Others have 0
        assertEq(licenseToken.balanceOf(bob, licenseId), 0);
        assertEq(licenseToken.balanceOf(charlie, licenseId), 0);
        assertEq(licenseToken.balanceOf(dave, licenseId), 0);
        assertEq(licenseToken.balanceOf(eve, licenseId), 0);
    }

    // ============ Concurrent Marketplace Activity Tests ============

    function test_E2E_FiveSimultaneousIPSales() public {
        // Five users each create and sell an IP simultaneously
        address[5] memory sellers = [alice, bob, charlie, dave, eve];
        address[5] memory buyers = [frank, grace, henry, ivy, jack];
        uint256[5] memory tokenIds;
        bytes32[5] memory listingIds;

        // Create IPs
        for (uint256 i = 0; i < 5; i++) {
            (address[] memory r, uint256[] memory s) = _simpleSplit(sellers[i]);
            tokenIds[i] = _mintIP(sellers[i], string(abi.encodePacked("ipfs://ip", vm.toString(i))));
            _configureRevenueSplit(tokenIds[i], sellers[i], r, s);

            listingIds[i] = _createListing(sellers[i], address(ipAsset), tokenIds[i], (i + 1) * 5 ether, true);
        }

        // All buyers purchase simultaneously
        for (uint256 i = 0; i < 5; i++) {
            _buyListing(buyers[i], listingIds[i], (i + 1) * 5 ether);
        }

        // Verify all ownership transfers
        for (uint256 i = 0; i < 5; i++) {
            assertEq(ipAsset.ownerOf(tokenIds[i]), buyers[i]);
        }
    }

    function test_E2E_MultipleUsersCompeteForSameLicense() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 10 ether,
            "ipfs://exclusive-license", "ipfs://exclusive-license-priv"
        );

        // Bob lists for 15 ETH
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 15 ether, false);

        // Multiple users make offers
        bytes32 offer1 = _createOffer(charlie, address(licenseToken), licenseId, 16 ether, _now() + 7 days);
        bytes32 offer2 = _createOffer(dave, address(licenseToken), licenseId, 18 ether, _now() + 7 days);
        bytes32 offer3 = _createOffer(eve, address(licenseToken), licenseId, 20 ether, _now() + 7 days);

        // Eve wins (highest offer)
        _acceptOffer(bob, offer3, address(licenseToken), false, licenseId);

        assertEq(licenseToken.balanceOf(eve, licenseId), 1);

        // Others can cancel their offers
        vm.prank(charlie);
        marketplace.cancelOffer(offer1);

        vm.prank(dave);
        marketplace.cancelOffer(offer2);
    }

    // ============ Complex Revenue Scenarios Tests ============

    function test_E2E_UserAccumulatesRevenueFromMultipleSources() public {
        // Alice participates in multiple IPs in different roles:
        // 1. Creator of IP1 (100%)
        // 2. Collaborator on IP2 (30%)
        // 3. Buyer of IP3 who later sells it

        // IP1: Alice 100%
        (address[] memory r1, uint256[] memory s1) = _simpleSplit(alice);
        uint256 ip1 = _mintIP(alice, "ipfs://ip1");
        _configureRevenueSplit(ip1, alice, r1, s1);
        _setRoyaltyRate(ip1, alice, 1000);

        // IP2: Bob 70%, Alice 30%
        (address[] memory r2, uint256[] memory s2) = _twoWaySplit(bob, 7000, alice, 3000);
        uint256 ip2 = _mintIP(bob, "ipfs://ip2");
        _configureRevenueSplit(ip2, bob, r2, s2);
        _setRoyaltyRate(ip2, bob, 500);

        // IP3: Charlie 100%
        (address[] memory r3, uint256[] memory s3) = _simpleSplit(charlie);
        uint256 ip3 = _mintIP(charlie, "ipfs://ip3");
        _configureRevenueSplit(ip3, charlie, r3, s3);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // 1. Alice sells IP1 (gets proceeds)
        bytes32 l1 = _createListing(alice, address(ipAsset), ip1, 20 ether, true);
        _buyListing(dave, l1, 20 ether);

        // 2. Bob sells IP2 (Alice gets 30% of proceeds as collaborator)
        bytes32 l2 = _createListing(bob, address(ipAsset), ip2, 30 ether, true);
        _buyListing(eve, l2, 30 ether);

        // 3. Alice buys IP3
        bytes32 l3 = _createListing(charlie, address(ipAsset), ip3, 10 ether, true);
        _buyListing(alice, l3, 10 ether);

        // 4. Alice sells IP3 (gets proceeds)
        bytes32 l4 = _createListing(alice, address(ipAsset), ip3, 15 ether, true);
        _buyListing(frank, l4, 15 ether);

        // 5. Dave resells IP1 (Alice gets royalty)
        bytes32 l5 = _createListing(dave, address(ipAsset), ip1, 25 ether, true);
        _buyListing(grace, l5, 25 ether);

        uint256 aliceBalanceAfter = revenueDistributor.getBalance(alice);
        uint256 totalRevenue = aliceBalanceAfter - aliceBalanceBefore;

        // Alice should have accumulated significant revenue from multiple sources
        assertGt(totalRevenue, 30 ether);
    }

    // ============ Multi-Party License Scenarios Tests ============

    function test_E2E_TenUsersWithRecurringLicensesAllPayOnTime() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        address[10] memory licensees = [bob, charlie, dave, eve, frank, grace, henry, ivy, jack, alice];
        uint256[10] memory licenseIds;

        // Create 10 recurring licenses through marketplace
        for (uint256 i = 0; i < 10; i++) {
            licenseIds[i] = _createRecurringLicense(alice, licensees[i], ipTokenId, 30 days, 1 ether);
        }

        // All pay first payment on time
        _advanceTime(30 days);

        for (uint256 i = 0; i < 10; i++) {
            _makeRecurringPayment(licensees[i], licenseIds[i]);
            assertEq(marketplace.getMissedPayments(address(licenseToken), licenseIds[i]), 0);
        }

        // Alice received 10 ETH in revenue (minus platform fees)
        assertGt(revenueDistributor.getBalance(alice), 9 ether);
    }

    function test_E2E_ComplexMultiUserDisputeScenario() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _mintIP(alice, "ipfs://ip");
        _configureRevenueSplit(ipTokenId, alice, recipients, shares);

        // Alice creates 3 licenses for different users
        uint256 license1 = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://l1", "ipfs://l1-priv"
        );

        uint256 license2 = _mintLicense(
            ipTokenId, alice, charlie, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://l2", "ipfs://l2-priv"
        );

        uint256 license3 = _mintLicense(
            ipTokenId, alice, dave, 1, _now() + 90 days, false, 0, 5 ether,
            "ipfs://l3", "ipfs://l3-priv"
        );

        // Bob and Charlie submit disputes
        uint256 dispute1 = _submitDispute(bob, license1, "Violation", "ipfs://proof1");
        uint256 dispute2 = _submitDispute(charlie, license2, "Violation", "ipfs://proof2");

        // Arbitrator approves Bob's dispute (revokes license1)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute1, true, "Approved");

        assertTrue(licenseToken.isRevoked(license1));

        // Arbitrator rejects Charlie's dispute (license2 stays active)
        vm.prank(arbitratorRole);
        arbitrator.resolveDispute(dispute2, false, "Rejected");

        assertFalse(licenseToken.isRevoked(license2));

        // Dave's license unaffected
        assertTrue(licenseToken.isActiveLicense(license3));

        // Bob can't use revoked license
        vm.prank(bob);
        vm.expectRevert();
        licenseToken.safeTransferFrom(bob, eve, license1, 1, "");

        // Charlie and Dave can still use theirs
        _transferLicense(charlie, eve, license2, 1);
        _transferLicense(dave, frank, license3, 1);
    }
}
