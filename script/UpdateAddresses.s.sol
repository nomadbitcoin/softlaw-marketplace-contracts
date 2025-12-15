// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

/**
 * @title UpdateAddresses
 * @notice Helper script to display deployed addresses
 * @dev Copy these addresses into your action scripts
 *
 * Usage: forge script script/UpdateAddresses.s.sol:UpdateAddresses --rpc-url <rpc> -vv
 *
 * After deployment, manually update these addresses in:
 * - script/actions/*.s.sol files
 */
contract UpdateAddresses is Script {
    function run() external view {
        console.log("=== Deployed Contract Addresses ===");
        console.log("");
        console.log("UPDATE THESE IN YOUR ACTION SCRIPTS:");
        console.log("");

        // From latest TestLicenseComplete deployment
        console.log("IPAsset Proxy:");
        console.log("  address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;");
        console.log("");

        console.log("LicenseToken Proxy:");
        console.log("  address constant LICENSE_TOKEN_PROXY = 0xb18355D6fccAF73502251dd3bd0fF7B6FaAE443E;");
        console.log("");

        console.log("RevenueDistributor:");
        console.log("  address constant REVENUE_DISTRIBUTOR = 0x5F8F945DC714bb858F22198758c29296182ee121;");
        console.log("");

        console.log("Marketplace Proxy:");
        console.log("  address constant MARKETPLACE_PROXY = 0x010DD42eB4979492df0bE9E6659ACaBA25F93B15;");
        console.log("");

        console.log("GovernanceArbitrator Proxy:");
        console.log("  address constant ARBITRATOR_PROXY = 0xF2C42ADB8c453fB95f1f9e073F7c531997D584E6;");
        console.log("");

        console.log("=====================================");
        console.log("");
        console.log("After running DeployProduction.s.sol:");
        console.log("1. Note the deployed addresses from the output");
        console.log("2. Update this script with new addresses");
        console.log("3. Run this script to see formatted addresses");
        console.log("4. Copy/paste into action scripts");
    }
}
