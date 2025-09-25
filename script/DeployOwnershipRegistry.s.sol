// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/OwnershipRegistry.sol";

/// @title Deploy OwnershipRegistry to Hedera Testnet
contract DeployOwnershipRegistryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOYING OWNERSHIP REGISTRY ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance / 1e18, "HBAR");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy OwnershipRegistry
        OwnershipRegistry ownershipRegistry = new OwnershipRegistry();

        console.log("OwnershipRegistry deployed at:", address(ownershipRegistry));

        vm.stopBroadcast();

        // Verification info
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("OwnershipRegistry:", address(ownershipRegistry));
        console.log("Block number:", block.number);
        console.log("Transaction complete!");
    }
}