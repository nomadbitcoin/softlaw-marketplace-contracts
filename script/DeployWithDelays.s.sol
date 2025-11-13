// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/base/ERC1967Proxy.sol";

contract DeployWithDelays is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Starting Deployment with Delays ===");
        console.log("Deploying from:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Network:", block.chainid);

        // Deploy each contract separately with broadcasts to get individual tx hashes

        // 1. Deploy IPAsset Implementation
        console.log("\n=== Step 1: Deploy IPAsset Implementation ===");
        vm.startBroadcast(deployerPrivateKey);
        IPAsset ipAssetImpl = new IPAsset();
        console.log("IPAsset Implementation:", address(ipAssetImpl));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 2. Deploy IPAsset Proxy
        console.log("\n=== Step 2: Deploy IPAsset Proxy ===");
        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset",
            "IPA",
            deployer,
            address(0), // licenseToken - will be set later
            address(0)  // arbitrator - will be set later
        );
        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        IPAsset ipAsset = IPAsset(address(ipAssetProxy));
        console.log("IPAsset Proxy:", address(ipAsset));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 3. Deploy RevenueDistributor
        console.log("\n=== Step 3: Deploy RevenueDistributor ===");
        address treasury = deployer;
        uint256 platformFeeBasisPoints = 250; // 2.5%
        uint256 defaultRoyaltyBasisPoints = 1000; // 10%
        vm.startBroadcast(deployerPrivateKey);
        RevenueDistributor revenueDistributor = new RevenueDistributor(
            treasury,
            platformFeeBasisPoints,
            defaultRoyaltyBasisPoints,
            address(ipAsset)
        );
        console.log("RevenueDistributor:", address(revenueDistributor));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 4. Deploy LicenseToken Implementation
        console.log("\n=== Step 4: Deploy LicenseToken Implementation ===");
        vm.startBroadcast(deployerPrivateKey);
        LicenseToken licenseTokenImpl = new LicenseToken();
        console.log("LicenseToken Implementation:", address(licenseTokenImpl));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 5. Deploy LicenseToken Proxy
        console.log("\n=== Step 5: Deploy LicenseToken Proxy ===");
        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://metadata.uri/",
            deployer,
            address(ipAsset),
            address(0), // arbitrator - will be set later
            address(revenueDistributor)
        );
        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(address(licenseTokenImpl), licenseTokenInitData);
        LicenseToken licenseToken = LicenseToken(address(licenseTokenProxy));
        console.log("LicenseToken Proxy:", address(licenseToken));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 6. Deploy GovernanceArbitrator Implementation
        console.log("\n=== Step 6: Deploy GovernanceArbitrator Implementation ===");
        vm.startBroadcast(deployerPrivateKey);
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();
        console.log("GovernanceArbitrator Implementation:", address(arbitratorImpl));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 7. Deploy GovernanceArbitrator Proxy
        console.log("\n=== Step 7: Deploy GovernanceArbitrator Proxy ===");
        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            deployer,
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );
        vm.startBroadcast(deployerPrivateKey);
        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(address(arbitratorImpl), arbitratorInitData);
        GovernanceArbitrator arbitrator = GovernanceArbitrator(address(arbitratorProxy));
        console.log("GovernanceArbitrator Proxy:", address(arbitrator));
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 8. Set LicenseToken in IPAsset
        console.log("\n=== Step 8: Set LicenseToken in IPAsset ===");
        vm.startBroadcast(deployerPrivateKey);
        ipAsset.setLicenseTokenContract(address(licenseToken));
        console.log("LicenseToken reference set");
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 9. Set Arbitrator in IPAsset
        console.log("\n=== Step 9: Set Arbitrator in IPAsset ===");
        vm.startBroadcast(deployerPrivateKey);
        ipAsset.setArbitratorContract(address(arbitrator));
        console.log("Arbitrator reference set");
        vm.stopBroadcast();
        console.log("Waiting 5 seconds...");
        vm.sleep(5000);

        // 10. Grant IP_ASSET_ROLE
        console.log("\n=== Step 10: Grant IP_ASSET_ROLE to IPAsset ===");
        vm.startBroadcast(deployerPrivateKey);
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        console.log("IP_ASSET_ROLE granted");
        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("IPAsset Proxy:", address(ipAsset));
        console.log("LicenseToken Proxy:", address(licenseToken));
        console.log("RevenueDistributor:", address(revenueDistributor));
        console.log("GovernanceArbitrator Proxy:", address(arbitrator));
    }
}
