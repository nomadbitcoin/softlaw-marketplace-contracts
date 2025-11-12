// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/RevenueDistributor.sol";

contract DeploySimple is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying RevenueDistributor...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        RevenueDistributor revenueDistributor = new RevenueDistributor(
            deployer, // treasury
            250,      // 2.5% platform fee
            1000,     // 10% default royalty
            address(0x1) // dummy ipAsset address
        );

        vm.stopBroadcast();

        console.log("RevenueDistributor deployed at:", address(revenueDistributor));
    }
}
