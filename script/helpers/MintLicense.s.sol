// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/IPAsset.sol";

/**
 * @title MintLicense
 * @notice Mints a new license for an IP Asset
 * Usage: forge script script/actions/MintLicense.s.sol:MintLicense --rpc-url <rpc> --broadcast
 *
 * Configure:
 * - IPASSET_PROXY: Address of IPAsset proxy contract
 * - IP_TOKEN_ID: The IP Asset token ID to license
 * - LICENSEE: Address receiving the license
 * - SUPPLY: Number of licenses to mint
 */
contract MintLicense is Script {
    // CONFIGURATION - Update these values
    address constant IPASSET_PROXY = 0x75Fde35E066f0a89cECf0BfDeD22572Ba2aB25D3;
    uint256 constant IP_TOKEN_ID = 1;
    address LICENSEE; // Will be set to deployer if not specified
    uint256 constant SUPPLY = 1;
    string constant PUBLIC_METADATA = "ipfs://QmLicensePublicMetadata";
    string constant PRIVATE_METADATA = "Confidential license terms";
    uint256 constant EXPIRY_DAYS = 365;
    string constant TERMS = "Standard Commercial License";
    bool constant IS_EXCLUSIVE = false;
    uint256 constant PAYMENT_INTERVAL = 0; // 0 = one-time payment

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Use deployer as licensee if not specified
        address licensee = LICENSEE == address(0) ? deployer : LICENSEE;

        IPAsset ipAsset = IPAsset(IPASSET_PROXY);

        console.log("=== Mint License ===");
        console.log("IPAsset Proxy:", IPASSET_PROXY);
        console.log("IP Token ID:", IP_TOKEN_ID);
        console.log("Licensee:", licensee);
        console.log("Supply:", SUPPLY);
        console.log("Expiry Days:", EXPIRY_DAYS);
        console.log("");

        uint256 expiryTime = block.timestamp + (EXPIRY_DAYS * 1 days);

        vm.startBroadcast(deployerPrivateKey);
        uint256 licenseId = ipAsset.mintLicense(
            IP_TOKEN_ID,
            licensee,
            SUPPLY,
            PUBLIC_METADATA,
            PRIVATE_METADATA,
            expiryTime,
            TERMS,
            IS_EXCLUSIVE,
            PAYMENT_INTERVAL
        );
        vm.stopBroadcast();

        console.log("SUCCESS!");
        console.log("License ID:", licenseId);
    }
}
