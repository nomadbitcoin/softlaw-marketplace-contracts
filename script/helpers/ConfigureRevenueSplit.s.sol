// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/IPAsset.sol";

/**
 * @title ConfigureRevenueSplit
 * @notice Configure revenue split for an IP Asset
 * Usage: forge script script/actions/ConfigureRevenueSplit.s.sol:ConfigureRevenueSplit --rpc-url <rpc> --broadcast
 */
contract ConfigureRevenueSplit is Script {
    // CONFIGURATION
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    uint256 constant TOKEN_ID = 1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        // Example: 70% to creator, 30% to collaborator
        address[] memory recipients = new address[](2);
        recipients[0] = deployer;
        recipients[1] = 0x0000000000000000000000000000000000000123; // Replace with actual address

        uint256[] memory shares = new uint256[](2);
        shares[0] = 7000; // 70%
        shares[1] = 3000; // 30%

        console.log("=== Configure Revenue Split ===");
        console.log("IPAsset Proxy:", IPASSET_PROXY);
        console.log("Token ID:", TOKEN_ID);
        console.log("Recipients:");
        for (uint256 i = 0; i < recipients.length; i++) {
            console.log("  ", recipients[i], "-", shares[i], "bps");
        }
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        ipAsset.configureRevenueSplit(TOKEN_ID, recipients, shares);
        vm.stopBroadcast();

        console.log("SUCCESS! Revenue split configured.");
    }
}
