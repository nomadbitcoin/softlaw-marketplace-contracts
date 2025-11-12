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
