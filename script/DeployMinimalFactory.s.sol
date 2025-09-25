// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MinimalPropertyFactory} from "../src/MinimalPropertyFactory.sol";

contract DeployMinimalFactoryScript is Script {
    MinimalPropertyFactory public factory;

    function run() external returns (address) {
        // Load the private key from the .env file (Hedera best practice)
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("=== Deploying MinimalPropertyFactory ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Deployer balance:", deployerAddress.balance / 1e18, "HBAR");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MinimalPropertyFactory with deployer as fee collector
        factory = new MinimalPropertyFactory(deployerAddress);

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("MinimalPropertyFactory deployed to:", address(factory));
        console.log("Fee collector set to:", deployerAddress);
        console.log("Deployment completed successfully!");

        return address(factory);
    }
}