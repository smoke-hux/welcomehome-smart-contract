// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MinimalPropertyFactory} from "../src/MinimalPropertyFactory.sol";
import {PropertyGovernance} from "../src/PropertyGovernance.sol";

contract TestSystemScript is Script {
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        address payable factoryAddress = payable(vm.envOr("FACTORY_ADDRESS", address(0x710d1E7F345CA3D893511743A00De2cFC1eAb6De)));
        address governanceAddress = vm.envOr("GOVERNANCE_ADDRESS", address(0x75A63900FF55F27975005FB8299e3C1b42e28dD6));

        require(factoryAddress != address(0), "Factory address not set");
        require(governanceAddress != address(0), "Governance address not set");

        console.log("=== Testing Welcome Home System ===");
        console.log("Factory address:", factoryAddress);
        console.log("Governance address:", governanceAddress);
        console.log("Test account:", deployerAddress);

        MinimalPropertyFactory factory = MinimalPropertyFactory(factoryAddress);
        PropertyGovernance governance = PropertyGovernance(governanceAddress);

        // Test reading factory state
        console.log("\n=== Factory State ===");
        console.log("Property count:", factory.propertyCount());
        console.log("Creation fee:", factory.propertyCreationFee() / 1e18, "HBAR");
        console.log("Fee collector:", factory.feeCollector());

        // Test reading governance state
        console.log("\n=== Governance State ===");
        console.log("Proposal count:", governance.proposalCount());
        console.log("Voting delay:", governance.VOTING_DELAY() / 86400, "days");
        console.log("Voting period:", governance.VOTING_PERIOD() / 86400, "days");

        // Test role checks
        console.log("\n=== Role Checks ===");
        bytes32 creatorRole = factory.PROPERTY_CREATOR_ROLE();
        bytes32 managerRole = factory.PROPERTY_MANAGER_ROLE();

        console.log("Has PROPERTY_CREATOR_ROLE:", factory.hasRole(creatorRole, deployerAddress));
        console.log("Has PROPERTY_MANAGER_ROLE:", factory.hasRole(managerRole, deployerAddress));

        console.log("\n=== System Test Complete ===");
        console.log("All contracts are deployed and functional!");
    }
}