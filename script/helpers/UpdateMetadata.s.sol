// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/IPAsset.sol";

/**
 * @title UpdateMetadata
 * @notice Update IP Asset metadata URI
 * Usage: forge script script/actions/UpdateMetadata.s.sol:UpdateMetadata --rpc-url <rpc> --broadcast
 */
contract UpdateMetadata is Script {
    // CONFIGURATION
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    uint256 constant TOKEN_ID = 1;
    string constant NEW_METADATA_URI = "ipfs://QmNewMetadataHash";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        console.log("=== Update Metadata ===");
        console.log("IPAsset Proxy:", IPASSET_PROXY);
        console.log("Token ID:", TOKEN_ID);
        console.log("Old URI:", ipAsset.tokenURI(TOKEN_ID));
        console.log("New URI:", NEW_METADATA_URI);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        ipAsset.updateMetadata(TOKEN_ID, NEW_METADATA_URI);
        vm.stopBroadcast();

        console.log("SUCCESS!");
        console.log("Updated URI:", ipAsset.tokenURI(TOKEN_ID));
    }
}
