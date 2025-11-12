// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/base/ERC1967Proxy.sol";

contract DeployAll is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Starting Deployment ===");
        console.log("Deploying from:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Network:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy IPAsset first (RevenueDistributor needs its address)
        console.log("\n=== Deploying IPAsset ===");
        IPAsset ipAssetImpl = new IPAsset();
        console.log("IPAsset Implementation:", address(ipAssetImpl));

        bytes memory ipAssetInitData = abi.encodeWithSelector(
            IPAsset.initialize.selector,
            "IP Asset",
            "IPA",
            deployer,
            address(0), // licenseToken - will be set later
            address(0)  // arbitrator - will be set later
        );

        ERC1967Proxy ipAssetProxy = new ERC1967Proxy(address(ipAssetImpl), ipAssetInitData);
        IPAsset ipAsset = IPAsset(address(ipAssetProxy));
        console.log("IPAsset Proxy:", address(ipAsset));

        // 2. Deploy RevenueDistributor (needs IPAsset address)
        console.log("\n=== Deploying RevenueDistributor ===");
        address treasury = deployer;
        uint256 platformFeeBasisPoints = 250; // 2.5%
        uint256 defaultRoyaltyBasisPoints = 1000; // 10%

        RevenueDistributor revenueDistributor = new RevenueDistributor(
            treasury,
            platformFeeBasisPoints,
            defaultRoyaltyBasisPoints,
            address(ipAsset)
        );
        console.log("RevenueDistributor deployed at:", address(revenueDistributor));

        // 3. Deploy LicenseToken
        console.log("\n=== Deploying LicenseToken ===");
        LicenseToken licenseTokenImpl = new LicenseToken();
        console.log("LicenseToken Implementation:", address(licenseTokenImpl));

        bytes memory licenseTokenInitData = abi.encodeWithSelector(
            LicenseToken.initialize.selector,
            "https://metadata.uri/", // baseURI
            deployer,               // admin
            address(ipAsset),       // ipAsset
            address(0),             // arbitrator - will be set later
            address(revenueDistributor) // revenueDistributor
        );

        ERC1967Proxy licenseTokenProxy = new ERC1967Proxy(address(licenseTokenImpl), licenseTokenInitData);
        LicenseToken licenseToken = LicenseToken(address(licenseTokenProxy));
        console.log("LicenseToken Proxy:", address(licenseToken));

        // 4. Deploy GovernanceArbitrator
        console.log("\n=== Deploying GovernanceArbitrator ===");
        GovernanceArbitrator arbitratorImpl = new GovernanceArbitrator();
        console.log("GovernanceArbitrator Implementation:", address(arbitratorImpl));

        bytes memory arbitratorInitData = abi.encodeWithSelector(
            GovernanceArbitrator.initialize.selector,
            deployer, // admin
            address(licenseToken),
            address(ipAsset),
            address(revenueDistributor)
        );

        ERC1967Proxy arbitratorProxy = new ERC1967Proxy(address(arbitratorImpl), arbitratorInitData);
        GovernanceArbitrator arbitrator = GovernanceArbitrator(address(arbitratorProxy));
        console.log("GovernanceArbitrator Proxy:", address(arbitrator));

        // 5. Wire up contracts
        console.log("\n=== Wiring Up Contracts ===");

        // Set LicenseToken address in IPAsset
        ipAsset.setLicenseTokenContract(address(licenseToken));
        console.log("Set LicenseToken in IPAsset");

        // Set Arbitrator in IPAsset
        ipAsset.setArbitratorContract(address(arbitrator));
        console.log("Set Arbitrator in IPAsset");

        // Grant IP_ASSET_ROLE to IPAsset contract in LicenseToken
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        console.log("Granted IP_ASSET_ROLE to IPAsset in LicenseToken");

        vm.stopBroadcast();

        // 6. Verification
        console.log("\n=== Deployment Summary ===");
        console.log("RevenueDistributor:", address(revenueDistributor));
        console.log("IPAsset Proxy:", address(ipAsset));
        console.log("LicenseToken Proxy:", address(licenseToken));
        console.log("GovernanceArbitrator Proxy:", address(arbitrator));
        console.log("Admin:", deployer);
        console.log("Treasury:", treasury);

        console.log("\n=== Verification ===");
        console.log("IPAsset has admin:", ipAsset.hasRole(ipAsset.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("LicenseToken has admin:", licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("IPAsset has correct LicenseToken:", ipAsset.licenseTokenContract() == address(licenseToken));
        console.log("IPAsset has IP_ASSET_ROLE:", licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset)));

        console.log("\n=== Deployment Complete ===");
    }
}
