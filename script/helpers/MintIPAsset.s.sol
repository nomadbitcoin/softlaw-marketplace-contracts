// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/IPAsset.sol";

/**
 * @title MintIPAsset
 * @notice Mints a new IP Asset
 * Usage: forge script script/actions/MintIPAsset.s.sol:MintIPAsset --rpc-url <rpc> --broadcast
 *
 * Configure:
 * - IPASSET_PROXY: Address of IPAsset proxy contract
 * - TO_ADDRESS: Address to mint to
 * - METADATA_URI: IPFS or HTTP URI for metadata
 */
contract MintIPAsset is Script {
    // CONFIGURATION - Update these values
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    address TO_ADDRESS; // Will be set to deployer if not specified
    string constant METADATA_URI = "ipfs://QmYourMetadataHash";

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Use deployer as recipient if TO_ADDRESS not set
        address recipient = TO_ADDRESS == address(0) ? deployer : TO_ADDRESS;

        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        console.log("=== Mint IP Asset ===");
        console.log("IPAsset Proxy:", IPASSET_PROXY);
        console.log("Recipient:", recipient);
        console.log("Metadata URI:", METADATA_URI);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        uint256 tokenId = ipAsset.mintIP(recipient, METADATA_URI);
        vm.stopBroadcast();

        console.log("SUCCESS!");
        console.log("Token ID:", tokenId);
        console.log("Owner:", ipAsset.ownerOf(tokenId));
        console.log("URI:", ipAsset.tokenURI(tokenId));
    }
}
