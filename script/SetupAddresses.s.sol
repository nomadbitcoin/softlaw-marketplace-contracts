// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";

contract SetupAddresses is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("Setting up contract addresses and roles...");

        // Get all contract addresses from environment
        address ipAssetAddress = vm.envOr("IPASSET_ADDRESS", address(0));
        address licenseTokenAddress = vm.envOr("LICENSE_TOKEN_ADDRESS", address(0));
        address arbitratorAddress = vm.envOr("ARBITRATOR_ADDRESS", address(0));

        require(ipAssetAddress != address(0), "Set IPASSET_ADDRESS in .env");
        require(licenseTokenAddress != address(0), "Set LICENSE_TOKEN_ADDRESS in .env");
        require(arbitratorAddress != address(0), "Set ARBITRATOR_ADDRESS in .env");

        IPAsset ipAsset = IPAsset(ipAssetAddress);
        LicenseToken licenseToken = LicenseToken(licenseTokenAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Set LicenseToken address in IPAsset
        console.log("\n[1/4] Setting LicenseToken in IPAsset...");
        ipAsset.setLicenseTokenContract(licenseTokenAddress);
        console.log("Done");

        // 2. Set Arbitrator in IPAsset
        console.log("\n[2/4] Setting Arbitrator in IPAsset...");
        ipAsset.setArbitratorContract(arbitratorAddress);
        console.log("Done");

        // 3. Grant IP_ASSET_ROLE to IPAsset in LicenseToken
        console.log("\n[3/4] Granting IP_ASSET_ROLE to IPAsset...");
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), ipAssetAddress);
        console.log("Done");

        // 4. Set Arbitrator in LicenseToken
        console.log("\n[4/4] Setting Arbitrator in LicenseToken...");
        licenseToken.setArbitratorContract(arbitratorAddress);
        console.log("Done");

        vm.stopBroadcast();

        // Verify setup
        console.log("\n=== VERIFICATION ===");
        console.log("IPAsset->LicenseToken:", ipAsset.licenseTokenContract() == licenseTokenAddress);
        console.log("IPAsset->Arbitrator:", ipAsset.arbitratorContract() == arbitratorAddress);
        console.log("LicenseToken has IP_ASSET_ROLE:", licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), ipAssetAddress));
        console.log("LicenseToken->Arbitrator:", licenseToken.arbitratorContract() == arbitratorAddress);

        console.log("\n[SUCCESS] Setup complete!");
    }
}
