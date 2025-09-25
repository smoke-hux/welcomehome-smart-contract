// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PropertyGovernance} from "../src/PropertyGovernance.sol";

contract DeployGovernanceScript is Script {
    PropertyGovernance public governance;

    function run() external returns (address) {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Get factory address from environment or use deployed address
        address factoryAddress = vm.envOr("FACTORY_ADDRESS", address(0x710d1E7F345CA3D893511743A00De2cFC1eAb6De));

        require(factoryAddress != address(0), "Factory address not set");

        console.log("=== Deploying PropertyGovernance ===");
        console.log("Deployer address:", deployerAddress);
        console.log("Factory address:", factoryAddress);
        console.log("Deployer balance:", deployerAddress.balance / 1e18, "HBAR");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy PropertyGovernance with factory address
        governance = new PropertyGovernance(factoryAddress);

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("PropertyGovernance deployed to:", address(governance));
        console.log("Connected to PropertyFactory:", factoryAddress);
        console.log("Deployment completed successfully!");

        return address(governance);
    }
}