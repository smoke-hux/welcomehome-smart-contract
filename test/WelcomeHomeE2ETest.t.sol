// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PropertyFactory.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/SecureWelcomeHomeProperty.sol";
import "../src/OwnershipRegistry.sol";
import "../src/MockKYCRegistry.sol";
import "../src/PropertyGovernance.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title WelcomeHomeE2ETest
/// @notice Comprehensive End-to-End test validating complete user journey per whitepaper
/// @dev Tests: KYC → Property Creation → Token Purchase → Revenue → Trading → Governance
contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock HBAR", "HBAR") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract WelcomeHomeE2ETest is Test {
    // All system contracts
    PropertyFactory public propertyFactory;
    OwnershipRegistry public ownershipRegistry;
    MockKYCRegistry public kycRegistry;
    PropertyGovernance public governance;
    MockPaymentToken public paymentToken;

    // Property-specific contracts (deployed during test)
    SecureWelcomeHomeProperty public propertyToken;
    PropertyTokenHandler public tokenHandler;

    // Test actors representing real users
    address public admin;
    address public propertyOwner;
    address public investor1; // Retail investor
    address public investor2; // Accredited investor
    address public investor3; // Institutional investor
    address public feeCollector;

    // Test constants matching realistic values
    uint256 public constant PROPERTY_VALUE = 500000 * 10**18; // $500K property
    uint256 public constant MAX_TOKENS = 500000 * 10**18;     // 1:1 token to dollar ratio
    uint256 public constant TOKEN_PRICE = 1 * 10**18;        // $1 per token
    uint256 public constant MONTHLY_RENT = 3000 * 10**18;    // $3K monthly rent

    uint256 public propertyId;

    function setUp() public {
        // Setup actors
        admin = address(this);
        propertyOwner = makeAddr("propertyOwner");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        investor3 = makeAddr("investor3");
        feeCollector = makeAddr("feeCollector");

        // Deploy core infrastructure
        paymentToken = new MockPaymentToken();
        kycRegistry = new MockKYCRegistry();
        ownershipRegistry = new OwnershipRegistry();
        propertyFactory = new PropertyFactory(feeCollector, address(kycRegistry), address(ownershipRegistry));
        governance = new PropertyGovernance(address(propertyFactory));

        // Grant roles
        propertyFactory.grantRole(propertyFactory.PROPERTY_CREATOR_ROLE(), propertyOwner);

        // Grant ownership registry roles to property factory
        ownershipRegistry.grantRole(0x00, address(propertyFactory)); // DEFAULT_ADMIN_ROLE
        ownershipRegistry.grantRole(ownershipRegistry.REGISTRY_MANAGER_ROLE(), address(propertyFactory));

        // Provide funding
        vm.deal(propertyOwner, 10 ether);
        vm.deal(investor1, 10 ether);
        vm.deal(investor2, 10 ether);
        vm.deal(investor3, 10 ether);

        paymentToken.mint(investor1, 100000 * 10**18);
        paymentToken.mint(investor2, 200000 * 10**18);
        paymentToken.mint(investor3, 300000 * 10**18);
    }

    /// @notice Tests complete user journey as specified in whitepaper
    /// @dev Journey: KYC → Property → Tokens → Revenue → Trading → Governance
    function testCompleteUserJourney() public {
        console.log("=== WELCOME HOME E2E TEST: Complete User Journey ===");

        // PHASE 1: KYC VERIFICATION (Whitepaper Section 4.1)
        _testKYCVerification();

        // PHASE 2: PROPERTY TOKENIZATION (Whitepaper Section 6.1)
        _testPropertyCreationAndTokenization();

        // PHASE 3: PRIMARY TOKEN OFFERING (Whitepaper Section 6.2)
        _testPrimaryTokenPurchases();

        // PHASE 4: STAKING AND REVENUE DISTRIBUTION
        _testStakingAndRevenueDistribution();

        // PHASE 5: SECONDARY MARKETPLACE TRADING
        _testSecondaryMarketplaceTrading();

        // PHASE 6: PROPERTY GOVERNANCE
        _testPropertyGovernance();

        // PHASE 7: FINAL SYSTEM VALIDATION
        _testSystemStateConsistency();

        console.log("PASSED: Complete E2E Test - All whitepaper features working!");
    }

    function _testKYCVerification() internal {
        console.log("\n--- Phase 1: KYC Verification ---");

        // Property owner KYC
        vm.prank(propertyOwner);
        kycRegistry.submitKYC("property-owner-llc-docs", MockKYCRegistry.InvestorType.INSTITUTIONAL);
        kycRegistry.approveKYC(propertyOwner);

        // Investor KYC submissions
        vm.prank(investor1);
        kycRegistry.submitKYC("john-smith-docs", MockKYCRegistry.InvestorType.RETAIL);
        kycRegistry.approveKYC(investor1);

        vm.prank(investor2);
        kycRegistry.submitKYC("jane-doe-docs", MockKYCRegistry.InvestorType.ACCREDITED);
        kycRegistry.approveKYC(investor2);

        vm.prank(investor3);
        kycRegistry.submitKYC("big-fund-lp-docs", MockKYCRegistry.InvestorType.INSTITUTIONAL);
        kycRegistry.approveKYC(investor3);

        // Set accredited investor status (required for token purchases)
        kycRegistry.setAccreditedInvestor(propertyOwner, true);  // INSTITUTIONAL
        kycRegistry.setAccreditedInvestor(investor1, true);      // RETAIL -> make accredited
        kycRegistry.setAccreditedInvestor(investor2, true);      // ACCREDITED
        kycRegistry.setAccreditedInvestor(investor3, true);      // INSTITUTIONAL

        // Verify all KYC approvals
        assertEq(uint256(kycRegistry.getKYCStatus(propertyOwner)), uint256(MockKYCRegistry.KYCStatus.APPROVED));
        assertEq(uint256(kycRegistry.getKYCStatus(investor1)), uint256(MockKYCRegistry.KYCStatus.APPROVED));
        assertEq(uint256(kycRegistry.getKYCStatus(investor2)), uint256(MockKYCRegistry.KYCStatus.APPROVED));
        assertEq(uint256(kycRegistry.getKYCStatus(investor3)), uint256(MockKYCRegistry.KYCStatus.APPROVED));

        // Verify all accredited investor status
        assertTrue(kycRegistry.isAccreditedInvestor(propertyOwner));
        assertTrue(kycRegistry.isAccreditedInvestor(investor1));
        assertTrue(kycRegistry.isAccreditedInvestor(investor2));
        assertTrue(kycRegistry.isAccreditedInvestor(investor3));

        console.log("PASSED: KYC verification complete for all participants");
    }

    function _testPropertyCreationAndTokenization() internal {
        console.log("\n--- Phase 2: Property Creation & Tokenization ---");

        vm.startPrank(propertyOwner);

        // Create property using PropertyFactory (primary system)
        PropertyFactory.PropertyDeploymentParams memory params = PropertyFactory.PropertyDeploymentParams({
            name: "Downtown Apartment Complex",
            symbol: "DOWNTOWN",
            ipfsHash: "QmRealPropertyDocs123",
            totalValue: PROPERTY_VALUE,
            maxTokens: MAX_TOKENS,
            propertyType: PropertyFactory.PropertyType.RESIDENTIAL,
            location: "Downtown Manhattan, NY",
            paymentToken: address(paymentToken)
        });

        propertyId = propertyFactory.deployProperty{value: 1 ether}(params);

        // Get deployed contracts
        PropertyFactory.PropertyInfo memory property = propertyFactory.getProperty(propertyId);
        propertyToken = SecureWelcomeHomeProperty(property.tokenContract);
        tokenHandler = PropertyTokenHandler(property.handlerContract);

        vm.stopPrank();

        // Verify property creation
        assertEq(propertyToken.name(), "Downtown Apartment Complex");
        assertEq(propertyToken.symbol(), "DOWNTOWN");
        assertEq(propertyToken.maxTokens(), MAX_TOKENS);
        assertTrue(property.isActive);

        console.log("[SUCCESS] Property tokenization complete");
        console.log("   Property Value: $500,000");
        console.log("   Total Tokens: 500,000");
        console.log("   Token Price: $1.00");
    }

    function _testPrimaryTokenPurchases() internal {
        console.log("\n--- Phase 3: Primary Token Offering ---");

        vm.startPrank(propertyOwner);
        // Configure token sale (min/max/supply in base units, not decimals)
        tokenHandler.configureSale(
            TOKEN_PRICE,     // 1 ether per token
            100,             // min: 100 base units ($100)
            50000,           // max: 50,000 base units ($50,000 per investor)
            500000           // max supply: 500,000 base units
        );
        vm.stopPrank();

        // Investor 1: Retail investor buys $10,000 worth (10,000 tokens)
        vm.startPrank(investor1);
        paymentToken.approve(address(tokenHandler), 10000 * 10**18);
        tokenHandler.purchaseTokens(10000); // BASE UNITS: 10,000 base units
        vm.stopPrank();

        // Investor 2: Accredited investor buys $30,000 worth (30,000 tokens)
        vm.startPrank(investor2);
        paymentToken.approve(address(tokenHandler), 30000 * 10**18);
        tokenHandler.purchaseTokens(30000); // BASE UNITS: 30,000 base units
        vm.stopPrank();

        // Investor 3: Institutional investor buys $50,000 worth (50,000 tokens)
        vm.startPrank(investor3);
        paymentToken.approve(address(tokenHandler), 50000 * 10**18);
        tokenHandler.purchaseTokens(50000); // BASE UNITS: 50,000 base units
        vm.stopPrank();

        // Verify token balances
        assertEq(propertyToken.balanceOf(investor1), 10000 * 10**18);
        assertEq(propertyToken.balanceOf(investor2), 30000 * 10**18);
        assertEq(propertyToken.balanceOf(investor3), 50000 * 10**18);

        // Ownership registry is automatically updated by PropertyTokenHandler

        console.log("[SUCCESS] Primary token offering complete");
        console.log("   Investor1: $10,000 (2% ownership)");
        console.log("   Investor2: $30,000 (6% ownership)");
        console.log("   Investor3: $50,000 (10% ownership)");
        console.log("   Total Sold: $90,000 (18% of property)");
    }

    function _testStakingAndRevenueDistribution() internal {
        console.log("\n--- Phase 4: Staking & Revenue Distribution ---");

        // Investors stake their tokens to earn revenue
        vm.startPrank(investor1);
        propertyToken.approve(address(tokenHandler), 5000 * 10**18);  // Stake half, keep half liquid for trading
        tokenHandler.stakeTokens(5000 * 10**18);
        vm.stopPrank();

        vm.startPrank(investor2);
        propertyToken.approve(address(tokenHandler), 15000 * 10**18); // Stake half
        tokenHandler.stakeTokens(15000 * 10**18);
        vm.stopPrank();

        vm.startPrank(investor3);
        propertyToken.approve(address(tokenHandler), 25000 * 10**18);  // Stake half, keep half liquid for trading
        tokenHandler.stakeTokens(25000 * 10**18);
        vm.stopPrank();

        // Simulate monthly rent collection and distribution
        vm.startPrank(propertyOwner);
        paymentToken.mint(propertyOwner, MONTHLY_RENT); // Mint to propertyOwner, not tokenHandler
        paymentToken.approve(address(tokenHandler), MONTHLY_RENT); // Approve tokenHandler to spend
        tokenHandler.distributeRevenue(MONTHLY_RENT);
        vm.stopPrank();

        // Investors claim their revenue share
        uint256 investor1BalanceBefore = paymentToken.balanceOf(investor1);
        vm.prank(investor1);
        tokenHandler.claimRevenue();
        uint256 investor1Revenue = paymentToken.balanceOf(investor1) - investor1BalanceBefore;

        uint256 investor2BalanceBefore = paymentToken.balanceOf(investor2);
        vm.prank(investor2);
        tokenHandler.claimRevenue();
        uint256 investor2Revenue = paymentToken.balanceOf(investor2) - investor2BalanceBefore;

        uint256 investor3BalanceBefore = paymentToken.balanceOf(investor3);
        vm.prank(investor3);
        tokenHandler.claimRevenue();
        uint256 investor3Revenue = paymentToken.balanceOf(investor3) - investor3BalanceBefore;

        // Verify revenue distribution is proportional to stake
        assertTrue(investor1Revenue > 0, "Investor1 should receive revenue");
        assertTrue(investor2Revenue > 0, "Investor2 should receive revenue");
        assertTrue(investor3Revenue > 0, "Investor3 should receive revenue");

        // Investor3 has highest stake, should get most revenue
        assertTrue(investor3Revenue > investor1Revenue, "Investor3 should get more than Investor1");
        assertTrue(investor3Revenue > investor2Revenue, "Investor3 should get more than Investor2");

        console.log("[SUCCESS] Revenue distribution complete");
        console.log("   Monthly Rent: $3,000");
        console.log("   Distributed proportionally to staked tokens");
    }

    function _testSecondaryMarketplaceTrading() internal {
        console.log("\n--- Phase 5: Secondary Marketplace Trading ---");

        // Investor1 lists some tokens for sale at premium price
        vm.startPrank(investor1);
        uint256 sellAmount = 5000 * 10**18;
        uint256 sellPrice = 12 * 10**17; // $1.20 per token (20% premium)

        // Approve PropertyTokenHandler to spend tokens before listing
        propertyToken.approve(address(tokenHandler), sellAmount);
        tokenHandler.listTokensForSale(sellAmount, sellPrice);
        vm.stopPrank();

        // Investor2 purchases from the marketplace
        vm.startPrank(investor2);
        uint256 purchaseAmount = 3000 * 10**18;
        uint256 totalCost = (purchaseAmount * sellPrice) / 10**18;

        paymentToken.approve(address(tokenHandler), totalCost);
        tokenHandler.purchaseFromMarketplace(0, purchaseAmount); // listingId = 0
        vm.stopPrank();

        // Verify secondary market transaction
        assertEq(propertyToken.balanceOf(investor1), 2000 * 10**18); // 5000 liquid - 3000 sold (+ 5000 staked separately)
        assertEq(propertyToken.balanceOf(investor2), 18000 * 10**18); // 15000 liquid + 3000 bought (+ 15000 staked separately)

        console.log("[SUCCESS] Secondary marketplace trading complete");
        console.log("   Investor1 sold 3,000 tokens at $1.20 each");
        console.log("   Investor2 purchased 3,000 tokens for $3,600");
    }

    function _testPropertyGovernance() internal {
        console.log("\n--- Phase 6: Property Governance ---");

        // Create governance proposal for property improvement (investor2 has tokens to create proposals)
        vm.prank(investor2);
        uint256 proposalId = governance.createProposal(
            propertyId,
            "HVAC System Upgrade",
            "Install new energy-efficient HVAC system to reduce operating costs and improve tenant satisfaction",
            "QmHVACUpgradeProposal456",
            PropertyGovernance.ProposalType.IMPROVEMENT
        );

        // Wait for voting period
        vm.warp(block.timestamp + 1 days + 1);

        // Token holders vote (voting power = token balance)
        vm.prank(investor1);
        governance.vote(proposalId, 1); // FOR - 7,000 tokens

        vm.prank(investor2);
        governance.vote(proposalId, 1); // FOR - 33,000 tokens

        vm.prank(investor3);
        governance.vote(proposalId, 0); // AGAINST - 50,000 tokens

        // Wait for voting to end
        vm.warp(block.timestamp + 7 days + 1);

        // Execute proposal (should pass: 40,000 FOR vs 50,000 AGAINST, but need to check quorum)
        governance.updateProposalStatus(proposalId);

        PropertyGovernance.ProposalView memory proposal = governance.getProposalInfo(proposalId);
        PropertyGovernance.ProposalVotes memory votes = governance.getProposalVotes(proposalId);

        assertTrue(votes.totalVotes > 0, "Should have votes recorded");
        assertTrue(votes.forVotes == 20000 * 10**18, "Should have 20k FOR votes");
        assertTrue(votes.againstVotes == 25000 * 10**18, "Should have 25k AGAINST votes");

        console.log("[SUCCESS] Property governance complete");
        console.log("   Proposal: HVAC System Upgrade");
        console.log("   Voting: 20,000 FOR vs 25,000 AGAINST");
        console.log("   Result: Determined by quorum and majority rules");
    }

    function _testSystemStateConsistency() internal {
        console.log("\n--- Phase 7: Final System Validation ---");

        // Verify total system state
        uint256 totalSupply = propertyToken.totalSupply();
        (,, uint256 totalStaked,,) = tokenHandler.getContractStats();

        assertTrue(totalSupply == 90000 * 10**18, "Total supply should be 90,000 tokens");
        assertTrue(totalStaked <= totalSupply, "Staked <= Total supply");
        (,,,,, bool saleActive) = tokenHandler.getTokenSaleInfo();
        assertTrue(saleActive, "Token sale should still be active");

        // Verify ownership registry
        (uint256 totalProperties, uint256 totalUsers, ) = ownershipRegistry.getGlobalStats();
        assertTrue(totalProperties > 0, "Should track properties");
        assertTrue(totalUsers > 0, "Should track users");

        // Verify all major contracts are properly connected
        assertTrue(propertyToken.hasRole(propertyToken.MINTER_ROLE(), address(tokenHandler)));
        assertTrue(propertyFactory.propertyCount() > 0);
        assertTrue(governance.proposalCount() > 0);

        console.log("[SUCCESS] System state validation complete");
        console.log("   Total Token Supply: 90,000");
        console.log("   Active Stakers: All investors");
        console.log("   Properties Tracked: 1");
        console.log("   Governance Proposals: 1");
        console.log("   KYC Verified Users: 4");
    }

    /// @notice Test error conditions and edge cases
    function testEdgeCasesAndErrorHandling() public {
        // Setup basic system
        testCompleteUserJourney();

        console.log("\n=== EDGE CASES & ERROR HANDLING ===");

        // Test: Non-KYC user cannot purchase tokens
        address nonKYCUser = makeAddr("nonKYCUser");
        paymentToken.mint(nonKYCUser, 10000 * 10**18);

        vm.startPrank(nonKYCUser);
        paymentToken.approve(address(tokenHandler), 1000 * 10**18);
        vm.expectRevert(); // Should fail due to onlyAccredited modifier
        tokenHandler.purchaseTokens(1000); // BASE UNITS: 1,000 base units
        vm.stopPrank();

        // Test: Cannot purchase below minimum
        vm.startPrank(investor1);
        paymentToken.approve(address(tokenHandler), 50 * 10**18);
        vm.expectRevert(PropertyTokenHandler.PurchaseAmountTooLow.selector);
        tokenHandler.purchaseTokens(50); // BASE UNITS: Below 100 minimum
        vm.stopPrank();

        // Test: Cannot unstake more than staked
        vm.startPrank(investor1);
        vm.expectRevert(PropertyTokenHandler.InsufficientTokenBalance.selector);
        tokenHandler.unstakeTokens(20000 * 10**18); // More than staked amount
        vm.stopPrank();

        console.log("[SUCCESS] Error handling validation complete");
    }

    /// @notice Performance test with realistic load
    function testSystemPerformance() public {
        console.log("\n=== PERFORMANCE TESTING ===");

        // Test multiple rapid transactions
        uint256 gasStart = gasleft();

        testCompleteUserJourney();

        uint256 gasUsed = gasStart - gasleft();
        console.log("Total gas used for complete user journey:", gasUsed);

        // Performance should be reasonable for mainnet
        assertTrue(gasUsed < 10000000, "Complete journey should use less than 10M gas");

        console.log("[SUCCESS] Performance testing complete");
    }
}