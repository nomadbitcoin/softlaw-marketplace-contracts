// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LicenseToken.sol";
import "../src/interfaces/ILicenseToken.sol";
import "../src/Marketplace.sol";
import "../src/interfaces/IMarketplace.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title LicenseTokenPenaltyRateTest
 * @notice Test suite for Story 6.5 - Configurable Penalty Rate Per License
 * @dev Tests penalty rate constants, struct storage, validation, and penalty calculations
 */
contract LicenseTokenPenaltyRateTest is Test {
    LicenseToken public licenseToken;
    Marketplace public marketplace;
    MockIPAsset public mockIPAsset;
    MockRevenueDistributor public mockRevenueDistributor;

    address public admin;
    address public buyer;
    address public arbitrator;
    uint256 public ipTokenId;

    function setUp() public {
        admin = address(this);
        buyer = address(0x123);
        arbitrator = address(0x456);

        // Deploy mock contracts
        mockIPAsset = new MockIPAsset();
        mockRevenueDistributor = new MockRevenueDistributor();
        ipTokenId = mockIPAsset.mint(admin);

        // Deploy LicenseToken implementation and proxy
        LicenseToken licenseTokenImpl = new LicenseToken();
        bytes memory licenseInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://metadata.uri/",
            admin,
            address(mockIPAsset),
            arbitrator,
            address(mockRevenueDistributor)
        );
        ERC1967Proxy licenseProxy = new ERC1967Proxy(address(licenseTokenImpl), licenseInitData);
        licenseToken = LicenseToken(address(licenseProxy));

        // Deploy Marketplace implementation and proxy
        Marketplace marketplaceImpl = new Marketplace();
        bytes memory marketplaceInitData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            admin,
            address(mockRevenueDistributor)
        );
        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(address(marketplaceImpl), marketplaceInitData);
        marketplace = Marketplace(payable(address(marketplaceProxy)));

        // Grant roles
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(mockIPAsset));
        licenseToken.grantRole(licenseToken.MARKETPLACE_ROLE(), address(marketplace));
    }

    // ==================== STORY 6.5: AC3,5 - Penalty Rate Constants ====================

    function testDefaultPenaltyRateConstant() public {
        // Verify DEFAULT_PENALTY_RATE = 500 (5% per month)
        // Constants are checked via validation when minting with 0
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 0
        );
        // If 0 is passed, DEFAULT_PENALTY_RATE (500) should be applied
        assertEq(licenseToken.getPenaltyRate(licenseId), 500);
    }

    function testMaxPenaltyRateConstant() public {
        // Verify MAX_PENALTY_RATE = 5000 (50% per month)
        // Test that 5000 is accepted but 5001 is rejected
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 5000
        );
        assertEq(licenseToken.getPenaltyRate(licenseId), 5000);

        // Verify 5001 is rejected (proves max is 5000)
        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.InvalidPenaltyRate.selector);
        licenseToken.mintLicense(
            buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 5001
        );
    }

    // ==================== STORY 6.5: AC1,2 - Penalty Rate Storage ====================

    function testMintLicenseWithCustomPenaltyRate() public {
        // AC1: Add penaltyRate parameter to license minting
        // AC2: Store penalty rate per license token

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
            3,      // maxMissedPayments
            1000    // penaltyRateBPS = 10% per month (Story 6.5)
        );

        // Verify penalty rate was stored
        uint16 retrievedRate = licenseToken.getPenaltyRate(licenseId);
        assertEq(retrievedRate, 1000);
    }

    function testMintLicenseWithDefaultPenaltyRate() public {
        // AC3: Default penalty rate if not specified (500 = 5% per month)

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
            3,
            0       // penaltyRateBPS = 0 should default to 500
        );

        // Verify default penalty rate (500 bps = 5% per month)
        uint16 retrievedRate = licenseToken.getPenaltyRate(licenseId);
        assertEq(retrievedRate, 500);
    }

    function testGetPenaltyRateReturnsCorrectValue() public {
        // Test getter function

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
            3,
            2500    // 25% per month penalty rate
        );

        assertEq(licenseToken.getPenaltyRate(licenseId), 2500);
    }

    // ==================== STORY 6.5: AC5 - Penalty Rate Validation ====================

    function testPenaltyRateAtMaximumIsValid() public {
        // AC5: Validate penalty rate <= MAX_PENALTY_RATE (5000 = 50%)

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
            3,
            5000    // MAX_PENALTY_RATE (50% per month)
        );

        assertEq(licenseToken.getPenaltyRate(licenseId), 5000);
    }

    function testPenaltyRateExceedsMaxReverts() public {
        // AC5: Validate penalty rate <= MAX_PENALTY_RATE

        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.InvalidPenaltyRate.selector);
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Standard terms",
            false,
            30 days,
            3,
            5001    // Exceeds MAX_PENALTY_RATE (5000)
        );
    }

    function testPenaltyRateVeryHighReverts() public {
        vm.prank(address(mockIPAsset));
        vm.expectRevert(ILicenseToken.InvalidPenaltyRate.selector);
        licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            block.timestamp + 365 days,
            "Standard terms",
            false,
            30 days,
            3,
            10000   // 100% per month - too high
        );
    }

    // ==================== STORY 6.5: AC4 - Penalty Calculation with Per-License Rate ====================

    function testPenaltyCalculationWithDifferentRates() public {
        // AC4: Modify penalty calculation to use per-license rate

        // Mint license 1 with 5% penalty rate (500 bps)
        vm.prank(address(mockIPAsset));
        uint256 license1 = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public1",
            "ipfs://private1",
            0,  // Perpetual
            "Standard terms",
            false,
            30 days,    // Recurring payment
            3,
            500         // 5% per month penalty
        );

        // Mint license 2 with 10% penalty rate (1000 bps)
        vm.prank(address(mockIPAsset));
        uint256 license2 = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public2",
            "ipfs://private2",
            0,  // Perpetual
            "Standard terms",
            false,
            30 days,    // Recurring payment
            3,
            1000        // 10% per month penalty
        );

        // Note: Actual penalty calculation testing requires Marketplace integration
        // which is tested separately in Marketplace tests

        // Verify different rates stored
        assertEq(licenseToken.getPenaltyRate(license1), 500);
        assertEq(licenseToken.getPenaltyRate(license2), 1000);
    }

    // ==================== STORY 6.5: AC6 - Backward Compatibility ====================

    function testBackwardCompatibilityWithDefaultRate() public {
        // AC6: Backward compatible - passing 0 uses default

        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "Standard terms",
            false,
            0,
            0,  // maxMissedPayments = 0 -> defaults to 3
            0   // penaltyRateBPS = 0 -> defaults to 500
        );

        // Verify defaults applied
        assertEq(licenseToken.getMaxMissedPayments(licenseId), 3);
        assertEq(licenseToken.getPenaltyRate(licenseId), 500);
    }

    // ==================== Additional Edge Cases ====================

    function testMultipleLicensesWithDifferentPenaltyRates() public {
        vm.startPrank(address(mockIPAsset));

        // Create licenses with various penalty rates
        uint256 id1 = licenseToken.mintLicense(buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 100);
        uint256 id2 = licenseToken.mintLicense(buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 500);
        uint256 id3 = licenseToken.mintLicense(buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 1000);
        uint256 id4 = licenseToken.mintLicense(buyer, ipTokenId, 1, "pub", "priv", 0, "terms", false, 0, 3, 5000);

        vm.stopPrank();

        // Verify each has correct rate
        assertEq(licenseToken.getPenaltyRate(id1), 100);
        assertEq(licenseToken.getPenaltyRate(id2), 500);
        assertEq(licenseToken.getPenaltyRate(id3), 1000);
        assertEq(licenseToken.getPenaltyRate(id4), 5000);
    }

    function testPenaltyRateImmutableAfterMinting() public {
        vm.prank(address(mockIPAsset));
        uint256 licenseId = licenseToken.mintLicense(
            buyer,
            ipTokenId,
            1,
            "ipfs://public",
            "ipfs://private",
            0,
            "Standard terms",
            false,
            30 days,
            3,
            1500    // 15% per month
        );

        // Verify penalty rate
        uint16 initialRate = licenseToken.getPenaltyRate(licenseId);
        assertEq(initialRate, 1500);

        // No function exists to change penalty rate (immutable by design)
        // Verify it remains the same
        assertEq(licenseToken.getPenaltyRate(licenseId), 1500);
    }
}

/**
 * @title MockIPAsset
 * @notice Mock IPAsset contract for testing
 */
contract MockIPAsset {
    uint256 private _counter;
    mapping(uint256 => address) private _owners;
    mapping(uint256 => uint256) public activeLicenseCount;
    mapping(uint256 => bool) public hasActiveDispute;

    function mint(address to) external returns (uint256) {
        uint256 tokenId = _counter++;
        _owners[tokenId] = to;
        return tokenId;
    }

    function updateActiveLicenseCount(uint256 ipAssetId, int256 delta) external {
        if (delta > 0) {
            activeLicenseCount[ipAssetId] += uint256(delta);
        } else {
            activeLicenseCount[ipAssetId] -= uint256(-delta);
        }
    }
}

/**
 * @title MockRevenueDistributor
 * @notice Mock RevenueDistributor contract for testing
 */
contract MockRevenueDistributor {
    event PaymentReceived(uint256 ipAssetId, uint256 amount);

    function distributePayment(uint256 ipAssetId, uint256 amount) external payable {
        emit PaymentReceived(ipAssetId, amount);
    }

    receive() external payable {}
}
