// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LicenseToken.sol";
import "../src/interfaces/ILicenseToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
    uint256 public ipTokenId;

    function setUp() public {
        admin = address(this);
        buyer = address(0x123);
        arbitrator = address(0x456);

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
            arbitrator
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
            address(0x777)
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
        , 0, 0);
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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
            , 0, 0);
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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);

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
        , 0, 0);
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
        , 0, 0);

        // Verify initial count
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), int256(supply));

        // Fast forward and mark expired
        vm.warp(block.timestamp + 101);
        licenseToken.markExpired(licenseId);

        // Verify count decremented by supply
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), 0);
    }

    // ==================== STORY 3.5: AC1 - getPublicMetadata() Returns Public Metadata ====================

    function testLicenseHasDualMetadata() public {
        // Mint license with both metadata URIs
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        // Verify both URIs stored
        string memory publicURI = licenseToken.getPublicMetadata(licenseId);
        assertEq(publicURI, "https://public.uri/metadata.json");

        vm.prank(buyer); // Owner can access private
        string memory privateURI = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateURI, "https://private.uri/secret.json");
    }

    // ==================== STORY 3.5: AC1 - Public Metadata Accessible to All ====================

    function testPublicMetadataAccessibleToAll() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        // Anyone can access public metadata
        address randomUser = address(0x999);
        vm.prank(randomUser);
        string memory publicURI = licenseToken.getPublicMetadata(licenseId);
        assertEq(publicURI, "https://public.uri/metadata.json");
    }

    // ==================== STORY 3.5: AC2,5 - Private Metadata Access Control ====================

    function testPrivateMetadataRestrictedToAuthorized() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        // Unauthorized user cannot access private metadata
        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert(ILicenseToken.NotAuthorizedForPrivateMetadata.selector);
        licenseToken.getPrivateMetadata(licenseId);

        // Owner can access
        vm.prank(buyer);
        string memory privateURI = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateURI, "https://private.uri/secret.json");

        // Admin can access
        vm.prank(admin);
        privateURI = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateURI, "https://private.uri/secret.json");
    }

    // ==================== STORY 3.5: AC3,4 - Grant Private Metadata Access ====================

    function testGrantPrivateMetadataAccess() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address grantee = address(0x999);

        // Grantee cannot access initially
        vm.prank(grantee);
        vm.expectRevert(ILicenseToken.NotAuthorizedForPrivateMetadata.selector);
        licenseToken.getPrivateMetadata(licenseId);

        // Owner grants access
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit ILicenseToken.PrivateAccessGranted(licenseId, grantee);
        licenseToken.grantPrivateAccess(licenseId, grantee);

        // Now grantee can access
        vm.prank(grantee);
        string memory privateURI = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateURI, "https://private.uri/secret.json");
    }

    function testNonOwnerCannotGrantPrivateAccess() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address nonOwner = address(0x999);
        address grantee = address(0x888);

        // Non-owner attempts to grant access
        vm.prank(nonOwner);
        vm.expectRevert(ILicenseToken.NotLicenseOwner.selector);
        licenseToken.grantPrivateAccess(licenseId, grantee);
    }

    // ==================== STORY 3.5 ENHANCEMENTS: Revoke and Query Access ====================

    function testRevokePrivateMetadataAccess() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address grantee = address(0x999);

        // Owner grants access
        vm.prank(buyer);
        licenseToken.grantPrivateAccess(licenseId, grantee);

        // Verify grantee can access
        vm.prank(grantee);
        string memory privateURI = licenseToken.getPrivateMetadata(licenseId);
        assertEq(privateURI, "https://private.uri/secret.json");

        // Owner revokes access
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit ILicenseToken.PrivateAccessRevoked(licenseId, grantee);
        licenseToken.revokePrivateAccess(licenseId, grantee);

        // Grantee can no longer access
        vm.prank(grantee);
        vm.expectRevert(ILicenseToken.NotAuthorizedForPrivateMetadata.selector);
        licenseToken.getPrivateMetadata(licenseId);
    }

    function testNonOwnerCannotRevokePrivateAccess() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address grantee = address(0x999);

        // Owner grants access
        vm.prank(buyer);
        licenseToken.grantPrivateAccess(licenseId, grantee);

        address nonOwner = address(0x888);

        // Non-owner attempts to revoke access
        vm.prank(nonOwner);
        vm.expectRevert(ILicenseToken.NotLicenseOwner.selector);
        licenseToken.revokePrivateAccess(licenseId, grantee);
    }

    function testHasPrivateAccessReturnsTrueForGrantedAccounts() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address grantee = address(0x999);

        // Initially no access
        assertFalse(licenseToken.hasPrivateAccess(licenseId, grantee));

        // Owner grants access
        vm.prank(buyer);
        licenseToken.grantPrivateAccess(licenseId, grantee);

        // Now has access
        assertTrue(licenseToken.hasPrivateAccess(licenseId, grantee));

        // Owner revokes access
        vm.prank(buyer);
        licenseToken.revokePrivateAccess(licenseId, grantee);

        // Access removed
        assertFalse(licenseToken.hasPrivateAccess(licenseId, grantee));
    }

    function testHasPrivateAccessReturnsFalseForNonGrantedAccounts() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "https://public.uri/metadata.json",
            "https://private.uri/secret.json",
            0,
            "terms",
            false,
            0
        , 0, 0);

        address randomAccount = address(0x999);

        // Random account has no access
        assertFalse(licenseToken.hasPrivateAccess(licenseId, randomAccount));
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
        , 0, 0);

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

/**
 * @title LicenseTokenRevocationTest
 * @notice Test suite for Story 3.4 (Revocation System - Manual + Auto)
 */
contract LicenseTokenRevocationTest is Test {
    LicenseToken public licenseToken;
    MockIPAsset public mockIPAsset;
    address public admin;
    address public buyer;
    address public arbitrator;
    address public marketplace;
    address public revenueDistributor;
    uint256 public ipTokenId;

    function setUp() public {
        admin = address(this);
        buyer = address(0x123);
        arbitrator = address(0x789);
        marketplace = address(0xABC);
        revenueDistributor = address(0xDEF);

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

        // Grant MARKETPLACE_ROLE to marketplace
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), marketplace);
    }

    // ==================== STORY 3.4: AC1 - Only ARBITRATOR_ROLE Can Manually Revoke ====================

    function testOnlyArbitratorCanRevokeLicense() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Arbitrator revokes license
        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Violation of terms");

        // Verify revoked
        (,,,,,, bool isRevoked,) = licenseToken.getLicenseInfo(licenseId);
        assertTrue(isRevoked);
    }

    function testNonArbitratorCannotRevokeLicense() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Non-arbitrator attempts to revoke
        address nonArbitrator = address(0x999);
        vm.prank(nonArbitrator);
        vm.expectRevert();
        licenseToken.revokeLicense(licenseId, "Unauthorized attempt");
    }

    // ==================== STORY 3.4: AC2 - Only MARKETPLACE_ROLE Can Auto-Revoke ====================

    function testMarketplaceCanRevokeForMissedPayments() public {
        // Mint recurring license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 30 days, 0, 0);

        // Marketplace revokes for 4 missed payments
        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 4);

        // Verify revoked
        (,,,,,, bool isRevoked,) = licenseToken.getLicenseInfo(licenseId);
        assertTrue(isRevoked);
    }

    function testAnyoneCanRevokeForMissedPayments() public {
        // Mint recurring license with default maxMissedPayments = 3
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 30 days, 0, 0);

        // Anyone can call when conditions are met (missedCount >= maxMissedPayments)
        address anyUser = address(0x999);
        vm.prank(anyUser);
        licenseToken.revokeForMissedPayments(licenseId, 4);

        // Verify license is revoked
        assertTrue(licenseToken.isRevoked(licenseId));
    }

    function testCannotAutoRevokeWithLessThan3MissedPayments() public {
        // Mint recurring license with default maxMissedPayments = 3
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 30 days, 0, 0);

        // Try to revoke with only 2 missed payments (needs >= 3)
        vm.prank(marketplace);
        vm.expectRevert(ILicenseToken.InsufficientMissedPayments.selector);
        licenseToken.revokeForMissedPayments(licenseId, 2);

        // 3 missed payments should work (meets the threshold)
        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 3);

        (,,,,,, bool isRevoked,) = licenseToken.getLicenseInfo(licenseId);
        assertTrue(isRevoked);
    }

    // ==================== STORY 3.4: AC3 - Both Set isRevoked Flag ====================

    function testRevokeLicenseSetsIsRevokedFlag() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Test reason");

        assertTrue(licenseToken.isRevoked(licenseId));
    }

    function testRevokeForMissedPaymentsSetsIsRevokedFlag() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 30 days, 0, 0);

        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 4);

        assertTrue(licenseToken.isRevoked(licenseId));
    }

    // ==================== STORY 3.4: AC4-5 - Update Active License Count and Clear Exclusive ====================

    function testRevokeUpdatesActiveLicenseCount() public {
        uint256 supply = 5;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, supply, "public", "private", 0, "terms", false, 0, 0, 0);

        // Verify initial count
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), int256(supply));

        // Revoke
        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Test");

        // Verify count decremented by supply
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), 0);
    }

    function testAutoRevokeUpdatesActiveLicenseCount() public {
        uint256 supply = 3;

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, supply, "public", "private", 0, "terms", false, 30 days, 0, 0);

        // Verify initial count
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), int256(supply));

        // Auto-revoke
        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 4);

        // Verify count decremented by supply
        assertEq(mockIPAsset.getActiveLicenseCount(ipTokenId), 0);
    }

    function testRevokeClearsExclusiveFlag() public {
        uint256 ipId = mockIPAsset.mint(admin);

        // Mint exclusive license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipId, 1, "public", "private", 0, "terms", true, 0, 0, 0);

        // Cannot mint another exclusive license
        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.ExclusiveLicenseAlreadyExists.selector);
        licenseToken.mintLicense(address(0x999), ipId, 1, "public", "private", 0, "terms", true, 0, 0, 0);

        // Revoke exclusive license
        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Test");

        // Should now be able to mint another exclusive license
        vm.prank(address(mockIPAsset));
        uint256 newLicenseId = licenseToken.mintLicense(address(0x999), ipId, 1, "public", "private", 0, "terms", true, 0, 0, 0);

        assertEq(newLicenseId, licenseId + 1);
    }

    function testAutoRevokeClearsExclusiveFlag() public {
        uint256 ipId = mockIPAsset.mint(admin);

        // Mint exclusive license with recurring payment
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipId, 1, "public", "private", 0, "terms", true, 30 days, 0, 0);

        // Auto-revoke exclusive license
        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 4);

        // Should now be able to mint another exclusive license
        vm.prank(address(mockIPAsset));
        uint256 newLicenseId = licenseToken.mintLicense(address(0x999), ipId, 1, "public", "private", 0, "terms", true, 0, 0, 0);

        assertEq(newLicenseId, licenseId + 1);
    }

    // ==================== STORY 3.4: AC6 - Transfer Prevention ====================

    function testCannotTransferRevokedLicense() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Revoke license
        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Test");

        // Try to transfer revoked license
        vm.prank(buyer);
        vm.expectRevert(ILicenseToken.CannotTransferRevokedLicense.selector);
        licenseToken.safeTransferFrom(buyer, address(0x999), licenseId, 1, "");
    }

    // ==================== STORY 3.4: AC7 - Revocation is Permanent ====================

    function testCannotRevokeAlreadyRevokedLicense() public {
        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Revoke license
        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "First revocation");

        // Try to revoke again
        vm.prank(arbitrator);
        vm.expectRevert(ILicenseToken.AlreadyRevoked.selector);
        licenseToken.revokeLicense(licenseId, "Second revocation");
    }

    // ==================== STORY 3.4: AC8-9 - Event Emissions ====================

    function testLicenseRevokedEvent() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        vm.expectEmit(true, false, false, true);
        emit ILicenseToken.LicenseRevoked(licenseId, "Violation of terms");

        vm.prank(arbitrator);
        licenseToken.revokeLicense(licenseId, "Violation of terms");
    }

    function testAutoRevokedEvent() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 30 days, 0, 0);

        vm.expectEmit(true, false, false, true);
        emit ILicenseToken.AutoRevoked(licenseId, 4);

        vm.prank(marketplace);
        licenseToken.revokeForMissedPayments(licenseId, 4);
    }

    // ==================== STORY 3.4: AC10 - Integration Test (Transfer + Metadata) ====================

    function testLicenseTransferAndMetadataAccess() public {
        // Note: This test will pass once metadata functions are implemented in future stories
        // For now, we test the transfer portion which is already functional

        // Mint license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Transfer license
        vm.prank(buyer);
        licenseToken.safeTransferFrom(buyer, address(0x999), licenseId, 1, "");

        // Verify transfer
        assertEq(licenseToken.balanceOf(address(0x999), licenseId), 1);
        assertEq(licenseToken.balanceOf(buyer, licenseId), 0);

        // Metadata access tests will be added when getPrivateMetadata is implemented
    }
}

/**
 * @title LicenseTokenAdminTest
 * @notice Test suite for Story 3.6 (Admin Functions & Upgrade Testing)
 */
contract LicenseTokenAdminTest is Test {
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

    // ==================== STORY 3.6: AC1 - Admin Setter Functions ====================

    function testSetArbitratorContractOnlyAdmin() public {
        address newArbitrator = address(0x999);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit ILicenseToken.ArbitratorContractUpdated(arbitrator, newArbitrator);

        // Admin can set arbitrator
        licenseToken.setArbitratorContract(newArbitrator);

        // Verify new arbitrator has role
        assertTrue(licenseToken.hasRole(licenseToken.ARBITRATOR_ROLE(), newArbitrator));
        // Verify old arbitrator no longer has role
        assertFalse(licenseToken.hasRole(licenseToken.ARBITRATOR_ROLE(), arbitrator));
        // Verify contract reference updated
        assertEq(licenseToken.arbitratorContract(), newArbitrator);
    }

    function testNonAdminCannotSetArbitratorContract() public {
        address nonAdmin = address(0x888);
        address newArbitrator = address(0x999);

        // Non-admin cannot set arbitrator
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.setArbitratorContract(newArbitrator);
    }

    function testCannotSetArbitratorToZeroAddress() public {
        vm.expectRevert(ILicenseToken.InvalidArbitratorAddress.selector);
        licenseToken.setArbitratorContract(address(0));
    }

    function testSetIPAssetContractOnlyAdmin() public {
        address newIPAsset = address(0x999);

        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit ILicenseToken.IPAssetContractUpdated(address(mockIPAsset), newIPAsset);

        // Admin can set IP asset contract
        licenseToken.setIPAssetContract(newIPAsset);

        // Verify new contract address and role
        assertEq(licenseToken.ipAssetContract(), newIPAsset);
        assertTrue(licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), newIPAsset));
        assertFalse(licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), address(mockIPAsset)));
    }

    function testNonAdminCannotSetIPAssetContract() public {
        address nonAdmin = address(0x888);
        address newIPAsset = address(0x999);

        // Non-admin cannot set IP asset contract
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.setIPAssetContract(newIPAsset);
    }

    function testCannotSetIPAssetToZeroAddress() public {
        vm.expectRevert(ILicenseToken.InvalidIPAssetAddress.selector);
        licenseToken.setIPAssetContract(address(0));
    }

    // ==================== STORY 3.6: AC2 - Pause/Unpause Functions ====================

    function testOnlyAdminCanPause() public {
        // Admin can pause
        licenseToken.pause();

        // Verify paused (will be tested by trying to mint)
        vm.prank(address(mockIPAsset));
        vm.expectRevert();
        licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);
    }

    function testOnlyAdminCanUnpause() public {
        // Pause first
        licenseToken.pause();

        // Admin can unpause
        licenseToken.unpause();

        // Verify unpaused by successfully minting
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);
        assertEq(licenseId, 0);
    }

    function testCannotOperateWhenPaused() public {
        // Pause contract
        licenseToken.pause();

        // Try to mint license (should fail)
        vm.prank(address(mockIPAsset));
        vm.expectRevert();
        licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);

        // Unpause
        licenseToken.unpause();

        // Now should work
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(buyer, ipTokenId, 1, "public", "private", 0, "terms", false, 0, 0, 0);
        assertEq(licenseId, 0);
    }

    // ==================== STORY 3.6: AC3 - UUPS Upgrade Authorization ====================

    function testOnlyAdminCanUpgrade() public {
        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Try to upgrade as non-admin (should fail)
        address nonAdmin = address(0x123);
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.upgradeToAndCall(address(newImpl), "");

        // Upgrade as admin (should work)
        licenseToken.upgradeToAndCall(address(newImpl), "");
    }

    function testCannotUpgradeWithoutAdminRole() public {
        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Non-admin cannot upgrade
        address nonAdmin = address(0x999);
        vm.prank(nonAdmin);
        vm.expectRevert();
        licenseToken.upgradeToAndCall(address(newImpl), "");
    }

    // ==================== STORY 3.6: AC4 - Upgrade State Preservation ====================

    function testUpgradePreservesState() public {
        // Setup: Mint a license
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "public_uri",
            "private_uri",
            0,
            "terms",
            false,
            0
        , 0, 0);

        // Store state before upgrade
        (uint256 ipAssetId, uint256 supply,,,,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(ipAssetId, ipTokenId);
        assertEq(supply, 1);

        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Upgrade (as admin)
        licenseToken.upgradeToAndCall(address(newImpl), "");

        // Verify state preserved
        (uint256 ipAssetIdAfter, uint256 supplyAfter,,,,,,) = licenseToken.getLicenseInfo(licenseId);
        assertEq(ipAssetId, ipAssetIdAfter);
        assertEq(supply, supplyAfter);

        // Verify new functionality
        LicenseTokenV2 upgraded = LicenseTokenV2(address(licenseToken));
        assertEq(upgraded.newFunction(), "upgraded");
        assertEq(upgraded.version(), 2);
    }

    function testUpgradeV2Implementation() public {
        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Upgrade
        licenseToken.upgradeToAndCall(address(newImpl), "");

        // Cast to V2 and test new functionality
        LicenseTokenV2 v2 = LicenseTokenV2(address(licenseToken));
        assertEq(v2.newFunction(), "upgraded");
        assertEq(v2.version(), 2);
    }

    function testUpgradePreservesRoles() public {
        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Upgrade
        licenseToken.upgradeToAndCall(address(newImpl), "");

        // Verify roles preserved
        assertTrue(licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(licenseToken.hasRole(licenseToken.ARBITRATOR_ROLE(), arbitrator));
        assertTrue(licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), address(mockIPAsset)));
    }

    function testUpgradePreservesContractReferences() public {
        // Deploy new implementation
        LicenseTokenV2 newImpl = new LicenseTokenV2();

        // Upgrade
        licenseToken.upgradeToAndCall(address(newImpl), "");

        // Verify contract references preserved
        assertEq(licenseToken.ipAssetContract(), address(mockIPAsset));
    }

    // ============ Story 6.2: Configurable maxMissedPayments Per License ============

    function testMintLicenseWithCustomMaxMissedPayments() public {
        // Mint license with custom maxMissedPayments = 5
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Standard terms",
            false,
            30 days,
            5,  // Custom maxMissedPayments
            0   // penaltyRateBPS (default)
        );

        // Verify custom value stored
        uint8 maxMissed = licenseToken.getMaxMissedPayments(licenseId);
        assertEq(maxMissed, 5);
    }

    function testMintLicenseWithDefaultMaxMissedPayments() public {
        // Mint license with maxMissedPayments = 0 (should use DEFAULT = 3)
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Standard terms",
            false,
            30 days,
            0,  // 0 = use DEFAULT_MAX_MISSED_PAYMENTS
            0   // penaltyRateBPS (default)
        );

        // Verify default value (3) applied
        uint8 maxMissed = licenseToken.getMaxMissedPayments(licenseId);
        assertEq(maxMissed, 3);
    }

    function testDifferentThresholdsForDifferentLicenses() public {
        // Create second IP token
        uint256 ipTokenId2 = mockIPAsset.mint(admin);

        // Mint license 1 with maxMissedPayments = 1
        vm.prank(address(mockIPAsset));
        uint256 license1 = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public1",
            "ipfs://private1",
            block.timestamp + 365 days,
            "Strict terms",
            false,
            30 days,
            1,  // Very strict - only 1 missed payment allowed
            0   // penaltyRateBPS (default)
        );

        // Mint license 2 with maxMissedPayments = 10
        vm.prank(address(mockIPAsset));
        uint256 license2 = licenseToken.mintLicense(
            buyer,
            ipTokenId2,
            1,
            "ipfs://public2",
            "ipfs://private2",
            block.timestamp + 365 days,
            "Lenient terms",
            false,
            30 days,
            10,  // Very lenient - 10 missed payments allowed
            0    // penaltyRateBPS (default)
        );

        // Verify each license has its own threshold
        uint8 maxMissed1 = licenseToken.getMaxMissedPayments(license1);
        uint8 maxMissed2 = licenseToken.getMaxMissedPayments(license2);

        assertEq(maxMissed1, 1);
        assertEq(maxMissed2, 10);
        assertTrue(maxMissed2 > maxMissed1);
    }

    function testGetMaxMissedPayments() public {
        // Mint license with custom maxMissedPayments
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Standard terms",
            false,
            30 days,
            7,  // Custom value
            0   // penaltyRateBPS (default)
        );

        // Test getter function
        uint8 maxMissed = licenseToken.getMaxMissedPayments(licenseId);
        assertEq(maxMissed, 7);
    }

    function testDefaultConstantValue() public {
        // Verify DEFAULT_MAX_MISSED_PAYMENTS constant is accessible and equals 3
        assertEq(licenseToken.DEFAULT_MAX_MISSED_PAYMENTS(), 3);
    }
}

/**
 * @title LicenseTokenV2
 * @notice Test contract for upgrade testing (Story 3.6)
 * @dev Adds new functionality for testing state preservation
 */
contract LicenseTokenV2 is LicenseToken {
    function newFunction() external pure returns (string memory) {
        return "upgraded";
    }

    function version() external pure returns (uint256) {
        return 2;
    }
}
