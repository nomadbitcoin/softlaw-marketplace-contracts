// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/IPAsset.sol";
import "../src/LicenseToken.sol";
import "../src/RevenueDistributor.sol";
import "../src/GovernanceArbitrator.sol";
import "../src/Marketplace.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployProduction is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Production Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        // 1. Deploy IPAsset Implementation
        console.log("\n[1/13] Deploying IPAsset Implementation...");
        vm.startBroadcast(deployerPrivateKey);
        address ipAssetImpl = address(new IPAsset());
        console.log("  Address:", ipAssetImpl);
        vm.stopBroadcast();
        vm.sleep(3000);

        // 2. Deploy IPAsset Proxy
        console.log("\n[2/13] Deploying IPAsset Proxy...");
        IPAsset ipAsset;
        {
            bytes memory initData = abi.encodeWithSelector(
                IPAsset.initialize.selector,
                "IP Asset", "IPA", deployer, address(0), address(0)
            );
            vm.startBroadcast(deployerPrivateKey);
            ipAsset = IPAsset(address(new ERC1967Proxy(ipAssetImpl, initData)));
            console.log("  Proxy:", address(ipAsset));
            vm.stopBroadcast();
        }
        vm.sleep(3000);

        // 3. Deploy RevenueDistributor
        console.log("\n[3/13] Deploying RevenueDistributor...");
        vm.startBroadcast(deployerPrivateKey);
        RevenueDistributor revenueDistributor = new RevenueDistributor(
            deployer, // treasury
            250,      // 2.5% platform fee
            1000,     // 10% default royalty
            address(ipAsset)
        );
        console.log("  Address:", address(revenueDistributor));
        vm.stopBroadcast();
        vm.sleep(3000);

        // 4. Deploy LicenseToken Implementation
        console.log("\n[4/13] Deploying LicenseToken Implementation...");
        vm.startBroadcast(deployerPrivateKey);
        address licenseTokenImpl = address(new LicenseToken());
        console.log("  Address:", licenseTokenImpl);
        vm.stopBroadcast();
        vm.sleep(3000);

        // 5. Deploy LicenseToken Proxy
        console.log("\n[5/13] Deploying LicenseToken Proxy...");
        LicenseToken licenseToken;
        {
            bytes memory initData = abi.encodeWithSelector(
                LicenseToken.initialize.selector,
                "https://softlaw.io/metadata/",
                deployer,
                address(ipAsset),
                address(0),
                address(revenueDistributor)
            );
            vm.startBroadcast(deployerPrivateKey);
            licenseToken = LicenseToken(address(new ERC1967Proxy(licenseTokenImpl, initData)));
            console.log("  Proxy:", address(licenseToken));
            vm.stopBroadcast();
        }
        vm.sleep(3000);

        // 6. Deploy GovernanceArbitrator Implementation
        console.log("\n[6/13] Deploying GovernanceArbitrator Implementation...");
        vm.startBroadcast(deployerPrivateKey);
        address arbitratorImpl = address(new GovernanceArbitrator());
        console.log("  Address:", arbitratorImpl);
        vm.stopBroadcast();
        vm.sleep(3000);

        // 7. Deploy GovernanceArbitrator Proxy
        console.log("\n[7/13] Deploying GovernanceArbitrator Proxy...");
        GovernanceArbitrator arbitrator;
        {
            bytes memory initData = abi.encodeWithSelector(
                GovernanceArbitrator.initialize.selector,
                deployer,
                address(licenseToken),
                address(ipAsset),
                address(revenueDistributor)
            );
            vm.startBroadcast(deployerPrivateKey);
            arbitrator = GovernanceArbitrator(address(new ERC1967Proxy(arbitratorImpl, initData)));
            console.log("  Proxy:", address(arbitrator));
            vm.stopBroadcast();
        }
        vm.sleep(3000);

        // 8. Deploy Marketplace Implementation
        console.log("\n[8/13] Deploying Marketplace Implementation...");
        vm.startBroadcast(deployerPrivateKey);
        address marketplaceImpl = address(new Marketplace());
        console.log("  Address:", marketplaceImpl);
        vm.stopBroadcast();
        vm.sleep(3000);

        // 9. Deploy Marketplace Proxy
        console.log("\n[9/13] Deploying Marketplace Proxy...");
        Marketplace marketplace;
        {
            bytes memory initData = abi.encodeWithSelector(
                Marketplace.initialize.selector,
                deployer,
                address(revenueDistributor)
            );
            vm.startBroadcast(deployerPrivateKey);
            marketplace = Marketplace(address(new ERC1967Proxy(marketplaceImpl, initData)));
            console.log("  Proxy:", address(marketplace));
            vm.stopBroadcast();
        }
        vm.sleep(3000);

        // 10. Set LicenseToken in IPAsset
        console.log("\n[10/13] Setting LicenseToken in IPAsset...");
        vm.startBroadcast(deployerPrivateKey);
        ipAsset.setLicenseTokenContract(address(licenseToken));
        console.log("  Done");
        vm.stopBroadcast();
        vm.sleep(3000);

        // 11. Set Arbitrator in IPAsset
        console.log("\n[11/13] Setting Arbitrator in IPAsset...");
        vm.startBroadcast(deployerPrivateKey);
        ipAsset.setArbitratorContract(address(arbitrator));
        console.log("  Done");
        vm.stopBroadcast();
        vm.sleep(3000);

        // 12. Grant IP_ASSET_ROLE
        console.log("\n[12/13] Granting IP_ASSET_ROLE to IPAsset...");
        vm.startBroadcast(deployerPrivateKey);
        licenseToken.grantRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset));
        console.log("  Done");
        vm.stopBroadcast();
        vm.sleep(3000);

        // 13. Set Arbitrator in LicenseToken
        console.log("\n[13/13] Setting Arbitrator in LicenseToken...");
        vm.startBroadcast(deployerPrivateKey);
        licenseToken.setArbitratorContract(address(arbitrator));
        console.log("  Done");
        vm.stopBroadcast();

        // Print summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("\nIPAsset:");
        console.log("  Implementation:", ipAssetImpl);
        console.log("  Proxy:", address(ipAsset));
        console.log("\nRevenueDistributor:", address(revenueDistributor));
        console.log("\nLicenseToken:");
        console.log("  Implementation:", licenseTokenImpl);
        console.log("  Proxy:", address(licenseToken));
        console.log("\nGovernanceArbitrator:");
        console.log("  Implementation:", arbitratorImpl);
        console.log("  Proxy:", address(arbitrator));
        console.log("\nMarketplace:");
        console.log("  Implementation:", marketplaceImpl);
        console.log("  Proxy:", address(marketplace));

        console.log("\n=== VERIFICATION ===");
        console.log("Verifying IPAsset admin:", ipAsset.hasRole(ipAsset.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("Verifying LicenseToken admin:", licenseToken.hasRole(licenseToken.DEFAULT_ADMIN_ROLE(), deployer));
        console.log("Verifying IPAsset->LicenseToken:", ipAsset.licenseTokenContract() == address(licenseToken));
        console.log("Verifying IPAsset->Arbitrator:", ipAsset.arbitratorContract() == address(arbitrator));
        console.log("Verifying IP_ASSET_ROLE:", licenseToken.hasRole(licenseToken.IP_ASSET_ROLE(), address(ipAsset)));
        console.log("Verifying Marketplace->RevenueDistributor:", marketplace.revenueDistributor() == address(revenueDistributor));

        // Save addresses for reference
        string memory chainId = vm.toString(block.chainid);
        string memory addresses = string(abi.encodePacked(
            "# Deployment Addresses (Chain ID: ", chainId, ")\n\n",
            "IPAsset=", vm.toString(address(ipAsset)), "\n",
            "RevenueDistributor=", vm.toString(address(revenueDistributor)), "\n",
            "LicenseToken=", vm.toString(address(licenseToken)), "\n",
            "GovernanceArbitrator=", vm.toString(address(arbitrator)), "\n",
            "Marketplace=", vm.toString(address(marketplace)), "\n"
        ));
        string memory filename = string(abi.encodePacked("./deployments/", chainId, ".txt"));
        vm.writeFile(filename, addresses);
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("Addresses saved to:", filename);
    }
}
