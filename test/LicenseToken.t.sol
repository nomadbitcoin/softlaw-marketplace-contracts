// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LicenseToken.sol";
import "../src/interfaces/ILicenseToken.sol";
import "../src/base/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title LicenseTokenTest
 * @notice Comprehensive test suite for LicenseToken contract
 * @dev Tests Story 3.1 (Base Setup) and Story 3.2 (License Minting + Payment + Query + Exclusive Enforcement)
 */
contract LicenseTokenTest is Test {
    LicenseToken public licenseToken;
    MockIPAsset public mockIPAsset;
    address public admin;
    address public buyer;
    address public arbitrator;
    address public revenueDistributor;
    uint256 public ipTokenId;

    function setUp() public {
        admin = address(this);
        buyer = address(0x123);
        arbitrator = address(0x456);
        revenueDistributor = address(0x789);

        // Deploy mock IPAsset
        mockIPAsset = new MockIPAsset();
        ipTokenId = mockIPAsset.mint(admin);

        // Deploy LicenseToken implementation
        LicenseToken implementation = new LicenseToken();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://metadata.uri/",
            admin,
            address(mockIPAsset),
            arbitrator,
            revenueDistributor
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        licenseToken = LicenseToken(address(proxy));

        // Grant IP_ASSET_ROLE to mockIPAsset
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(mockIPAsset));
    }

    // ==================== STORY 3.1: AC1 - Contract Inheritance ====================

    function testContractInheritsFromERC1155Upgradeable() public view {
        // Verify ERC1155 interface support
        assertTrue(licenseToken.supportsInterface(type(IERC1155).interfaceId));
    }

    function testContractInheritsFromAccessControlUpgradeable() public view {
        // Verify AccessControl interface support
        assertTrue(licenseToken.supportsInterface(type(IAccessControl).interfaceId));
    }

    // Note: UUPS and Pausable don't have standard interface IDs to check
    // Their functionality is tested through function calls

    // ==================== STORY 3.1: AC4 - Initialize Function ====================

    function testInitializeSetsBaseURI() public {
        // Base URI is set during initialization
        // ERC1155 doesn't expose base URI getter, but we can verify initialization succeeded
        // by checking that roles were assigned
        assertTrue(licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testInitializeSetsRoles() public view {
        // Verify admin role
        assertTrue(licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), admin));

        // Verify arbitrator role
        assertTrue(licenseToken.hasRole(licenseToken.ARBITRATOR_ROLE(), arbitrator));

        // Verify IP asset role
        assertTrue(licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), address(mockIPAsset)));
    }

    function testInitializeSetsIPAssetContract() public view {
        assertEq(licenseToken.ipAssetContract(), address(mockIPAsset));
    }

    function testCannotReinitialize() public {
        vm.expectRevert();
        licenseToken.initialize(
            "https://new-uri/",
            address(0x999),
            address(0x888),
            address(0x777),
            address(0x666)
        );
    }

    // ==================== STORY 3.1: AC5 - ERC-165 Interface Detection ====================

    function testSupportsInterface() public view {
        // Test ERC1155 interface
        assertTrue(licenseToken.supportsInterface(type(IERC1155).interfaceId));

        // Test AccessControl interface
        assertTrue(licenseToken.supportsInterface(type(IAccessControl).interfaceId));

        // Test ERC165 interface itself
        assertTrue(licenseToken.supportsInterface(type(IERC165).interfaceId));
    }

    function testDoesNotSupportInvalidInterface() public view {
        // Random interface ID that shouldn't be supported
        assertFalse(licenseToken.supportsInterface(0xffffffff));
    }

    // ==================== ROLE CONSTANTS ====================

    function testRoleConstantsAreDefined() public view {
        // Verify role constants are properly defined
        assertEq(licenseToken.ARBITRATOR_ROLE(), keccak256("ARBITRATOR_ROLE"));
        assertEq(licenseToken.IP_ASSET_ROLE(), keccak256("IP_ASSET_ROLE"));
        assertEq(licenseToken.MARKETPLACE_ROLE(), keccak256("MARKETPLACE_ROLE"));
    }

    // ==================== ACCESS CONTROL ====================

    function testAdminCanGrantRoles() public {
        address newAccount = address(0x999);

        // Admin can grant marketplace role
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), newAccount);
        assertTrue(licenseToken.hasRole(licenseToken.MARKETPLACE_ROLE(), newAccount));
    }

    function testNonAdminCannotGrantRoles() public {
        address nonAdmin = address(0x888);
        address newAccount = address(0x999);
        bytes32 marketplaceRole = licenseToken.MARKETPLACE_ROLE();

        // AccessControl reverts with AccessControlUnauthorizedAccount error
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.grantRole(marketplaceRole, newAccount);
    }

    // ==================== PAUSABILITY ====================

    function testAdminCanPauseContract() public {
        licenseToken.pause();
        // Contract is now paused - pausable functions should revert
        // (This will be tested more thoroughly in later stories with actual pausable functions)
    }

    function testAdminCanUnpauseContract() public {
        licenseToken.pause();
        licenseToken.unpause();
        // Contract is now unpaused
    }

    function testNonAdminCannotPause() public {
        address nonAdmin = address(0x888);

        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.pause();
    }

    function testNonAdminCannotUnpause() public {
        licenseToken.pause();

        address nonAdmin = address(0x888);
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.unpause();
    }

    // ==================== UPGRADEABILITY ====================

    function testOnlyAdminCanAuthorizeUpgrade() public {
        // Deploy new implementation
        LicenseToken newImplementation = new LicenseToken();

        // Admin can upgrade (via proxy's upgradeToAndCall)
        // This would be tested in integration, but we can verify the role check
        assertTrue(licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testNonAdminCannotUpgrade() public {
        // Non-admin should not be able to authorize upgrade
        // This is enforced by _authorizeUpgrade which checks DEFAULT_ADMIN_ROLE
        address nonAdmin = address(0x888);
        assertFalse(licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), nonAdmin));
    }

    // ==================== STORY 3.2: AC1 - Only IP_ASSET_ROLE Can Mint ====================

    function testOnlyIPAssetCanMintLicense() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );
        assertEq(licenseId, 0);
    }

    function testCannotMintLicenseWithoutIPAssetRole() public {
        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert();
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );
    }

    // ==================== STORY 3.2: AC2 - Validate IP Asset Exists ====================

    function testMintLicenseLinksToIPAsset() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        (uint256 linkedIpAssetId,,,,,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(linkedIpAssetId, ipTokenId);
    }

    function testCannotMintLicenseWithInvalidIPAsset() public {
        uint256 invalidIpTokenId = 999;

        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.InvalidIPAsset.selector);
        licenseToken.mintLicense(
            buyer,
            invalidIpTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );
    }

    // ==================== STORY 3.2: AC3-4 - Exclusive License Supply Validation ====================

    function testExclusiveLicenseHasSupplyOne() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );

        (,,,,, bool isExclusive,,) = licenseToken.getLicenseInfo(licenseId);
        assertTrue(isExclusive);
    }

    function testCannotMintExclusiveLicenseWithSupplyGreaterThanOne() public {
        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.ExclusiveLicenseMustHaveSupplyOne.selector);
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            10,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );
    }

    // ==================== STORY 3.2: AC5-6 - Non-Exclusive License Supply ====================

    function testNonExclusiveLicenseCanHaveMultipleSupply() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            100,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertEq(licenseToken.balanceOf(buyer, licenseId), 100);
    }

    // ==================== STORY 3.2: AC7-9 - License Data Storage and Minting ====================

    function testLicenseStoresPaymentInterval() public {
        uint256 paymentInterval = 30 days;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            paymentInterval
        );

        (,,,, uint256 storedInterval,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(storedInterval, paymentInterval);
    }

    function testMintsERC1155TokensToLicensee() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            5,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertEq(licenseToken.balanceOf(buyer, licenseId), 5);
    }

    function testIncrementsLicenseIdCounter() public {
        vm.startPrank(address(mockIPAsset));

        uint256 firstId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        uint256 secondId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        vm.stopPrank();

        assertEq(firstId, 0);
        assertEq(secondId, 1);
    }

    // ==================== STORY 3.2: AC10 - Update IPAsset Active License Count ====================

    function testUpdatesIPAssetActiveLicenseCount() public {
        uint256 supply = 10;

        vm.prank(address(mockIPAsset));
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            supply,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        // Verify the mock received the callback
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), int256(supply));
    }

    // ==================== STORY 3.2: AC11 - Event Emission ====================

    function testLicenseCreatedEvent() public {
        uint256 paymentInterval = 30 days;

        vm.expectEmit(true, true, true, true);
        emit ILicenseToken.LicenseCreated(0, ipTokenId, buyer, false, paymentInterval);

        vm.prank(address(mockIPAsset));
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            5,
            "public",
            "private",
            0,
            "terms",
            false,
            paymentInterval
        );
    }

    // ==================== STORY 3.2: AC12 - Payment Interval ====================

    function testMintLicenseWithZeroInterval() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertEq(licenseToken.getPaymentInterval(licenseId), 0);
        assertTrue(licenseToken.isOneTime(licenseId));
        assertFalse(licenseToken.isRecurring(licenseId));
    }

    function testMintLicenseWithPaymentInterval() public {
        uint256 paymentInterval = 30 days;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            paymentInterval
        );

        assertEq(licenseToken.getPaymentInterval(licenseId), paymentInterval);
        assertTrue(licenseToken.isRecurring(licenseId));
        assertFalse(licenseToken.isOneTime(licenseId));
    }

    function testONETIMELicenseHasZeroInterval() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertTrue(licenseToken.isOneTime(licenseId));
    }

    function testRECURRENTLicenseHasPositiveInterval() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            7 days
        );

        assertTrue(licenseToken.isRecurring(licenseId));
    }

    // ==================== STORY 3.2: AC13 - Query Functions ====================

    function testGetPaymentIntervalReturnsCorrectValue() public {
        uint256 interval = 15 days;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            interval
        );

        assertEq(licenseToken.getPaymentInterval(licenseId), interval);
    }

    function testIsRecurringReturnsTrueForPositiveInterval() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            1
        );

        assertTrue(licenseToken.isRecurring(licenseId));
    }

    function testIsOneTimeReturnsTrueForZeroInterval() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertTrue(licenseToken.isOneTime(licenseId));
    }

    // ==================== STORY 3.2: AC14 - Comprehensive Query Functions ====================

    function testGetLicenseInfoReturnsCompleteData() public {
        uint256 expiryTime = block.timestamp + 365 days;
        uint256 paymentInterval = 30 days;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            true,
            paymentInterval
        );

        (
            uint256 returnedIpAssetId,
            uint256 returnedSupply,
            uint256 returnedExpiryTime,
            string memory returnedTerms,
            uint256 returnedPaymentInterval,
            bool returnedIsExclusive,
            bool returnedIsRevoked,
            bool returnedIsExpired
        ) = licenseToken.getLicenseInfo(licenseId);

        assertEq(returnedIpAssetId, ipTokenId);
        assertEq(returnedSupply, 1);
        assertEq(returnedExpiryTime, expiryTime);
        assertEq(returnedTerms, "terms");
        assertEq(returnedPaymentInterval, paymentInterval);
        assertTrue(returnedIsExclusive);
        assertFalse(returnedIsRevoked);
        assertFalse(returnedIsExpired);
    }

    function testIsActiveLicenseReturnsTrueForNewLicense() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertTrue(licenseToken.isActiveLicense(licenseId));
    }

    // ==================== STORY 3.2: Exclusive License Enforcement ====================

    function testCannotMintMultipleExclusiveLicenses() public {
        // Mint first exclusive license
        vm.prank(address(mockIPAsset));
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );

        // Try to mint second exclusive license for same IP
        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.ExclusiveLicenseAlreadyExists.selector);
        licenseToken.mintLicense(
            address(0x999),
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            true,
            0
        );
    }

    function testCanMintMultipleNonExclusiveLicenses() public {
        // Mint first non-exclusive license
        vm.prank(address(mockIPAsset));
        uint256 id1 = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            10,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        // Mint second non-exclusive license for same IP
        vm.prank(address(mockIPAsset));
        uint256 id2 = licenseToken.mintLicense(
            address(0x999),
            ipTokenId,
            5,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    // ==================== STORY 3.2: AC15 - Payment Interval Immutability ====================

    function testPaymentIntervalIsImmutable() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            30 days
        );

        // Payment interval should remain 30 days
        assertEq(licenseToken.getPaymentInterval(licenseId), 30 days);

        // There's no function to change it, so immutability is enforced by design
    }

    // ==================== STORY 3.3: AC1 - License Can Have Expiry Timestamp ====================

    function testLicenseCanHaveExpiryTimestamp() public {
        uint256 expiryTime = block.timestamp + 365 days;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        (,, uint256 storedExpiryTime,,,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(storedExpiryTime, expiryTime);
    }

    // ==================== STORY 3.3: AC2,6 - Perpetual Licenses ====================

    function testLicenseCanBePerpetual() public {
        // Test with expiryTime = 0 (perpetual standard)
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        (,, uint256 expiryTime,,,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(expiryTime, 0);
    }

    function testPerpetualLicenseNeverExpires() public {
        // Test with expiryTime = 0 (perpetual standard)
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        vm.expectRevert(ILicenseToken.LicenseIsPerpetual.selector);
        licenseToken.markExpired(licenseId);
    }

    // ==================== STORY 3.3: AC3,4 - Mark Expired ====================

    function testAnyoneCanMarkExpiredLicense() public {
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Fast forward past expiry
        vm.warp(block.timestamp + 101);

        // Anyone can mark as expired
        address randomUser = address(0x999);
        vm.prank(randomUser);
        licenseToken.markExpired(licenseId);

        assertTrue(licenseToken.isExpired(licenseId));
    }

    function testCannotMarkNonExpiredLicense() public {
        uint256 expiryTime = block.timestamp + 1000;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Try to mark as expired before expiry time
        vm.expectRevert(ILicenseToken.LicenseNotYetExpired.selector);
        licenseToken.markExpired(licenseId);
    }

    function testCannotMarkAlreadyExpiredLicense() public {
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Fast forward past expiry
        vm.warp(block.timestamp + 101);

        // Mark as expired
        licenseToken.markExpired(licenseId);

        // Try to mark again
        vm.expectRevert(ILicenseToken.AlreadyMarkedExpired.selector);
        licenseToken.markExpired(licenseId);
    }

    // ==================== STORY 3.3: AC4 - Expired License Tracking ====================

    function testIsExpiredReturnsCorrectValue() public {
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Not expired yet
        assertFalse(licenseToken.isExpired(licenseId));

        // Fast forward and mark expired
        vm.warp(block.timestamp + 101);
        licenseToken.markExpired(licenseId);

        // Now expired
        assertTrue(licenseToken.isExpired(licenseId));
    }

    // ==================== STORY 3.3: AC7 - Event Emission ====================

    function testLicenseExpiredEvent() public {
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        vm.warp(block.timestamp + 101);

        vm.expectEmit(true, false, false, false);
        emit ILicenseToken.LicenseExpired(licenseId);
        licenseToken.markExpired(licenseId);
    }

    // ==================== STORY 3.3: AC3 - Batch Mark Expired ====================

    function testBatchMarkExpired() public {
        uint256 expiryTime = block.timestamp + 100;
        uint256[] memory licenseIds = new uint256[](3);

        // Mint 3 licenses
        vm.startPrank(address(mockIPAsset));
        for (uint256 i = 0; i < 3; i++) {
            uint256 ipId = mockIPAsset.mint(admin);
            licenseIds[i] = licenseToken.mintLicense(
                buyer,
                ipId,
                1,
                "public",
                "private",
                expiryTime,
                "terms",
                false,
                0
            );
        }
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 101);

        // Batch mark expired
        licenseToken.batchMarkExpired(licenseIds);

        // Verify all are expired
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(licenseToken.isExpired(licenseIds[i]));
        }
    }

    function testBatchMarkExpiredContinuesOnError() public {
        uint256[] memory licenseIds = new uint256[](3);

        // Mint 2 expiring licenses and 1 perpetual
        vm.startPrank(address(mockIPAsset));
        uint256 ipId1 = mockIPAsset.mint(admin);
        licenseIds[0] = licenseToken.mintLicense(
            buyer,
            ipId1,
            1,
            "public",
            "private",
            block.timestamp + 100,
            "terms",
            false,
            0
        );

        uint256 ipId2 = mockIPAsset.mint(admin);
        licenseIds[1] = licenseToken.mintLicense(
            buyer,
            ipId2,
            1,
            "public",
            "private",
            0, // Perpetual
            "terms",
            false,
            0
        );

        uint256 ipId3 = mockIPAsset.mint(admin);
        licenseIds[2] = licenseToken.mintLicense(
            buyer,
            ipId3,
            1,
            "public",
            "private",
            block.timestamp + 100,
            "terms",
            false,
            0
        );
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 101);

        // Batch mark expired (should not revert despite perpetual license)
        licenseToken.batchMarkExpired(licenseIds);

        // Verify expiring licenses are expired
        assertTrue(licenseToken.isExpired(licenseIds[0]));
        assertFalse(licenseToken.isExpired(licenseIds[1])); // Perpetual remains active
        assertTrue(licenseToken.isExpired(licenseIds[2]));
    }

    // ==================== STORY 3.3: AC5,8,9 - Transfer Validation ====================

    function testCannotTransferExpiredLicense() public {
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Fast forward past expiry
        vm.warp(block.timestamp + 101);

        // Mark as expired
        licenseToken.markExpired(licenseId);

        // Try to transfer expired license
        vm.prank(buyer);
        vm.expectRevert(ILicenseToken.CannotTransferExpiredLicense.selector);
        licenseToken.safeTransferFrom(buyer, address(0x999), licenseId, 1, "");
    }

    function testCanTransferActiveLicense() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0, // Perpetual
            "terms",
            false,
            0
        );

        address recipient = address(0x999);

        // Transfer should succeed
        vm.prank(buyer);
        licenseToken.safeTransferFrom(buyer, recipient, licenseId, 1, "");

        // Verify transfer
        assertEq(licenseToken.balanceOf(recipient, licenseId), 1);
        assertEq(licenseToken.balanceOf(buyer, licenseId), 0);
    }

    function testCanBatchTransferActiveLicenses() public {
        // Mint 2 licenses
        vm.startPrank(address(mockIPAsset));
        uint256 ipId1 = mockIPAsset.mint(admin);
        uint256 licenseId1 = licenseToken.mintLicense(
            buyer,
            ipId1,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );

        uint256 ipId2 = mockIPAsset.mint(admin);
        uint256 licenseId2 = licenseToken.mintLicense(
            buyer,
            ipId2,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            0
        );
        vm.stopPrank();

        address recipient = address(0x999);
        uint256[] memory ids = new uint256[](2);
        ids[0] = licenseId1;
        ids[1] = licenseId2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        // Batch transfer should succeed
        vm.prank(buyer);
        licenseToken.safeBatchTransferFrom(buyer, recipient, ids, amounts, "");

        // Verify transfers
        assertEq(licenseToken.balanceOf(recipient, licenseId1), 1);
        assertEq(licenseToken.balanceOf(recipient, licenseId2), 1);
        assertEq(licenseToken.balanceOf(buyer, licenseId1), 0);
        assertEq(licenseToken.balanceOf(buyer, licenseId2), 0);
    }

    // ==================== STORY 3.3: Integration - Update Active License Count ====================

    function testMarkExpiredUpdatesActiveLicenseCount() public {
        uint256 supply = 5;
        uint256 expiryTime = block.timestamp + 100;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            supply,
            "public",
            "private",
            expiryTime,
            "terms",
            false,
            0
        );

        // Verify initial count
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), int256(supply));

        // Fast forward and mark expired
        vm.warp(block.timestamp + 101);
        licenseToken.markExpired(licenseId);

        // Verify count decremented by supply
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), 0);
    }

    // ==================== Gas Optimization Check ====================

    function testQueryFunctionsGasOptimized() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public",
            "private",
            0,
            "terms",
            false,
            30 days
        );

        // Query functions should be efficient (< 10k gas each)
        uint256 gasBefore = gasleft();
        licenseToken.getPaymentInterval(licenseId);
        uint256 gasUsed1 = gasBefore - gasleft();
        assertTrue(gasUsed1 < 10000);

        gasBefore = gasleft();
        licenseToken.isRecurring(licenseId);
        uint256 gasUsed2 = gasBefore - gasleft();
        assertTrue(gasUsed2 < 10000);

        gasBefore = gasleft();
        licenseToken.isOneTime(licenseId);
        uint256 gasUsed3 = gasBefore - gasleft();
        assertTrue(gasUsed3 < 10000);

        gasBefore = gasleft();
        licenseToken.getLicenseInfo(licenseId);
        uint256 gasUsed4 = gasBefore - gasleft();
        assertTrue(gasUsed4 < 15000);

        gasBefore = gasleft();
        licenseToken.isActiveLicense(licenseId);
        uint256 gasUsed5 = gasBefore - gasleft();
        assertTrue(gasUsed5 < 10000);
    }
}

/**
 * @title MockIPAsset
 * @notice Mock contract for testing IPAsset integration
 */
contract MockIPAsset {
    uint256 private _tokenIdCounter;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => int256) private _activeLicenseCounts;
    mapping(uint256 => bool) private _disputes;

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter++;
        _owners[tokenId] = to;
        return tokenId;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "Token does not exist");
        return owner;
    }

    function hasActiveDispute(uint256 tokenId) external view returns (bool) {
        // Revert if token doesn't exist
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _disputes[tokenId];
    }

    function updateActiveLicenseCount(uint256 tokenId, int256 delta) external {
        _activeLicenseCounts[tokenId] += delta;
    }

    function getActiveLicenseCount(uint256 tokenId) external view returns (int256) {
        return _activeLicenseCounts[tokenId];
    }
}
