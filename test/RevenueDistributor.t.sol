// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/RevenueDistributor.sol";
import "../src/interfaces/IRevenueDistributor.sol";

contract RevenueDistributorTest is Test {
    RevenueDistributor public distributor;
    
    address public admin = address(1);
    address public treasury = address(2);
    address public recipient1 = address(3);
    address public recipient2 = address(4);
    address public recipient3 = address(5);
    
    uint256 constant PLATFORM_FEE = 250; // 2.5%
    uint256 constant DEFAULT_ROYALTY = 1000; // 10%
    uint256 constant INTEREST_RATE = 500; // 5% monthly
    
    event PaymentDistributed(uint256 indexed ipAssetId, uint256 amount, uint256 platformFee);
    event SplitConfigured(uint256 indexed ipAssetId, address[] recipients, uint256[] shares);
    event Withdrawal(address indexed recipient, uint256 principal, uint256 interest, uint256 total);
    event InterestAccrued(address indexed recipient, uint256 amount, uint256 monthsDelayed);
    
    function setUp() public {
        vm.startPrank(admin);
        distributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY);
        distributor.grantRole(distributor.CONFIGURATOR_ROLE(), admin);
        vm.stopPrank();
    }

    function testConstructorSetsVariables() public {
        vm.prank(admin);
        RevenueDistributor newDistributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY);

        assertEq(newDistributor.platformTreasury(), treasury);
        assertEq(newDistributor.platformFeeBasisPoints(), PLATFORM_FEE);
        assertEq(newDistributor.defaultRoyaltyBasisPoints(), DEFAULT_ROYALTY);
    }

    function testConstructorGrantsAdminRole() public {
        vm.prank(admin);
        RevenueDistributor newDistributor = new RevenueDistributor(treasury, PLATFORM_FEE, DEFAULT_ROYALTY);

        assertTrue(newDistributor.hasRole(newDistributor.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testConstructorRevertsWithInvalidTreasury() public {
        vm.prank(admin);
        vm.expectRevert("Invalid treasury address");
        new RevenueDistributor(address(0), PLATFORM_FEE, DEFAULT_ROYALTY);
    }

    function testConstructorRevertsWithInvalidPlatformFee() public {
        vm.prank(admin);
        vm.expectRevert("Invalid platform fee");
        new RevenueDistributor(treasury, 10001, DEFAULT_ROYALTY);
    }

    function testConstructorRevertsWithInvalidRoyalty() public {
        vm.prank(admin);
        vm.expectRevert("Invalid royalty");
        new RevenueDistributor(treasury, PLATFORM_FEE, 10001);
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
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Distribute 1 ether
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        // Platform fee = 1 ether * 2.5% = 0.025 ether
        assertEq(treasury.balance, treasuryBalanceBefore + 0.025 ether);
        
        // Recipient gets 97.5% = 0.975 ether
        (uint256 principal,,) = distributor.getBalanceWithInterest(recipient1);
        assertEq(principal, 0.975 ether);
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
        
        // Distribute payment
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
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
        
        // Distribute payment
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        // recipient2 tries to withdraw (has no balance)
        vm.prank(recipient2);
        vm.expectRevert("No balance to withdraw");
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
        
        // Distribute payment
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        // First withdrawal succeeds
        vm.prank(recipient1);
        distributor.withdraw();
        
        // Second withdrawal fails (no balance left)
        vm.prank(recipient1);
        vm.expectRevert("No balance to withdraw");
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

        // Distribution should not revert even if one recipient fails
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);

        // recipient1 should still receive their share
        (uint256 principal,,) = distributor.getBalanceWithInterest(recipient1);
        assertGt(principal, 0);
    }
    
    // ============ BR-004.7: A delay in payments generates interest ============
    
    function testDelayedPaymentGeneratesInterest() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute payment
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        // Fast forward 30 days (1 month)
        vm.warp(block.timestamp + 30 days);
        
        (uint256 principal, uint256 interest, uint256 total) = distributor.getBalanceWithInterest(recipient1);
        
        assertGt(interest, 0);
        assertEq(total, principal + interest);
    }
    
    // ============ BR-004.8: Interest calculations use fixed monthly rate of 5% ============
    
    function testInterestCalculationAt5PercentMonthly() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute 1 ether (after platform fee = 0.975 ether)
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        (uint256 principal,,) = distributor.getBalanceWithInterest(recipient1);
        
        // Fast forward 30 days (1 month)
        vm.warp(block.timestamp + 30 days);
        
        (,uint256 interest,) = distributor.getBalanceWithInterest(recipient1);
        
        // Interest should be 5% of principal
        uint256 expectedInterest = (principal * 500) / 10000; // 5%
        assertEq(interest, expectedInterest);
    }
    
    function testInterestCompoundsMonthly() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute 1 ether
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        (uint256 principal,,) = distributor.getBalanceWithInterest(recipient1);
        
        // Fast forward 60 days (2 months)
        vm.warp(block.timestamp + 60 days);
        
        (,uint256 interest2Months,) = distributor.getBalanceWithInterest(recipient1);
        
        // Calculate expected compound interest
        // Month 1: principal * 1.05
        // Month 2: (principal * 1.05) * 1.05 = principal * 1.1025
        uint256 expectedTotal = (principal * 11025) / 10000;
        uint256 expectedInterest = expectedTotal - principal;
        
        assertEq(interest2Months, expectedInterest);
    }
    
    function testInterestAccruedEvent() public {
        // Configure split
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        // Distribute payment
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);
        
        // Withdraw should emit interest event
        vm.prank(recipient1);
        vm.expectEmit(true, false, false, false);
        emit InterestAccrued(recipient1, 0, 1); // Will calculate actual amount
        distributor.withdraw();
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
        
        // Distribute 10 ether
        vm.deal(address(this), 10 ether);
        distributor.distributePayment{value: 10 ether}(1, 10 ether);
        
        // After platform fee (2.5%), remaining = 9.75 ether
        (uint256 principal1,,) = distributor.getBalanceWithInterest(recipient1);
        (uint256 principal2,,) = distributor.getBalanceWithInterest(recipient2);
        (uint256 principal3,,) = distributor.getBalanceWithInterest(recipient3);
        
        assertEq(principal1, 4.875 ether); // 50% of 9.75
        assertEq(principal2, 2.925 ether); // 30% of 9.75
        assertEq(principal3, 1.95 ether);  // 20% of 9.75
    }
    
    function testWithdrawalEvent() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;
        
        vm.prank(admin);
        distributor.configureSplit(1, recipients, shares);
        
        vm.deal(address(this), 1 ether);
        distributor.distributePayment{value: 1 ether}(1, 1 ether);
        
        vm.warp(block.timestamp + 30 days);
        
        vm.prank(recipient1);
        vm.expectEmit(true, false, false, false);
        emit Withdrawal(recipient1, 0, 0, 0); // Actual values calculated
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
    
    function testDistributeToUnconfiguredIPAsset() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert("No split configured");
        distributor.distributePayment{value: 1 ether}(999, 1 ether);
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
}

// Helper contract that rejects ETH
contract RejectETH {
    receive() external payable {
        revert("Rejecting ETH");
    }
}

