// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/Marketplace.sol";
import "../../src/IPAsset.sol";

/**
 * @title CreateListing
 * @notice Create a marketplace listing for an IP Asset
 * Usage: forge script script/actions/CreateListing.s.sol:CreateListing --rpc-url <rpc> --broadcast
 */
contract CreateListing is Script {
    // CONFIGURATION
    address constant MARKETPLACE_PROXY = 0x010DD42eB4979492df0bE9E6659ACaBA25F93B15;
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    uint256 constant TOKEN_ID = 1;
    uint256 constant PRICE = 1 ether;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        Marketplace marketplace = Marketplace(MARKETPLACE_PROXY);
        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        console.log("=== Create Marketplace Listing ===");
        console.log("Marketplace Proxy:", MARKETPLACE_PROXY);
        console.log("IPAsset:", IPASSET_PROXY);
        console.log("Token ID:", TOKEN_ID);
        console.log("Price:", PRICE);
        console.log("");

        // Approve marketplace
        vm.startBroadcast(deployerPrivateKey);
        ipAsset.approve(MARKETPLACE_PROXY, TOKEN_ID);

        // Create listing
        bytes32 listingId = marketplace.createListing(
            IPASSET_PROXY,
            TOKEN_ID,
            PRICE,
            true // isERC721
        );
        vm.stopBroadcast();

        console.log("SUCCESS!");
        console.log("Listing ID:", vm.toString(abi.encodePacked(listingId)));
    }
}
