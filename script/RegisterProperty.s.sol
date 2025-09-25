// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MinimalPropertyFactory} from "../src/MinimalPropertyFactory.sol";

contract RegisterPropertyScript is Script {
    function run() external returns (uint256) {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        address payable factoryAddress = payable(vm.envOr("FACTORY_ADDRESS", address(0x710d1E7F345CA3D893511743A00De2cFC1eAb6De)));
        address tokenContract = vm.envOr("TOKEN_CONTRACT", address(0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7));
        address handlerContract = vm.envOr("HANDLER_CONTRACT", address(0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7)); // Using token as handler for demo

        require(factoryAddress != address(0), "Factory address not set");
        require(tokenContract != address(0), "Token contract address not set");

        console.log("=== Registering Property ===");
        console.log("Factory address:", factoryAddress);
        console.log("Token contract:", tokenContract);
        console.log("Handler contract:", handlerContract);
        console.log("Registration fee: 1 HBAR");

        MinimalPropertyFactory factory = MinimalPropertyFactory(factoryAddress);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Register the property (requires 1 HBAR fee)
        uint256 propertyId = factory.registerProperty{value: 1 ether}(
            tokenContract,
            handlerContract,
            "Welcome Home Test Property",
            "WHTP",
            "QmTestHash123456789", // IPFS hash placeholder
            1000000 ether, // Total value: 1M HBAR
            100000 ether,  // Max tokens: 100k tokens
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "123 Test Street, Test City"
        );

        // Stop broadcasting
        vm.stopBroadcast();

        console.log("Property registered with ID:", propertyId);
        console.log("Registration completed successfully!");

        return propertyId;
    }
}