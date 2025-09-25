// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockKYCRegistry.sol";

/// @title Deploy MockKYCRegistry to Hedera Testnet
contract DeployMockKYCScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYING MOCK KYC REGISTRY ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "HBAR");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockKYCRegistry
        MockKYCRegistry kycRegistry = new MockKYCRegistry();

        console.log("MockKYCRegistry deployed at:", address(kycRegistry));

        vm.stopBroadcast();

        // Verification info
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("MockKYCRegistry:", address(kycRegistry));
        console.log("Block number:", block.number);
        console.log("Transaction complete!");
    }
}