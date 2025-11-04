// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployIPAsset is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        console.log("\n=== Deploying IPAsset Implementation ===");
        IPAsset implementation = new IPAsset();
        console.log("Implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset", // name
            "IPA", // symbol
            deployer, // admin
            address(0), // licenseToken (to be set later)
            address(0) // arbitrator (to be set later)
        );

        // Deploy proxy
        console.log("\n=== Deploying ERC1967 Proxy ===");
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        console.log("\n=== Deployment Summary ===");
        console.log("IPAsset Implementation:", address(implementation));
        console.log("IPAsset Proxy (use this):", address(proxy));
        console.log("Admin:", deployer);

        vm.stopBroadcast();

        // Verify initialization
        IPAsset ipAsset = IPAsset(address(proxy));
        console.log("\n=== Verification ===");
        console.log("Has PAUSER_ROLE:", ipAsset.hasRole(ipAsset.PAUSER_ROLE(), deployer));
        console.log("Has UPGRADER_ROLE:", ipAsset.hasRole(ipAsset.UPGRADER_ROLE(), deployer));
        console.log("Has DEFAULT_ADMIN_ROLE:", ipAsset.hasRole(ipAsset.DEFAULT_ADMIN_ROLE(), deployer));
    }
}
