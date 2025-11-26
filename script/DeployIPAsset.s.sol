// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployIPAsset is Script {
    function run() external returns (address proxy, address implementation) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying IPAsset...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        IPAsset ipAssetImpl = new IPAsset();
        implementation = address(ipAssetImpl);
        console.log("Implementation:", implementation);

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset",
            "IPA",
            deployer,
            address(0), // licenseToken - set later
            address(0)  // arbitrator - set later
        );

        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(implementation, initData);
        proxy = address(ipAssetProxy);
        console.log("Proxy:", proxy);

        vm.stopBroadcast();

        console.log("\nIPAsset deployed!");
        console.log("Use proxy address:", proxy);
    }
}
