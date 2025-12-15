// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/LicenseToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLicenseToken is Script {
    function run() external returns (address proxy, address implementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying LicenseToken...");
        console.log("Deployer:", deployer);

        // Get required addresses
        address ipAssetAddress = vm.envOr("IPASSET_ADDRESS", address(0));
        address revenueDistributorAddress = vm.envOr("REVENUE_DISTRIBUTOR_ADDRESS", address(0));

        require(ipAssetAddress != address(0), "Set IPASSET_ADDRESS in .env");
        require(revenueDistributorAddress != address(0), "Set REVENUE_DISTRIBUTOR_ADDRESS in .env");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        LicenseToken licenseTokenImpl = new LicenseToken();
        implementation = address(licenseTokenImpl);
        console.log("Implementation:", implementation);

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://softlaw.io/metadata/",
            deployer,
            ipAssetAddress,
            address(0), // arbitrator - set later
            revenueDistributorAddress
        );

        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(implementation, initData);
        proxy = address(licenseTokenProxy);
        console.log("Proxy:", proxy);

        vm.stopBroadcast();

        console.log("\nLicenseToken deployed!");
        console.log("Use proxy address:", proxy);
    }
}
