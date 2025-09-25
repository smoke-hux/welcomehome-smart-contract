// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/SecureWelcomeHomeProperty.sol";

contract DeployTokenHandler is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with the account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the property token first
        SecureWelcomeHomeProperty propertyToken = new SecureWelcomeHomeProperty(
            "Welcome Home Token",
            "WHT"
        );

        // For demo purposes, using HBAR wrapped token address on Hedera Testnet
        // WHBAR on Hedera Testnet: 0x0000000000000000000000000000000000000001
        address paymentToken = address(0x0000000000000000000000000000000000000001);

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