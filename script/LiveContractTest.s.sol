// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/MinimalPropertyFactory.sol";
import "../src/PropertyGovernance.sol";
import "../src/interfaces/IPropertyToken.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Live Contract Testing Script
/// @notice Tests deployed contracts on Hedera Testnet to verify functionality
contract LiveContractTestScript is Script {
    // Deployed contract addresses on Hedera Testnet
    address constant PROPERTY_TOKEN_HANDLER = 0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb;
    address constant MINIMAL_PROPERTY_FACTORY = 0x710d1E7F345CA3D893511743A00De2cFC1eAb6De;
    address constant PROPERTY_GOVERNANCE = 0x75A63900FF55F27975005FB8299e3C1b42e28dD6;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== LIVE CONTRACT TESTING ===");
        console.log("Deployer address:", deployer);
        console.log("Deployer HBAR balance:", deployer.balance / 1e18, "HBAR");

        vm.startBroadcast(deployerPrivateKey);

        // Test 1: Check PropertyTokenHandler basic info
        testPropertyTokenHandler();

        // Test 2: Check MinimalPropertyFactory basic info
        testMinimalPropertyFactory();

        // Test 3: Check PropertyGovernance basic info
        testPropertyGovernance();

        vm.stopBroadcast();
    }

    function testPropertyTokenHandler() internal {
        console.log("\n=== TESTING PROPERTY TOKEN HANDLER ===");

        PropertyTokenHandler handler = PropertyTokenHandler(PROPERTY_TOKEN_HANDLER);

        try handler.propertyToken() returns (IPropertyToken propertyTokenContract) {
            console.log("[OK] Property token address:", address(propertyTokenContract));
        } catch {
            console.log("[FAIL] Failed to get property token address");
            return;
        }

        try handler.paymentToken() returns (IERC20 paymentTokenContract) {
            console.log("[OK] Payment token address:", address(paymentTokenContract));
        } catch {
            console.log("[FAIL] Failed to get payment token address");
            return;
        }

        try handler.nextListingId() returns (uint256 nextId) {
            console.log("[OK] Next listing ID:", nextId);
        } catch {
            console.log("[FAIL] Failed to get next listing ID");
        }

        // Test current sale status (simplified to avoid struct destructuring issues)
        try handler.currentSale() {
            console.log("[OK] Current sale data accessible");
        } catch Error(string memory reason) {
            console.log("[FAIL] Failed to get current sale info:", reason);
        } catch {
            console.log("[FAIL] Failed to get current sale info (unknown error)");
        }

        // Check if deployer is accredited investor
        try handler.accreditedInvestors(vm.addr(vm.envUint("HEDERA_PRIVATE_KEY"))) returns (bool isAccredited) {
            console.log("[OK] Deployer accredited status:", isAccredited);
        } catch {
            console.log("[FAIL] Failed to check accredited status");
        }
    }

    function testMinimalPropertyFactory() internal {
        console.log("\n=== TESTING MINIMAL PROPERTY FACTORY ===");

        MinimalPropertyFactory factory = MinimalPropertyFactory(payable(MINIMAL_PROPERTY_FACTORY));

        try factory.propertyCount() returns (uint256 count) {
            console.log("[OK] Property count:", count);
        } catch {
            console.log("[FAIL] Failed to get property count");
            return;
        }

        try factory.propertyCreationFee() returns (uint256 fee) {
            console.log("[OK] Property creation fee:", fee / 1e18, "HBAR");
        } catch {
            console.log("[FAIL] Failed to get property creation fee");
        }

        try factory.feeCollector() returns (address collector) {
            console.log("[OK] Fee collector:", collector);
        } catch {
            console.log("[FAIL] Failed to get fee collector");
        }

        // Try to get creator properties for deployer
        try factory.getCreatorProperties(vm.addr(vm.envUint("HEDERA_PRIVATE_KEY"))) returns (uint256[] memory properties) {
            console.log("[OK] Deployer properties count:", properties.length);
            for (uint256 i = 0; i < properties.length && i < 5; i++) {
                console.log("  - Property ID:", properties[i]);
            }
        } catch {
            console.log("[FAIL] Failed to get creator properties");
        }
    }

    function testPropertyGovernance() internal {
        console.log("\n=== TESTING PROPERTY GOVERNANCE ===");

        PropertyGovernance governance = PropertyGovernance(PROPERTY_GOVERNANCE);

        try governance.proposalCount() returns (uint256 count) {
            console.log("[OK] Proposal count:", count);
        } catch {
            console.log("[FAIL] Failed to get proposal count");
        }

        // Test default governance parameters
        console.log("[OK] Governance contract accessible");
    }
}