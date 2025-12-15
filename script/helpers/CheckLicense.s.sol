// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../../src/LicenseToken.sol";

/**
 * @title CheckLicense
 * @notice Check license details
 * Usage: forge script script/actions/CheckLicense.s.sol:CheckLicense --rpc-url <rpc> -vv
 */
contract CheckLicense is Script {
    // CONFIGURATION
    address constant LICENSE_TOKEN_PROXY = 0xb18355D6fccAF73502251dd3bd0fF7B6FaAE443E;
    uint256 constant LICENSE_ID = 1;
    address HOLDER_ADDRESS; // Will check deployer if not specified

    function run() external view {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        address holder = HOLDER_ADDRESS == address(0) ? deployer : HOLDER_ADDRESS;

        LicenseToken licenseToken = LicenseToken(LICENSE_TOKEN_PROXY);

        console.log("=== License Details ===");
        console.log("LicenseToken Proxy:", LICENSE_TOKEN_PROXY);
        console.log("License ID:", LICENSE_ID);
        console.log("");

        // Check balance
        uint256 balance = licenseToken.balanceOf(holder, LICENSE_ID);
        console.log("Balance of", holder);
        console.log("  Balance:", balance);
        console.log("");

        // Get license info
        (
            uint256 ipAssetId,
            uint256 supply,
            uint256 expiryTime,
            string memory terms,
            uint256 paymentInterval,
            bool isExclusive,
            bool isRevoked,
            bool isExpired
        ) = licenseToken.getLicenseInfo(LICENSE_ID);

        console.log("License Info:");
        console.log("  IP Asset ID:", ipAssetId);
        console.log("  Supply:", supply);
        console.log("  Expiry Time:", expiryTime);
        console.log("  Payment Interval:", paymentInterval);
        console.log("  Is Exclusive:", isExclusive);
        console.log("  Is Revoked:", isRevoked);
        console.log("  Is Expired:", isExpired);
        console.log("  Terms:", terms);
        console.log("");

        console.log("Status:");
        console.log("  Is Active:", licenseToken.isActiveLicense(LICENSE_ID));
    }
}
