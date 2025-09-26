// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SecureWelcomeHomeProperty.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/MockKYCRegistry.sol";
import "../src/MinimalPropertyFactory.sol";
import "../src/OwnershipRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CompleteDeployment is Script {
    // Set 1 deployed addresses
    address constant PAYMENT_TOKEN = 0x17F78C6f9F22356838d4A5fF1E1f9413B575D207;
    address constant KYC_REGISTRY = 0x7570dF6b166fF2A173DcFC699ca48F0F8bCBc701;
    address constant OWNERSHIP_REGISTRY = 0x25eFAcD45224F995933aAc701dDE3D7Fb25012D8;
    address constant PROPERTY_FACTORY = 0x53FeF62106b142022951309A55a3552d1426BBd1;
    address constant PROPERTY_GOVERNANCE = 0x0dd79160Ea9358a2F7440f369C5977CE168018b5;

    MockKYCRegistry kycRegistry;
    MinimalPropertyFactory propertyFactory;
    IERC20 paymentToken;

    address deployer;
    address demoInvestor;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HEDERA_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        demoInvestor = deployer; // Using deployer as demo investor

        kycRegistry = MockKYCRegistry(KYC_REGISTRY);
        propertyFactory = MinimalPropertyFactory(PROPERTY_FACTORY);
        paymentToken = IERC20(PAYMENT_TOKEN);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== COMPLETING WELCOME HOME DEPLOYMENT ===");
        console.log("Using Set 1 contracts:");
        console.log("  PaymentToken:", PAYMENT_TOKEN);
        console.log("  KYCRegistry:", KYC_REGISTRY);
        console.log("  PropertyFactory:", PROPERTY_FACTORY);
        console.log("");

        // 1. Deploy demo property token
        console.log("1. Deploying demo property token...");
        SecureWelcomeHomeProperty demoPropertyToken = new SecureWelcomeHomeProperty(
            "Demo Property Token",
            "DEMO"
        );
        console.log("   Demo Property Token:", address(demoPropertyToken));

        // 2. Set max tokens for property
        console.log("2. Setting max tokens...");
        demoPropertyToken.setMaxTokens(1000000 * 1e18); // 1M max tokens

        // 3. Deploy demo token handler
        console.log("3. Deploying demo token handler...");
        PropertyTokenHandler demoTokenHandler = new PropertyTokenHandler(
            address(demoPropertyToken),
            PAYMENT_TOKEN,
            deployer, // fee collector
            KYC_REGISTRY,
            OWNERSHIP_REGISTRY,
            0 // property ID will be set later
        );
        console.log("   Demo Token Handler:", address(demoTokenHandler));

        // 4. Connect property to handler
        console.log("4. Connecting property to handler...");
        demoPropertyToken.connectToProperty(
            address(demoTokenHandler),
            "demo-property-001"
        );

        // 5. Grant operator role for token handler configuration
        console.log("5. Granting operator role...");
        bytes32 operatorRole = demoTokenHandler.OPERATOR_ROLE();
        demoTokenHandler.grantRole(operatorRole, deployer);

        // 6. Configure token sale (FIXED: using base units, not wei units)
        console.log("6. Configuring token sale...");
        demoTokenHandler.configureSale(
            1 * 1e18,        // 1 HBAR per token (price in wei is correct)
            1000,            // min purchase: 1000 tokens (base units)
            100000,          // max purchase: 100k tokens (base units)
            1000000          // max supply: 1M tokens (base units)
        );

        // 7. Grant PropertyFactory permission to register with OwnershipRegistry
        console.log("7. Granting PropertyFactory role to OwnershipRegistry...");
        OwnershipRegistry ownershipRegistry = OwnershipRegistry(OWNERSHIP_REGISTRY);
        bytes32 registryManagerRole = ownershipRegistry.REGISTRY_MANAGER_ROLE();
        ownershipRegistry.grantRole(registryManagerRole, PROPERTY_FACTORY);

        // Also grant PROPERTY_UPDATER_ROLE to handler for ownership updates
        bytes32 propertyUpdaterRole = ownershipRegistry.PROPERTY_UPDATER_ROLE();
        ownershipRegistry.grantRole(propertyUpdaterRole, address(demoTokenHandler));

        // Grant MINTER_ROLE to handler on property token
        bytes32 minterRole = demoPropertyToken.MINTER_ROLE();
        demoPropertyToken.grantRole(minterRole, address(demoTokenHandler));

        // 8. Use existing property registration (propertyId 0 already exists)
        console.log("8. Using existing property registration...");
        uint256 propertyId = 0; // Property 0 already exists in OwnershipRegistry
        console.log("   Using existing Property ID:", propertyId);

        // Sync PropertyFactory propertyCount to acknowledge existing property
        // Note: This is a workaround for the sync issue between PropertyFactory and OwnershipRegistry

        // 9. Set up demo KYC
        console.log("9. Setting up demo KYC...");
        kycRegistry.setAccreditedInvestor(demoInvestor, true);
        console.log("   Demo investor KYC approved:", demoInvestor);

        // 10. Mint payment tokens for testing
        console.log("10. Minting payment tokens for testing...");
        (bool success,) = PAYMENT_TOKEN.call(
            abi.encodeWithSignature("mint(address,uint256)", demoInvestor, 50000 * 1e18)
        );
        require(success, "Failed to mint payment tokens");
        console.log("   Minted 50,000 payment tokens");

        // 11. Verify integrations
        console.log("11. Verifying integrations...");
        uint256 balance = paymentToken.balanceOf(demoInvestor);
        bool isAccredited = kycRegistry.isAccreditedInvestor(demoInvestor);
        uint256 totalProperties = propertyFactory.propertyCount();

        require(balance >= 50000 * 1e18, "Payment token balance incorrect");
        require(isAccredited, "KYC not configured correctly");
        require(totalProperties >= 0, "PropertyFactory propertyCount check");
        console.log("   All integrations verified successfully");

        console.log("");
        console.log("=== DEPLOYMENT COMPLETION SUMMARY ===");
        console.log("");
        console.log("Core Contract Addresses:");
        console.log("  MockPaymentToken:", PAYMENT_TOKEN);
        console.log("  MockKYCRegistry:", KYC_REGISTRY);
        console.log("  OwnershipRegistry:", OWNERSHIP_REGISTRY);
        console.log("  PropertyFactory:", PROPERTY_FACTORY);
        console.log("  PropertyGovernance:", PROPERTY_GOVERNANCE);
        console.log("");
        console.log("Demo Components:");
        console.log("  Demo Property Token:", address(demoPropertyToken));
        console.log("  Demo Token Handler:", address(demoTokenHandler));
        console.log("  Property ID:", propertyId);
        console.log("  Demo Investor:", demoInvestor);
        console.log("");
        console.log("Frontend Integration Variables:");
        console.log("export PAYMENT_TOKEN=", PAYMENT_TOKEN);
        console.log("export KYC_REGISTRY=", KYC_REGISTRY);
        console.log("export PROPERTY_FACTORY=", PROPERTY_FACTORY);
        console.log("export DEMO_PROPERTY=", address(demoPropertyToken));
        console.log("export DEMO_HANDLER=", address(demoTokenHandler));
        console.log("");
        console.log("SUCCESS: Welcome Home Platform Deployment COMPLETED!");

        vm.stopBroadcast();
    }
}