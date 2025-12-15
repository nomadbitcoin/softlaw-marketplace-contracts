// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/RevenueDistributor.sol";

contract DeployRevenueDistributor is Script {
    function run() external returns (address distributor) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying RevenueDistributor...");
        console.log("Deployer:", deployer);

        // Get IPAsset address from environment or prompt
        address ipAssetAddress = vm.envOr("IPASSET_ADDRESS", address(0));
        require(ipAssetAddress != address(0), "Set IPASSET_ADDRESS in .env");

        vm.startBroadcast(deployerPrivateKey);

        RevenueDistributor revenueDistributor = new RevenueDistributor(
            deployer, // treasury
            250,      // 2.5% platform fee
            1000,     // 10% default royalty
            ipAssetAddress
        );
        distributor = address(revenueDistributor);

        console.log("RevenueDistributor:", distributor);

        vm.stopBroadcast();

        console.log("\nRevenueDistributor deployed!");
    }
}
