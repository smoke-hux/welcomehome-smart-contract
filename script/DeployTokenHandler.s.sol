// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/SecureWelcomeHomeProperty.sol";

contract DeployTokenHandler is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with the account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the property token first
        SecureWelcomeHomeProperty propertyToken = new SecureWelcomeHomeProperty(
            "Welcome Home Token",
            "WHT"
        );

        // For demo purposes, using a mock payment token address
        // In production, this would be the HBAR token or USDC on Hedera
        address paymentToken = address(0x1234567890123456789012345678901234567890); // Replace with actual token

        // Deploy the token handler
        PropertyTokenHandler tokenHandler = new PropertyTokenHandler(
            address(propertyToken),
            paymentToken,
            deployer // Fee collector
        );

        // Grant necessary roles to the token handler
        propertyToken.grantRole(propertyToken.MINTER_ROLE(), address(tokenHandler));
        propertyToken.grantRole(propertyToken.PROPERTY_MANAGER_ROLE(), address(tokenHandler));

        vm.stopBroadcast();

        console.log("PropertyToken deployed to:", address(propertyToken));
        console.log("TokenHandler deployed to:", address(tokenHandler));

        // Log important addresses and configuration
        console.log("\n=== Deployment Summary ===");
        console.log("Property Token:", address(propertyToken));
        console.log("Token Handler:", address(tokenHandler));
        console.log("Payment Token:", paymentToken);
        console.log("Fee Collector:", deployer);
        console.log("Deployer has all admin roles on both contracts");
    }
}