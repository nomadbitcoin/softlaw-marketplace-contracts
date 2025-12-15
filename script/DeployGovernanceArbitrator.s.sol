// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/GovernanceArbitrator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployGovernanceArbitrator is Script {
    function run() external returns (address proxy, address implementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying GovernanceArbitrator...");
        console.log("Deployer:", deployer);

        // Get required addresses
        address ipAssetAddress = vm.envOr("IPASSET_ADDRESS", address(0));
        address licenseTokenAddress = vm.envOr("LICENSE_TOKEN_ADDRESS", address(0));
        address revenueDistributorAddress = vm.envOr("REVENUE_DISTRIBUTOR_ADDRESS", address(0));

        require(ipAssetAddress != address(0), "Set IPASSET_ADDRESS in .env");
        require(licenseTokenAddress != address(0), "Set LICENSE_TOKEN_ADDRESS in .env");
        require(revenueDistributorAddress != address(0), "Set REVENUE_DISTRIBUTOR_ADDRESS in .env");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();
        implementation = address(arbitratorImpl);
        console.log("Implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            deployer,
            licenseTokenAddress,
            ipAssetAddress,
            revenueDistributorAddress
        );

        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(implementation, initData);
        proxy = address(arbitratorProxy);
        console.log("Proxy:", proxy);

        vm.stopBroadcast();

        console.log("\nGovernanceArbitrator deployed!");
        console.log("Use proxy address:", proxy);
    }
}
