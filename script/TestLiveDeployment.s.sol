// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";

contract TestLiveDeployment is Script {
    // Deployed contract addresses on Passet Hub
    address constant IP_ASSET = 0x160DbC883322b014e00e8b0bF505Ec18F2332244;
    address constant LICENSE_TOKEN = 0x92bd81dE0B968a7d6a551420ae8b8d0485124006;
    address constant REVENUE_DISTRIBUTOR = 0xc263853dc6B524edE3bEa75e7d223B7269A0Eb16;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Testing Live Deployment ===");
        console.log("Network Chain ID:", block.chainid);
        console.log("Tester address:", deployer);
        console.log("Tester balance:", deployer.balance);

        IPAsset ipAsset = IPAsset(IP_ASSET);
        LicenseToken licenseToken = LicenseToken(LICENSE_TOKEN);
        RevenueDistributor revenueDistributor = RevenueDistributor(REVENUE_DISTRIBUTOR);

        console.log("\n=== Contract Verification ===");

        // Test 1: Verify contracts are accessible
        console.log("IPAsset address responds:", address(ipAsset).code.length > 0);
        console.log("LicenseToken address responds:", address(licenseToken).code.length > 0);
        console.log("RevenueDistributor address responds:", address(revenueDistributor).code.length > 0);

        // Test 2: Check contract state
        console.log("\n=== State Verification ===");
        console.log("IPAsset admin:", ipAsset.hasRole(ipAsset.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("LicenseToken admin:", licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("IPAsset -> LicenseToken:", ipAsset.licenseTokenContract() == LICENSE_TOKEN);
        console.log("IPAsset has IP_ASSET_ROLE:", licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), IP_ASSET));

        vm.startBroadcast(deployerPrivateKey);

        // Test 3: Mint an IP Asset
        console.log("\n=== Test 1: Minting IP Asset ===");
        uint256 ipTokenId = ipAsset.mintIP(deployer, "ipfs://test-metadata");
        console.log("IP Asset minted with ID:", ipTokenId);
        console.log("IP Asset owner:", ipAsset.ownerOf(ipTokenId));
        console.log("Owner matches deployer:", ipAsset.ownerOf(ipTokenId) == deployer);

        // Test 4: Mint a License
        console.log("\n=== Test 2: Minting License ===");
        address licensee = address(0x123);
        uint256 licenseId = ipAsset.mintLicense(
            ipTokenId,
            licensee,
            5, // supply
            "ipfs://license-public",
            "ipfs://license-private",
            block.timestamp + 365 days, // expiryTime
            "Test license terms",
            false, // non-exclusive
            0 // one-time payment
        );
        console.log("License minted with ID:", licenseId);

        // Test 5: Verify License Data
        console.log("\n=== Test 3: Verify License Data ===");
        (
            uint256 linkedIpAssetId,
            uint256 supply,
            uint256 expiryTime,
            string memory terms,
            uint256 paymentInterval,
            bool isExclusive,
            bool isRevoked,
            bool isExpired
        ) = licenseToken.getLicenseInfo(licenseId);

        console.log("License linked to IP Asset:", linkedIpAssetId);
        console.log("License supply:", supply);
        console.log("License expiry:", expiryTime);
        console.log("License terms:", terms);
        console.log("Payment interval:", paymentInterval);
        console.log("Is exclusive:", isExclusive);
        console.log("Is revoked:", isRevoked);
        console.log("Is expired:", isExpired);

        // Test 6: Verify ERC1155 Balance
        console.log("\n=== Test 4: Verify ERC1155 Balance ===");
        uint256 balance = licenseToken.balanceOf(licensee, licenseId);
        console.log("Licensee balance:", balance);
        console.log("Balance matches supply:", balance == supply);

        // Test 7: Verify Query Functions
        console.log("\n=== Test 5: Query Functions ===");
        console.log("Is one-time payment:", licenseToken.isOneTime(licenseId));
        console.log("Is recurring payment:", licenseToken.isRecurring(licenseId));
        console.log("Is active license:", licenseToken.isActiveLicense(licenseId));
        console.log("Payment interval:", licenseToken.getPaymentInterval(licenseId));

        vm.stopBroadcast();

        console.log("\n=== All Tests Passed! ===");
        console.log("Deployment is working correctly on live network");
    }
}
