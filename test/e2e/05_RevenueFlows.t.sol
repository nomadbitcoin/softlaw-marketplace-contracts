// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./E2ETestBase.sol";

/**
 * @title RevenueFlows E2E Tests
 * @notice Comprehensive end-to-end tests for revenue distribution and withdrawal
 * @dev Tests cover:
 *      - Primary vs secondary sale detection
 *      - Revenue splits (simple, complex, changes)
 *      - Royalty rates (default, custom, changes)
 *      - Platform fees
 *      - Multi-source revenue accumulation
 *      - Withdrawal flows
 *      - Collaborator revenue sharing
 *      NO ADMIN OPERATIONS - Production-like user flows only
 */
contract RevenueFlowsTest is E2ETestBase {

    // ============ Helper: Create IP with Split ============
    function _createIPWithSplit(
        address owner,
        address[] memory recipients,
        uint256[] memory shares
    ) internal returns (uint256) {
        uint256 tokenId = _mintIP(owner, "ipfs://ip-metadata");
        _configureRevenueSplit(tokenId, owner, recipients, shares);
        return tokenId;
    }

    // ============ Primary Sale Tests ============

    function test_E2E_PrimarySaleSimpleSplit() public {
        // Alice creates IP with 100% revenue to herself
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Alice lists for 10 ETH
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Bob buys (primary sale)
        _buyListing(bob, listingId, 10 ether);

        // Alice should receive proceeds minus platform fee
        uint256 platformFee = _platformFee(10 ether);
        uint256 expectedRevenue = 10 ether - platformFee;

        uint256 aliceBalanceAfter = revenueDistributor.getBalance(alice);
        assertEq(aliceBalanceAfter - aliceBalanceBefore, expectedRevenue);
    }

    function test_E2E_PrimarySaleCollaborativeSplit() public {
        // Alice, Eve, Frank collaborate 50/30/20
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );

        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Alice lists for 10 ETH
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 eveBalanceBefore = revenueDistributor.getBalance(eve);
        uint256 frankBalanceBefore = revenueDistributor.getBalance(frank);

        // Bob buys
        _buyListing(bob, listingId, 10 ether);

        // Calculate expected amounts
        uint256 platformFee = _platformFee(10 ether);
        uint256 netRevenue = 10 ether - platformFee;

        uint256 aliceExpected = (netRevenue * 5000) / BASIS_POINTS;
        uint256 eveExpected = (netRevenue * 3000) / BASIS_POINTS;
        uint256 frankExpected = (netRevenue * 2000) / BASIS_POINTS;

        // Verify splits
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, aliceExpected);
        assertEq(revenueDistributor.getBalance(eve) - eveBalanceBefore, eveExpected);
        assertEq(revenueDistributor.getBalance(frank) - frankBalanceBefore, frankExpected);
    }

    function test_E2E_PlatformFeeAccumulatesToTreasury() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);

        uint256 treasuryBalanceBefore = revenueDistributor.getBalance(treasury);

        // Bob buys
        _buyListing(bob, listingId, 10 ether);

        uint256 expectedPlatformFee = _platformFee(10 ether);
        uint256 treasuryBalanceAfter = revenueDistributor.getBalance(treasury);

        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedPlatformFee);
    }

    // ============ Secondary Sale Tests ============

    function test_E2E_SecondarySaleWithRoyalty() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Alice sets 10% royalty
        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Primary sale: Alice -> Bob for 10 ETH
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 bobBalanceBefore = revenueDistributor.getBalance(bob);

        // Secondary sale: Bob -> Charlie for 20 ETH
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        // Calculate expected amounts
        uint256 platformFee = _platformFee(20 ether);
        uint256 royalty = _royalty(20 ether, 1000); // 10% of 20 ETH = 2 ETH
        uint256 sellerProceeds = 20 ether - platformFee - royalty;

        // Alice gets royalty
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty);

        // Bob gets seller proceeds
        assertEq(revenueDistributor.getBalance(bob) - bobBalanceBefore, sellerProceeds);
    }

    function test_E2E_MultipleSecondarySalesRoyalties() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        _setRoyaltyRate(ipTokenId, alice, 1000); // 10%

        // Primary: Alice -> Bob for 10 ETH
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary 1: Bob -> Charlie for 15 ETH
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 15 ether, true);
        _buyListing(charlie, listing2, 15 ether);

        uint256 royalty1 = _royalty(15 ether, 1000);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty1);

        aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary 2: Charlie -> Dave for 20 ETH
        bytes32 listing3 = _createListing(charlie, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(dave, listing3, 20 ether);

        uint256 royalty2 = _royalty(20 ether, 1000);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty2);

        aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary 3: Dave -> Eve for 25 ETH
        bytes32 listing4 = _createListing(dave, address(ipAsset), ipTokenId, 25 ether, true);
        _buyListing(eve, listing4, 25 ether);

        uint256 royalty3 = _royalty(25 ether, 1000);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty3);
    }

    function test_E2E_RoyaltyWithCollaborators() public {
        // Alice, Eve, Frank collaborate 50/30/20
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );

        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);
        _setRoyaltyRate(ipTokenId, alice, 1500); // 15% royalty

        // Primary: Alice -> Bob for 10 ETH
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 eveBalanceBefore = revenueDistributor.getBalance(eve);
        uint256 frankBalanceBefore = revenueDistributor.getBalance(frank);

        // Secondary: Bob -> Charlie for 20 ETH
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        // Royalty split among collaborators
        uint256 totalRoyalty = _royalty(20 ether, 1500); // 15% of 20 ETH = 3 ETH

        uint256 aliceRoyalty = (totalRoyalty * 5000) / BASIS_POINTS;
        uint256 eveRoyalty = (totalRoyalty * 3000) / BASIS_POINTS;
        uint256 frankRoyalty = (totalRoyalty * 2000) / BASIS_POINTS;

        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, aliceRoyalty);
        assertEq(revenueDistributor.getBalance(eve) - eveBalanceBefore, eveRoyalty);
        assertEq(revenueDistributor.getBalance(frank) - frankBalanceBefore, frankRoyalty);
    }

    // ============ Royalty Rate Configuration Tests ============

    function test_E2E_DifferentRoyaltyRatesAcrossIPs() public {
        // IP1: 5% royalty
        (address[] memory r1, uint256[] memory s1) = _simpleSplit(alice);
        uint256 ip1 = _createIPWithSplit(alice, r1, s1);
        _setRoyaltyRate(ip1, alice, 500);

        // IP2: 10% royalty
        (address[] memory r2, uint256[] memory s2) = _simpleSplit(bob);
        uint256 ip2 = _createIPWithSplit(bob, r2, s2);
        _setRoyaltyRate(ip2, bob, 1000);

        // IP3: 20% royalty
        (address[] memory r3, uint256[] memory s3) = _simpleSplit(charlie);
        uint256 ip3 = _createIPWithSplit(charlie, r3, s3);
        _setRoyaltyRate(ip3, charlie, 2000);

        // Primary sales
        bytes32 listing1 = _createListing(alice, address(ipAsset), ip1, 10 ether, true);
        _buyListing(dave, listing1, 10 ether);

        bytes32 listing2 = _createListing(bob, address(ipAsset), ip2, 10 ether, true);
        _buyListing(eve, listing2, 10 ether);

        bytes32 listing3 = _createListing(charlie, address(ipAsset), ip3, 10 ether, true);
        _buyListing(frank, listing3, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 bobBalanceBefore = revenueDistributor.getBalance(bob);
        uint256 charlieBalanceBefore = revenueDistributor.getBalance(charlie);

        // Secondary sales all at 10 ETH
        bytes32 listing4 = _createListing(dave, address(ipAsset), ip1, 10 ether, true);
        _buyListing(grace, listing4, 10 ether);

        bytes32 listing5 = _createListing(eve, address(ipAsset), ip2, 10 ether, true);
        _buyListing(henry, listing5, 10 ether);

        bytes32 listing6 = _createListing(frank, address(ipAsset), ip3, 10 ether, true);
        _buyListing(ivy, listing6, 10 ether);

        // Verify different royalty amounts
        uint256 aliceRoyalty = revenueDistributor.getBalance(alice) - aliceBalanceBefore;
        uint256 bobRoyalty = revenueDistributor.getBalance(bob) - bobBalanceBefore;
        uint256 charlieRoyalty = revenueDistributor.getBalance(charlie) - charlieBalanceBefore;

        assertEq(aliceRoyalty, _royalty(10 ether, 500)); // 5%
        assertEq(bobRoyalty, _royalty(10 ether, 1000)); // 10%
        assertEq(charlieRoyalty, _royalty(10 ether, 2000)); // 20%
    }

    function test_E2E_RoyaltyRateChangeBetweenSales() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Initial royalty: 10%
        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Primary sale: Alice -> Bob
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary sale 1: Bob -> Charlie (10% royalty)
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        uint256 royalty1 = _royalty(20 ether, 1000);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty1);

        // Charlie (new owner) changes royalty to 5%
        _setRoyaltyRate(ipTokenId, charlie, 500);

        aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary sale 2: Charlie -> Dave (5% royalty now)
        bytes32 listing3 = _createListing(charlie, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(dave, listing3, 20 ether);

        uint256 royalty2 = _royalty(20 ether, 500);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty2);
    }

    function test_E2E_ZeroRoyaltyRate() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Alice sets 0% royalty (no royalties on secondary sales)
        _setRoyaltyRate(ipTokenId, alice, 0);

        // Primary sale
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 bobBalanceBefore = revenueDistributor.getBalance(bob);

        // Secondary sale
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        // Alice gets no royalty (0%)
        assertEq(revenueDistributor.getBalance(alice), aliceBalanceBefore);

        // Bob gets full proceeds minus platform fee
        uint256 platformFee = _platformFee(20 ether);
        uint256 expectedBobRevenue = 20 ether - platformFee;
        assertEq(revenueDistributor.getBalance(bob) - bobBalanceBefore, expectedBobRevenue);
    }

    // ============ Revenue Split Reconfiguration Tests ============

    function test_E2E_SplitReconfigurationBetweenSales() public {
        // Initial split: Alice 100%
        (address[] memory recipients1, uint256[] memory shares1) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients1, shares1);

        _setRoyaltyRate(ipTokenId, alice, 1000);

        // Primary sale
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Secondary sale 1 (Alice gets 100% of royalty)
        bytes32 listing2 = _createListing(bob, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(charlie, listing2, 20 ether);

        uint256 royalty1 = _royalty(20 ether, 1000);
        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, royalty1);

        // Charlie reconfigures split: 60% Alice, 40% Eve
        (address[] memory recipients2, uint256[] memory shares2) = _twoWaySplit(
            alice, 6000,
            eve, 4000
        );
        _configureRevenueSplit(ipTokenId, charlie, recipients2, shares2);

        aliceBalanceBefore = revenueDistributor.getBalance(alice);
        uint256 eveBalanceBefore = revenueDistributor.getBalance(eve);

        // Secondary sale 2 (New split applies)
        bytes32 listing3 = _createListing(charlie, address(ipAsset), ipTokenId, 20 ether, true);
        _buyListing(dave, listing3, 20 ether);

        uint256 totalRoyalty2 = _royalty(20 ether, 1000);
        uint256 aliceRoyalty = (totalRoyalty2 * 6000) / BASIS_POINTS;
        uint256 eveRoyalty = (totalRoyalty2 * 4000) / BASIS_POINTS;

        assertEq(revenueDistributor.getBalance(alice) - aliceBalanceBefore, aliceRoyalty);
        assertEq(revenueDistributor.getBalance(eve) - eveBalanceBefore, eveRoyalty);
    }

    // ============ Withdrawal Tests ============

    function test_E2E_UserWithdrawsAccumulatedRevenue() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Multiple sales to accumulate revenue
        bytes32 listing1 = _createListing(alice, address(ipAsset), ipTokenId, 5 ether, true);
        _buyListing(bob, listing1, 5 ether);

        uint256 ip2 = _mintIP(alice, "ipfs://ip2");
        (address[] memory r2, uint256[] memory s2) = _simpleSplit(alice);
        _configureRevenueSplit(ip2, alice, r2, s2);

        bytes32 listing2 = _createListing(alice, address(ipAsset), ip2, 8 ether, true);
        _buyListing(charlie, listing2, 8 ether);

        // Alice has accumulated revenue
        uint256 accumulatedBalance = revenueDistributor.getBalance(alice);
        assertGt(accumulatedBalance, 0);

        uint256 aliceEthBefore = alice.balance;

        // Alice withdraws
        uint256 withdrawn = _withdraw(alice);

        // Alice received ETH
        assertEq(alice.balance, aliceEthBefore + withdrawn);

        // Balance cleared
        assertEq(revenueDistributor.getBalance(alice), 0);
    }

    function test_E2E_MultipleUsersWithdrawIndependently() public {
        // Collaborative IP: Alice 50%, Eve 30%, Frank 20%
        (address[] memory recipients, uint256[] memory shares) = _threeWaySplit(
            alice, 5000,
            eve, 3000,
            frank, 2000
        );

        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Sale generates revenue
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 10 ether, true);
        _buyListing(bob, listingId, 10 ether);

        // All three have balances
        uint256 aliceBalance = revenueDistributor.getBalance(alice);
        uint256 eveBalance = revenueDistributor.getBalance(eve);
        uint256 frankBalance = revenueDistributor.getBalance(frank);

        assertGt(aliceBalance, 0);
        assertGt(eveBalance, 0);
        assertGt(frankBalance, 0);

        // Eve withdraws first
        uint256 eveWithdrawn = _withdraw(eve);
        assertEq(eveWithdrawn, eveBalance);
        assertEq(revenueDistributor.getBalance(eve), 0);

        // Alice and Frank still have balances
        assertEq(revenueDistributor.getBalance(alice), aliceBalance);
        assertEq(revenueDistributor.getBalance(frank), frankBalance);

        // Alice withdraws
        _withdraw(alice);
        assertEq(revenueDistributor.getBalance(alice), 0);

        // Frank withdraws later
        _withdraw(frank);
        assertEq(revenueDistributor.getBalance(frank), 0);
    }

    function test_E2E_MultiSourceRevenueAccumulation() public {
        // Alice has:
        // 1. Primary sales from her own IPs
        // 2. Royalties from secondary sales
        // 3. Collaborator splits from other IPs

        (address[] memory r1, uint256[] memory s1) = _simpleSplit(alice);
        uint256 aliceIP = _createIPWithSplit(alice, r1, s1);
        _setRoyaltyRate(aliceIP, alice, 1000);

        // Alice's IP primary sale
        bytes32 listing1 = _createListing(alice, address(ipAsset), aliceIP, 10 ether, true);
        _buyListing(bob, listing1, 10 ether);

        uint256 balanceAfterPrimary = revenueDistributor.getBalance(alice);

        // Alice's IP secondary sale (royalty)
        bytes32 listing2 = _createListing(bob, address(ipAsset), aliceIP, 15 ether, true);
        _buyListing(charlie, listing2, 15 ether);

        uint256 balanceAfterRoyalty = revenueDistributor.getBalance(alice);
        assertGt(balanceAfterRoyalty, balanceAfterPrimary);

        // Bob's IP with Alice as collaborator (30% split)
        (address[] memory r2, uint256[] memory s2) = _twoWaySplit(bob, 7000, alice, 3000);
        uint256 bobIP = _createIPWithSplit(bob, r2, s2);

        bytes32 listing3 = _createListing(bob, address(ipAsset), bobIP, 20 ether, true);
        _buyListing(dave, listing3, 20 ether);

        uint256 balanceAfterCollabSale = revenueDistributor.getBalance(alice);
        assertGt(balanceAfterCollabSale, balanceAfterRoyalty);

        // Alice withdraws all accumulated revenue
        uint256 totalWithdrawn = _withdraw(alice);
        assertEq(totalWithdrawn, balanceAfterCollabSale);
    }

    // ============ License Sales Revenue Tests ============

    function test_E2E_LicenseSaleRevenueToIPOwner() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Alice creates license for Bob
        uint256 licenseId = _mintLicense(
            ipTokenId, alice, bob, 1, _now() + 60 days, false, 0, 5 ether,
            "ipfs://license", "ipfs://license-priv"
        );

        uint256 aliceBalanceBefore = revenueDistributor.getBalance(alice);

        // Bob sells license to Charlie on marketplace
        bytes32 listingId = _createListing(bob, address(licenseToken), licenseId, 8 ether, false);
        _buyListing(charlie, listingId, 8 ether);

        // Revenue distributed to IP owner (Alice) and seller (Bob)
        uint256 aliceBalanceAfter = revenueDistributor.getBalance(alice);

        // Alice should receive royalty
        uint256 royalty = _royalty(8 ether, DEFAULT_ROYALTY_BPS);
        assertGt(aliceBalanceAfter - aliceBalanceBefore, 0);
    }

    // ============ Edge Cases ============

    function test_E2E_VerySmallSaleAmountRounding() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Tiny sale: 1 wei
        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 1 wei, true);
        _buyListing(bob, listingId, 1 wei);

        // Should handle rounding correctly (platform fee might round to 0)
        uint256 aliceBalance = revenueDistributor.getBalance(alice);
        assertGt(aliceBalance, 0);
    }

    function test_E2E_LargeSaleAmountNoOverflow() public {
        (address[] memory recipients, uint256[] memory shares) = _simpleSplit(alice);
        uint256 ipTokenId = _createIPWithSplit(alice, recipients, shares);

        // Large sale: 1000 ETH
        vm.deal(bob, 2000 ether);

        bytes32 listingId = _createListing(alice, address(ipAsset), ipTokenId, 1000 ether, true);
        _buyListing(bob, listingId, 1000 ether);

        // Should handle large amounts without overflow
        uint256 aliceBalance = revenueDistributor.getBalance(alice);

        uint256 expectedRevenue = 1000 ether - _platformFee(1000 ether);
        assertEq(aliceBalance, expectedRevenue);
    }

    function test_E2E_WithdrawZeroBalanceFails() public {
        // Alice has no accumulated revenue
        assertEq(revenueDistributor.getBalance(alice), 0);

        // Try to withdraw - should fail
        vm.prank(alice);
        vm.expectRevert();
        revenueDistributor.withdraw();
    }
}
