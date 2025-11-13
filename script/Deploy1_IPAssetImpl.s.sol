// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";

contract Deploy1_IPAssetImpl is Script {
    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        IPAsset implementation = new IPAsset();
        vm.stopBroadcast();

        console.log("IPAsset Implementation deployed at:", address(implementation));
        return address(implementation);
    }
}
