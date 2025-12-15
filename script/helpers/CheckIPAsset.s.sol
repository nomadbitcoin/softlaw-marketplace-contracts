// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/IPAsset.sol";

/**
 * @title CheckIPAsset
 * @notice Check IP Asset details
 * Usage: forge script script/actions/CheckIPAsset.s.sol:CheckIPAsset --rpc-url <rpc> -vv
 */
contract CheckIPAsset is Script {
    // CONFIGURATION
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    uint256 constant TOKEN_ID = 1;

    function run() external view {
        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        console.log("=== IP Asset Details ===");
        console.log("IPAsset Proxy:", IPASSET_PROXY);
        console.log("Token ID:", TOKEN_ID);
        console.log("");

        console.log("Owner:", ipAsset.ownerOf(TOKEN_ID));
        console.log("Metadata URI:", ipAsset.tokenURI(TOKEN_ID));
        console.log("Active License Count:", ipAsset.activeLicenseCount(TOKEN_ID));
        console.log("Has Active Dispute:", ipAsset.hasActiveDispute(TOKEN_ID));
        console.log("License Token Contract:", ipAsset.licenseTokenContract());
        console.log("Arbitrator Contract:", ipAsset.arbitratorContract());
    }
}
