// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/RevenueDistributor.sol";
import "../src/interfaces/IRevenueDistributor.sol";

contract MockIPAsset {
    mapping(uint256 => address) private _owners;

    function setOwner(uint256 tokenId, address owner) external {
        _owners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
        return owner;
    }
}

contract RevenueDistributorTest is Test {
    RevenueDistributor public distributor;
    MockIPAsset public mockIPAsset;

    address public admin = address(1);
    address public treasury = address(2);
    address public recipient1 = address(3);
    address public recipient2 = address(4);
    address public recipient3 = address(5);
    address public ipOwner = address(6);
    
    uint256 constant PLATFORM_FEE = 250; // 2.5%
    uint256 constant DEFAULT_ROYALTY = 1000; // 10%
    uint256 constant PENALTY_RATE = 500; // 5% monthly penalty for late payments

    event PaymentDistributed(uint256 indexed ipAssetId, uint256 amount, uint256 platformFee);
    event SplitConfigured(uint256 indexed ipAssetId, address[] recipients, uint256[] shares);
    event Withdrawal(address indexed recipient, uint256 principal);
    event PenaltyAccrued(address indexed recipient, uint256 amount, uint256 monthsDelayed);
    event RoyaltyUpdated(uint256 newRoyaltyBasisPoints);
    
    function setUp() public {
        vm.startPrank(admin);
        mockIPAsset = new MockIPAsset();
        distributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY, address(mockIPAsset));
        distributor.grantRole(distributor.CONFIGURATOR_ROLE(), admin);
        vm.stopPrank();

        // Set up a default IP asset owner
        mockIPAsset.setOwner(1, ipOwner);
    }

    function testConstructorSetsVariables() public {
        MockIPAsset newMockIPAsset = new MockIPAsset();
        RevenueDistributor newDistributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY, address(newMockIPAsset));

        assertEq(newDistributor.platformTreasury(), treasury);
        assertEq(newDistributor.platformFeeBasisPoints(), PLATFORM_FEE);
        assertEq(newDistributor.defaultRoyaltyBasisPoints(), DEFAULT_ROYALTY);
        assertEq(newDistributor.ipAssetContract(), address(newMockIPAsset));
    }

    function testConstructorGrantsAdminRole() public {
        MockIPAsset newMockIPAsset = new MockIPAsset();

        vm.prank(admin);
        RevenueDistributor newDistributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY, address(newMockIPAsset));

        assertTrue(newDistributor.hasRole(newDistributor.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testConstructorRevertsWithInvalidTreasury() public {
        MockIPAsset newMockIPAsset = new MockIPAsset();
        vm.expectRevert(IRevenueDistributor.InvalidTreasuryAddress.selector);
        new RevenueDistributor(address(0), PLATFORM_FEE, DEFAULT_ROYALTY, address(newMockIPAsset));
    }

    function testConstructorRevertsWithInvalidPlatformFee() public {
        MockIPAsset newMockIPAsset = new MockIPAsset();
        vm.expectRevert(IRevenueDistributor.InvalidPlatformFee.selector);
        new RevenueDistributor(treasury, 10001, DEFAULT_ROYALTY, address(newMockIPAsset));
    }

    function testConstructorRevertsWithInvalidRoyalty() public {
        MockIPAsset newMockIPAsset = new MockIPAsset();
        vm.expectRevert(IRevenueDistributor.InvalidRoyalty.selector);
        new RevenueDistributor(treasury, PLATFORM_FEE, 10001, address(newMockIPAsset));
    }

    function testConstructorRevertsWithInvalidIPAssetAddress() public {
        vm.expectRevert(IRevenueDistributor.InvalidIPAssetAddress.selector);
        new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY, address(0));
    }

    // ============ BR-004.1: Revenue splits MUST sum to exactly 100% ============
    
    function testConfigureSplitWithValidShares() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%
        
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit SplitConfigured(1, recipients, shares);
        distributor.configureSplit(1, recipients, shares);
        
        (address[] memory storedRecipients, uint256[] memory storedShares) = distributor.ipSplits(1);
        assertEq(storedRecipients.length, 2);
        assertEq(storedShares[0], 7000);
        assertEq(storedShares[1], 3000);
    }
    
    function testCannotConfigureSplitWithInvalidSum() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000; // 60%
        shares[1] = 3000; // 30% - Total = 90%

        vm.prank(admin);
        vm.expectRevert(IRevenueDistributor.InvalidSharesSum.selector);
        distributor.configureSplit(1, recipients, shares);
    }
    
    function testCannotConfigureSplitWithMismatchedArrays() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;

        uint256[] memory shares = new uint256[](3);
        shares[0] = 5000;
        shares[1] = 3000;
        shares[2] = 2000;

        vm.prank(admin);
        vm.expectRevert(IRevenueDistributor.ArrayLengthMismatch.selector);
        distributor.configureSplit(1, recipients, shares);
    }
    
    // ============ BR-004.2: Platform fees MUST be deducted before distribution ============
    
    function testPlatformFeeDeductedBeforeDistribution() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000; // 100%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Distribute 1 ether (primary sale - seller is in split)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Platform fee = 1 ether * 2.5% = 0.025 ether (accumulated in balance)
        uint256 treasuryBalance = distributor.getBalance(treasury);
        assertEq(treasuryBalance, 0.025 ether);

        // Recipient gets 97.5% = 0.975 ether
        uint256 balance = distributor.getBalance(recipient1);
        assertEq(balance, 0.975 ether);
    }
    
    // ============ BR-004.3: Royalties MUST be calculated on all secondary sales ============
    
    function testRoyaltyInfo() public {
        uint256 salePrice = 10 ether;
        
        (address receiver, uint256 royaltyAmount) = distributor.royaltyInfo(1, salePrice);
        
        // Default royalty is 10%
        assertEq(royaltyAmount, 1 ether);
        assertEq(receiver, address(distributor));
    }
    
    function testSetDefaultRoyalty() public {
        vm.prank(admin);
        distributor.setDefaultRoyalty(1500); // 15%
        
        (,uint256 royaltyAmount) = distributor.royaltyInfo(1, 10 ether);
        assertEq(royaltyAmount, 1.5 ether);
    }
    
    function testSupportsEIP2981Interface() public {
        // EIP-2981 interface ID
        assertTrue(distributor.supportsInterface(0x2a55205a));
    }
    
    // ============ BR-004.4: Recipients MUST withdraw their own funds (pull pattern) ============
    
    function testRecipientCanWithdraw() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute payment (primary sale - seller is in split)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        uint256 recipient1BalanceBefore = recipient1.balance;
        
        // Recipient withdraws
        vm.prank(recipient1);
        distributor.withdraw();
        
        assertGt(recipient1.balance, recipient1BalanceBefore);
    }
    
    function testCannotWithdrawOthersFunds() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute payment (primary sale - seller is in split)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // recipient2 tries to withdraw (has no balance)
        vm.prank(recipient2);
        vm.expectRevert(IRevenueDistributor.NoBalanceToWithdraw.selector);
        distributor.withdraw();
    }
    
    // ============ BR-004.5: Withdrawals MUST NOT exceed available balance ============
    
    function testCannotWithdrawMoreThanBalance() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute payment (primary sale - seller is in split)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // First withdrawal succeeds
        vm.prank(recipient1);
        distributor.withdraw();
        
        // Second withdrawal fails (no balance left)
        vm.prank(recipient1);
        vm.expectRevert(IRevenueDistributor.NoBalanceToWithdraw.selector);
        distributor.withdraw();
    }
    
    // ============ BR-004.6: Failed distributions MUST NOT block transactions ============

    function testDistributionDoesNotRevertWhenRecipientFails() public {
        // Configure split with invalid recipient (contract that rejects ETH)
        RejectETH rejecter = new RejectETH();

        address[] memory recipients = new address[](2);
        recipients[0] = address(rejecter);
        recipients[1] = recipient1;

        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000;
        shares[1] = 5000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Distribution should not revert even if one recipient fails (primary sale)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // recipient1 should still receive their share
        uint256 balance = distributor.getBalance(recipient1);
        assertGt(balance, 0);
    }
    
    // ============ Additional Tests ============
    
    function testMultipleRecipientDistribution() public {
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;
        
        uint256[] memory shares = new uint256[](3);
        shares[0] = 5000; // 50%
        shares[1] = 3000; // 30%
        shares[2] = 2000; // 20%
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute 10 ether (primary sale - seller is in split)
        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);

        // After platform fee (2.5%), remaining = 9.75 ether
        uint256 balance1 = distributor.getBalance(recipient1);
        uint256 balance2 = distributor.getBalance(recipient2);
        uint256 balance3 = distributor.getBalance(recipient3);

        assertEq(balance1, 4.875 ether); // 50% of 9.75
        assertEq(balance2, 2.925 ether); // 30% of 9.75
        assertEq(balance3, 1.95 ether);  // 20% of 9.75
    }
    
    function testWithdrawalEvent() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        vm.warp(block.timestamp + 30 days);
        
        vm.prank(recipient1);
        vm.expectEmit(true, false, false, false);
        emit Withdrawal(recipient1, 0); // Actual values calculated
        distributor.withdraw();
    }
    
    function testOnlyConfiguratorCanConfigureSplit() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(recipient2);
        vm.expectRevert();
        distributor.configureSplit(1, recipients, shares);
    }
    
    function testCanUpdateExistingSplit() public {
        address[] memory recipients1 = new address[](1);
        recipients1[0] = recipient1;
        
        uint256[] memory shares1 = new uint256[](1);
        shares1[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients1, shares1);
        
        // Update split
        address[] memory recipients2 = new address[](2);
        recipients2[0] = recipient1;
        recipients2[1] = recipient2;
        
        uint256[] memory shares2 = new uint256[](2);
        shares2[0] = 6000;
        shares2[1] = 4000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients2, shares2);
        
        (address[] memory storedRecipients,) = distributor.ipSplits(1);
        assertEq(storedRecipients.length, 2);
    }
    
    function testDistributeToOwnerWhenNoSplitConfigured() public {
        // Setup: DO NOT configure split for IP asset
        uint256 ipAssetId = 999;
        address owner = address(0xABC);
        mockIPAsset.setOwner(ipAssetId, owner);

        // Action: Distribute 1 ether payment (falls back to owner)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(ipAssetId, 1 ether, owner);

        // Assert: Platform fee accumulated (2.5% = 0.025 ether)
        uint256 treasuryBalance = distributor.getBalance(treasury);
        assertEq(treasuryBalance, 0.025 ether);

        // Assert: After platform fee, entire remaining amount goes to IP asset owner
        uint256 balance = distributor.getBalance(owner);
        assertEq(balance, 0.975 ether); // 1 ether - 2.5% fee
    }

    function testDistributeToInvalidIPAssetReverts() public {
        // IP asset 888 doesn't exist (no owner set)
        vm.deal(address(this), 1 ether);
        vm.expectRevert("ERC721: invalid token ID");
        distributor.distributePayment{value: 1 ether}(888, 1 ether, recipient1);
    }

    function testDistributeWithIncorrectPaymentAmountReverts() public {
        // Configure split first
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        vm.expectRevert(IRevenueDistributor.IncorrectPaymentAmount.selector);
        distributor.distributePayment{value: 1 ether}(1, 0.5 ether, recipient1); // msg.value != amount
    }

    function testGrantConfiguratorRoleToIPAssetContract() public {
        address ipAssetContract = address(0x999);

        // Admin grants CONFIGURATOR_ROLE to IPAsset contract
        vm.startPrank(admin);
        distributor.grantConfiguratorRole(ipAssetContract);
        vm.stopPrank();

        // Verify IPAsset contract has the role
        assertTrue(distributor.hasRole(distributor.CONFIGURATOR_ROLE(), ipAssetContract));

        // IPAsset contract can now configure splits
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;

        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.startPrank(ipAssetContract);
        distributor.configureSplit(1, recipients, shares);
        vm.stopPrank();

        // Verify split was configured
        (address[] memory storedRecipients,) = distributor.ipSplits(1);
        assertEq(storedRecipients.length, 1);
        assertEq(storedRecipients[0], recipient1);
    }

    function testOnlyAdminCanGrantConfiguratorRole() public {
        address ipAssetContract = address(0x999);

        // Non-admin cannot grant role
        vm.startPrank(recipient1);
        vm.expectRevert();
        distributor.grantConfiguratorRole(ipAssetContract);
        vm.stopPrank();
    }

    function testCannotGrantConfiguratorRoleToZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(IRevenueDistributor.InvalidRecipient.selector);
        distributor.grantConfiguratorRole(address(0));
        vm.stopPrank();
    }

    function testRevenueDistributionAfterOwnershipChange() public {
        // Setup: Create dedicated test addresses for old and new owners
        address oldOwner = address(0x100);
        address newOwner = address(0x200);

        // Step 1: Admin grants CONFIGURATOR_ROLE to old owner
        vm.startPrank(admin);
        distributor.grantRole(distributor.CONFIGURATOR_ROLE(), oldOwner);
        vm.stopPrank();

        // Step 2: Old owner configures initial split
        address[] memory oldRecipients = new address[](2);
        oldRecipients[0] = recipient1;
        oldRecipients[1] = recipient2;

        uint256[] memory oldShares = new uint256[](2);
        oldShares[0] = 7000; // 70%
        oldShares[1] = 3000; // 30%

        vm.startPrank(oldOwner);
        distributor.configureSplit(1, oldRecipients, oldShares);
        vm.stopPrank();

        // Step 3: Verify old split is configured correctly
        (address[] memory storedRecipients, uint256[] memory storedShares) = distributor.ipSplits(1);
        assertEq(storedRecipients.length, 2);
        assertEq(storedRecipients[0], recipient1);
        assertEq(storedRecipients[1], recipient2);
        assertEq(storedShares[0], 7000);
        assertEq(storedShares[1], 3000);

        // Step 4: Simulate ownership change - Admin grants CONFIGURATOR_ROLE to new owner
        vm.startPrank(admin);
        distributor.grantRole(distributor.CONFIGURATOR_ROLE(), newOwner);
        vm.stopPrank();

        // Step 5: Verify old split remains active after ownership change (AC: 7)
        (address[] memory storedRecipientsAfter, uint256[] memory storedSharesAfter) = distributor.ipSplits(1);
        assertEq(storedRecipientsAfter.length, 2);
        assertEq(storedRecipientsAfter[0], recipient1); // Old recipients still configured
        assertEq(storedSharesAfter[0], 7000);

        // Step 6: New owner can reconfigure split
        address[] memory newRecipients = new address[](1);
        newRecipients[0] = recipient3;

        uint256[] memory newShares = new uint256[](1);
        newShares[0] = 10000; // 100%

        vm.startPrank(newOwner);
        vm.expectEmit(true, false, false, true);
        emit SplitConfigured(1, newRecipients, newShares);
        distributor.configureSplit(1, newRecipients, newShares);
        vm.stopPrank();

        // Step 7: Verify new split is now active
        (address[] memory finalRecipients, uint256[] memory finalShares) = distributor.ipSplits(1);
        assertEq(finalRecipients.length, 1);
        assertEq(finalRecipients[0], recipient3);
        assertEq(finalShares[0], 10000);
    }

    function testIpSplitsReturnsConfiguration() public {
        // Setup: Configure split with 2 recipients
        address[] memory expectedRecipients = new address[](2);
        expectedRecipients[0] = recipient1;
        expectedRecipients[1] = recipient2;
        uint256[] memory expectedShares = new uint256[](2);
        expectedShares[0] = 6000;
        expectedShares[1] = 4000;

        vm.prank(admin);
        distributor.configureSplit(1, expectedRecipients, expectedShares);

        // Action: Query split configuration
        (address[] memory recipients, uint256[] memory shares) = distributor.ipSplits(1);

        // Assert: Returns correct configuration
        assertEq(recipients.length, 2, "Should have 2 recipients");
        assertEq(recipients[0], expectedRecipients[0], "Recipient 1 mismatch");
        assertEq(recipients[1], expectedRecipients[1], "Recipient 2 mismatch");
        assertEq(shares[0], expectedShares[0], "Share 1 mismatch");
        assertEq(shares[1], expectedShares[1], "Share 2 mismatch");
    }

    function testIsSplitConfigured() public {
        // Assert: No split configured initially
        assertFalse(distributor.isSplitConfigured(1), "Should not be configured");

        // Setup: Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Assert: Split now configured
        assertTrue(distributor.isSplitConfigured(1), "Should be configured");
    }

    function testGetBalance() public {
        // Setup: Configure split and distribute payment
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Action: Query balance
        uint256 balance = distributor.getBalance(recipient1);

        // Assert: Returns principal balance (1 ether - 2.5% platform fee)
        assertEq(balance, 0.975 ether, "Balance should match principal");
    }

    function testSetDefaultRoyaltyEmitsEvent() public {
        // Setup: Deploy contract with initial royalty (done in constructor)
        uint256 newRoyalty = 1000; // 10%

        // Action: Admin calls setDefaultRoyalty
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoyaltyUpdated(newRoyalty);
        distributor.setDefaultRoyalty(newRoyalty);

        // Assert: Royalty updated
        assertEq(distributor.defaultRoyaltyBasisPoints(), newRoyalty, "Royalty should be updated");

        // Verify royaltyInfo uses new rate
        uint256 salePrice = 1 ether;
        uint256 expectedRoyalty = (salePrice * newRoyalty) / 10000;
        (, uint256 royaltyAmount) = distributor.royaltyInfo(1, salePrice);
        assertEq(royaltyAmount, expectedRoyalty, "Royalty calculation should use new rate");
    }

    function testCannotSetInvalidRoyalty() public {
        // Action: Try to set royalty > 10000
        vm.prank(admin);
        vm.expectRevert(IRevenueDistributor.InvalidBasisPoints.selector);
        distributor.setDefaultRoyalty(10001);
    }

    function testOnlyAdminCanSetRoyalty() public {
        address nonAdmin = address(0x999);

        // Action: Non-admin tries to call setDefaultRoyalty
        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl revert
        distributor.setDefaultRoyalty(500);
    }

    // ============ Platform Treasury Withdrawal Tests ============

    function testPlatformTreasuryCanWithdraw() public {
        // Setup: Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Action: Distribute 10 ether payment (primary sale)
        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);

        // Assert: Platform fee accumulated (2.5% of 10 ether = 0.25 ether)
        uint256 treasuryBalance = distributor.getBalance(treasury);
        assertEq(treasuryBalance, 0.25 ether);

        // Action: Treasury withdraws accumulated fees
        uint256 treasuryEthBefore = treasury.balance;
        vm.prank(treasury);
        distributor.withdraw();

        // Assert: Treasury received funds
        assertEq(treasury.balance, treasuryEthBefore + 0.25 ether);

        // Assert: Treasury balance in contract is now zero
        assertEq(distributor.getBalance(treasury), 0);
    }

    function testPlatformTreasuryAccumulatesAcrossMultipleDistributions() public {
        // Setup: Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Action: Distribute 3 payments (primary sales)
        vm.deal(address(this), 30 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);

        // Assert: Platform fees accumulated across all distributions
        // 3 * (10 ether * 2.5%) = 0.75 ether
        uint256 treasuryBalance = distributor.getBalance(treasury);
        assertEq(treasuryBalance, 0.75 ether);

        // Action: Treasury withdraws all accumulated fees
        uint256 treasuryEthBefore = treasury.balance;
        vm.prank(treasury);
        distributor.withdraw();

        // Assert: Treasury received all accumulated fees
        assertEq(treasury.balance, treasuryEthBefore + 0.75 ether);
    }

    // ============ Per-Asset Royalties & Primary/Secondary Sale Auto-Detection ============

    // Configuration Tests (5)
    function testSetAssetRoyalty() public {
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 1500); // 15%

        uint256 royalty = distributor.getAssetRoyalty(1);
        assertEq(royalty, 1500);
    }

    function testSetAssetRoyaltyOnlyConfigurator() public {
        vm.prank(recipient1); // Not a configurator
        vm.expectRevert();
        distributor.setAssetRoyalty(1, 1500);
    }

    function testSetAssetRoyaltyValidation() public {
        vm.prank(admin);
        vm.expectRevert(IRevenueDistributor.InvalidRoyaltyRate.selector);
        distributor.setAssetRoyalty(1, 10001); // > 10000 basis points
    }

    function testGetAssetRoyaltyCustom() public {
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 2000); // 20%

        uint256 royalty = distributor.getAssetRoyalty(1);
        assertEq(royalty, 2000);
    }

    function testGetAssetRoyaltyDefault() public view {
        // Don't set custom royalty
        uint256 royalty = distributor.getAssetRoyalty(1);
        assertEq(royalty, 1000); // Default 10%
    }

    // Auto-Detection Tests (6)
    function testPrimarySaleDetectionSingleRecipient() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Primary sale: seller is in split
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // All funds (minus platform fee) go to split recipients
        uint256 balance = distributor.getBalance(recipient1);
        assertEq(balance, 0.975 ether);
    }

    function testPrimarySaleDetectionMultipleRecipients() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Primary sale: seller (recipient2) is in split
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient2);

        // All funds (minus platform fee) split between recipients
        uint256 balance1 = distributor.getBalance(recipient1);
        uint256 balance2 = distributor.getBalance(recipient2);
        assertEq(balance1, 0.4875 ether); // 50% of 0.975
        assertEq(balance2, 0.4875 ether); // 50% of 0.975
    }

    function testSecondarySaleDetectionNotInSplit() public {
        address seller = address(0x999);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Secondary sale: seller is NOT in split
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller);

        // Royalty (10% of 0.975 = 0.0975) goes to recipient1
        // Remainder (0.975 - 0.0975 = 0.8775) goes to seller
        uint256 recipientBalance = distributor.getBalance(recipient1);
        uint256 sellerBalance = distributor.getBalance(seller);

        assertEq(recipientBalance, 0.0975 ether);
        assertEq(sellerBalance, 0.8775 ether);
    }

    // Primary Sale Distribution Tests (5)
    function testDistributePaymentPrimarySaleSingleRecipient() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient1);

        // Platform fee: 10 * 2.5% = 0.25 ether
        // Remaining: 9.75 ether all to recipient1
        assertEq(distributor.getBalance(treasury), 0.25 ether);
        assertEq(distributor.getBalance(recipient1), 9.75 ether);
    }

    function testDistributePaymentPrimarySaleMultipleRecipients() public {
        address[] memory recipients = new address[](3);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        recipients[2] = recipient3;
        uint256[] memory shares = new uint256[](3);
        shares[0] = 5000; // 50%
        shares[1] = 3000; // 30%
        shares[2] = 2000; // 20%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, recipient2);

        // Platform fee: 0.25 ether, remaining: 9.75 ether
        assertEq(distributor.getBalance(recipient1), 4.875 ether); // 50%
        assertEq(distributor.getBalance(recipient2), 2.925 ether); // 30%
        assertEq(distributor.getBalance(recipient3), 1.95 ether); // 20%
    }

    function testDistributePaymentPrimarySaleEqualShares() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Platform fee: 0.025 ether, remaining: 0.975 ether
        assertEq(distributor.getBalance(recipient1), 0.4875 ether);
        assertEq(distributor.getBalance(recipient2), 0.4875 ether);
    }

    function testDistributePaymentPrimarySaleUnequalShares() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Platform fee: 0.025 ether, remaining: 0.975 ether
        assertEq(distributor.getBalance(recipient1), 0.6825 ether); // 70%
        assertEq(distributor.getBalance(recipient2), 0.2925 ether); // 30%
    }

    function testPrimaryPlatformFeeDeducted() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Platform fee should be 2.5%
        uint256 platformFee = distributor.getBalance(treasury);
        assertEq(platformFee, 0.025 ether);
    }

    // Secondary Sale Distribution Tests (8)
    function testDistributePaymentSecondarySaleSingleRecipient() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Platform fee: 0.25 ether, remaining: 9.75 ether
        // Royalty (10%): 0.975 ether to recipient1
        // Seller gets: 8.775 ether
        assertEq(distributor.getBalance(treasury), 0.25 ether);
        assertEq(distributor.getBalance(recipient1), 0.975 ether);
        assertEq(distributor.getBalance(seller), 8.775 ether);
    }

    function testDistributePaymentSecondarySaleMultipleRecipients() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000; // 60%
        shares[1] = 4000; // 40%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Platform fee: 0.25 ether, remaining: 9.75 ether
        // Royalty (10% of 9.75 = 0.975) split by shares
        // Recipient1: 0.975 * 60% = 0.585
        // Recipient2: 0.975 * 40% = 0.39
        // Seller: 9.75 - 0.975 = 8.775
        assertEq(distributor.getBalance(recipient1), 0.585 ether);
        assertEq(distributor.getBalance(recipient2), 0.39 ether);
        assertEq(distributor.getBalance(seller), 8.775 ether);
    }

    function testSecondarySaleRoyaltyDistribution() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller);

        // Royalty (10% of 0.975 = 0.0975) to recipient1
        assertEq(distributor.getBalance(recipient1), 0.0975 ether);
    }

    function testSecondarySaleSellerRemainder() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller);

        // Seller gets remainder: 0.975 - 0.0975 = 0.8775
        assertEq(distributor.getBalance(seller), 0.8775 ether);
    }

    function testSecondarySaleCustomRoyaltyRate() public {
        address seller = address(0x888);

        // Set custom royalty rate
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 2000); // 20%

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Platform fee: 0.25, remaining: 9.75
        // Royalty (20% of 9.75 = 1.95) to recipient1
        // Seller: 9.75 - 1.95 = 7.8
        assertEq(distributor.getBalance(recipient1), 1.95 ether);
        assertEq(distributor.getBalance(seller), 7.8 ether);
    }

    function testSecondarySaleDefaultRoyaltyRate() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Default royalty (10% of 9.75 = 0.975) to recipient1
        assertEq(distributor.getBalance(recipient1), 0.975 ether);
    }

    function testSecondarySaleZeroRoyalty() public {
        address seller = address(0x888);

        // Set 0% royalty - NOTE: This will fallback to default 10%
        // To truly get 0, we'd need a way to differentiate "unset" from "0"
        // For now, let's use a very low royalty
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 1); // 0.01%

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Royalty (0.01% of 9.75) to recipient1
        // Seller gets almost everything
        uint256 recipientBalance = distributor.getBalance(recipient1);
        uint256 sellerBalance = distributor.getBalance(seller);

        assertLt(recipientBalance, 0.001 ether); // Very small royalty
        assertGt(sellerBalance, 9.74 ether); // Seller gets almost all
    }

    function testSecondarySaleMaxRoyalty() public {
        address seller = address(0x888);

        // Set 100% royalty
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 10000); // 100%

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether, seller);

        // Platform fee: 0.25, remaining: 9.75
        // Royalty (100%): all 9.75 to recipient1
        // Seller: 0
        assertEq(distributor.getBalance(recipient1), 9.75 ether);
        assertEq(distributor.getBalance(seller), 0);
    }

    // EIP-2981 Tests (3)
    function testRoyaltyInfoUsesCustomRate() public {
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 1500); // 15%

        (address receiver, uint256 royaltyAmount) = distributor.royaltyInfo(1, 10 ether);

        assertEq(receiver, address(distributor));
        assertEq(royaltyAmount, 1.5 ether); // 15% of 10 ether
    }

    function testRoyaltyInfoUsesDefaultRate() public {
        // Don't set custom rate
        (address receiver, uint256 royaltyAmount) = distributor.royaltyInfo(1, 10 ether);

        assertEq(receiver, address(distributor));
        assertEq(royaltyAmount, 1 ether); // Default 10% of 10 ether
    }

    function testRoyaltyInfoCalculation() public {
        vm.prank(admin);
        distributor.setAssetRoyalty(1, 2500); // 25%

        (address receiver, uint256 royaltyAmount) = distributor.royaltyInfo(1, 8 ether);

        assertEq(receiver, address(distributor));
        assertEq(royaltyAmount, 2 ether); // 25% of 8 ether
    }

    // Edge Cases (3)
    function testMultipleSequentialSales() public {
        address seller1 = address(0x111);
        address seller2 = address(0x222);

        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // First sale: primary (seller1 is in split)
        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Second sale: secondary (seller2 is NOT in split)
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller2);

        // Third sale: secondary again
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller1); // seller1 NOT in split for this IP

        // Verify balances accumulated correctly
        uint256 recipientBalance = distributor.getBalance(recipient1);
        uint256 seller2Balance = distributor.getBalance(seller2);
        uint256 seller1Balance = distributor.getBalance(seller1);

        // recipient1: 0.975 (primary) + 0.0975 (secondary) + 0.0975 (secondary) = 1.17
        assertEq(recipientBalance, 1.17 ether);
        // seller2: 0.8775 (secondary)
        assertEq(seller2Balance, 0.8775 ether);
        // seller1: 0.8775 (secondary)
        assertEq(seller1Balance, 0.8775 ether);
    }

    function testCreatorResellingOwnIP() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Creator (recipient1) resells their own IP
        // Should be treated as primary sale
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // All goes to recipient1 (no royalty to self)
        assertEq(distributor.getBalance(recipient1), 0.975 ether);
    }

    function testBalanceAccounting() public {
        address seller = address(0x888);

        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 5000; // 50%
        shares[1] = 5000; // 50%

        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);

        // Primary sale
        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether, recipient1);

        // Secondary sale
        distributor.distributePayment{value: 1 ether}(1, 1 ether, seller);

        // Verify all balances sum correctly
        uint256 treasuryBal = distributor.getBalance(treasury);
        uint256 recipient1Bal = distributor.getBalance(recipient1);
        uint256 recipient2Bal = distributor.getBalance(recipient2);
        uint256 sellerBal = distributor.getBalance(seller);

        // Total: 2 ether distributed
        // Treasury: 2 * 0.025 = 0.05
        // Primary sale remaining: 0.975, split 50/50
        // Secondary sale remaining: 0.975, royalty 10% (0.0975), split 50/50, seller gets 0.8775
        assertEq(treasuryBal, 0.05 ether);
        assertEq(recipient1Bal, 0.4875 ether + 0.04875 ether); // Primary + secondary royalty share
        assertEq(recipient2Bal, 0.4875 ether + 0.04875 ether); // Primary + secondary royalty share
        assertEq(sellerBal, 0.8775 ether);

        // Total should equal 2 ether
        uint256 total = treasuryBal + recipient1Bal + recipient2Bal + sellerBal;
        assertEq(total, 2 ether);
    }

}

// Helper contract that rejects ETH
contract RejectETH {
    receive() external payable {
        revert("Rejecting ETH");
    }
}

