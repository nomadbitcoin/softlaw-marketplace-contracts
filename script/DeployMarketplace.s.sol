// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Marketplace.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMarketplace is Script {
    function run() external returns (address proxy, address implementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Marketplace...");
        console.log("Deployer:", deployer);

        // Get required address
        address revenueDistributorAddress = vm.envOr("REVENUE_DISTRIBUTOR_ADDRESS", address(0));
        require(revenueDistributorAddress != address(0), "Set REVENUE_DISTRIBUTOR_ADDRESS in .env");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        Marketplace marketplaceImpl = new Marketplace();
        implementation = address(marketplaceImpl);
        console.log("Implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            Marketplace.initialize.selector,
            deployer,
            revenueDistributorAddress
        );

        ERC1967Proxy marketplaceProxy = new ERC1967Proxy(implementation, initData);
        proxy = address(marketplaceProxy);
        console.log("Proxy:", proxy);

        vm.stopBroadcast();

        console.log("\nMarketplace deployed!");
        console.log("Use proxy address:", proxy);
    }
}
