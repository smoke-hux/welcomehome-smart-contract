// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SecureWelcomeHomeProperty.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console.log("Deploying from address:", deployerAddress);
        console.log("Deployer balance:", deployerAddress.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        SecureWelcomeHomeProperty token = new SecureWelcomeHomeProperty(
            "WelcomeHomeProperty",
            "WHP"
        );

        console.log("SecureWelcomeHomeProperty deployed at:", address(token));
        console.log("Deployment completed successfully!");

        vm.stopBroadcast();
    }
}

contract DeployWithConfigScript is Script {
    struct DeploymentConfig {
        string tokenName;
        string tokenSymbol;
        address propertyAddress;
        string transactionId;
        uint256 maxTokens;
        address[] minters;
        address[] pausers;
        address[] propertyManagers;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Load configuration
        DeploymentConfig memory config = getConfig();

        console.log("Deploying from address:", deployerAddress);
        console.log("Token Name:", config.tokenName);
        console.log("Token Symbol:", config.tokenSymbol);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        SecureWelcomeHomeProperty token = new SecureWelcomeHomeProperty(
            config.tokenName,
            config.tokenSymbol
        );

        console.log("SecureWelcomeHomeProperty deployed at:", address(token));

        // Configure roles
        for (uint256 i = 0; i < config.minters.length; i++) {
            if (config.minters[i] != address(0)) {
                token.grantRole(token.MINTER_ROLE(), config.minters[i]);
                console.log("Granted MINTER_ROLE to:", config.minters[i]);
            }
        }

        for (uint256 i = 0; i < config.pausers.length; i++) {
            if (config.pausers[i] != address(0)) {
                token.grantRole(token.PAUSER_ROLE(), config.pausers[i]);
                console.log("Granted PAUSER_ROLE to:", config.pausers[i]);
            }
        }

        for (uint256 i = 0; i < config.propertyManagers.length; i++) {
            if (config.propertyManagers[i] != address(0)) {
                token.grantRole(token.PROPERTY_MANAGER_ROLE(), config.propertyManagers[i]);
                console.log("Granted PROPERTY_MANAGER_ROLE to:", config.propertyManagers[i]);
            }
        }

        // Set max tokens if specified
        if (config.maxTokens > 0) {
            token.setMaxTokens(config.maxTokens);
            console.log("Max tokens set to:", config.maxTokens);
        }

        // Connect to property if specified
        if (config.propertyAddress != address(0) && bytes(config.transactionId).length > 0) {
            token.connectToProperty(config.propertyAddress, config.transactionId);
            console.log("Connected to property:", config.propertyAddress);
            console.log("Transaction ID:", config.transactionId);
        }

        console.log("Deployment and configuration completed!");

        vm.stopBroadcast();
    }

    function getConfig() internal view returns (DeploymentConfig memory) {
        DeploymentConfig memory config;

        // Read from environment variables or use defaults
        config.tokenName = vm.envOr("TOKEN_NAME", string("WelcomeHomeProperty"));
        config.tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("WHP"));

        // Property configuration
        config.propertyAddress = vm.envOr("PROPERTY_ADDRESS", address(0));
        config.transactionId = vm.envOr("TRANSACTION_ID", string(""));

        // Max tokens (0 means unlimited)
        config.maxTokens = vm.envOr("MAX_TOKENS", uint256(0));

        // Role assignments (comma-separated addresses in env)
        config.minters = parseAddresses(vm.envOr("MINTERS", string("")));
        config.pausers = parseAddresses(vm.envOr("PAUSERS", string("")));
        config.propertyManagers = parseAddresses(vm.envOr("PROPERTY_MANAGERS", string("")));

        return config;
    }

    function parseAddresses(string memory input) internal pure returns (address[] memory) {
        if (bytes(input).length == 0) {
            return new address[](0);
        }

        // Simple parser for comma-separated addresses
        // In production, use a more robust parsing solution
        uint256 count = 1;
        for (uint256 i = 0; i < bytes(input).length; i++) {
            if (bytes(input)[i] == ",") {
                count++;
            }
        }

        address[] memory addresses = new address[](count);
        // Implementation would parse the string and populate addresses
        // For now, return empty array if not empty string
        return addresses;
    }
}