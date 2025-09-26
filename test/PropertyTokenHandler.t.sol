// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PropertyTokenHandler.sol";
import "../src/SecureWelcomeHomeProperty.sol";
import "../src/MockKYCRegistry.sol";
import "../src/OwnershipRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock HBAR/payment token for testing
contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock HBAR", "MHBAR") {
        _mint(msg.sender, 1000000 * 10**18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PropertyTokenHandlerTest is Test {
    PropertyTokenHandler public handler;
    SecureWelcomeHomeProperty public propertyToken;
    MockPaymentToken public paymentToken;
    MockKYCRegistry public kycRegistry;
    OwnershipRegistry public ownershipRegistry;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public revenueManager = address(0x3);
    address public marketplaceManager = address(0x4);
    address public feeCollector = address(0x5);
    address public investor1 = address(0x6);
    address public investor2 = address(0x7);
    address public nonAccredited = address(0x8);

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REVENUE_MANAGER_ROLE = keccak256("REVENUE_MANAGER_ROLE");
    bytes32 public constant MARKETPLACE_MANAGER_ROLE = keccak256("MARKETPLACE_MANAGER_ROLE");

    function setUp() public {
        vm.startPrank(admin);

        // Deploy mock payment token
        paymentToken = new MockPaymentToken();

        // Deploy property token
        propertyToken = new SecureWelcomeHomeProperty("Test Property", "TPT");

        // Connect property to enable minting
        propertyToken.grantRole(propertyToken.PROPERTY_MANAGER_ROLE(), admin);
        propertyToken.connectToProperty(address(0x100), "TEST-TX-001");

        // Deploy additional dependencies
        kycRegistry = new MockKYCRegistry();
        ownershipRegistry = new OwnershipRegistry();

        // Grant roles to handler for ownership registry
        ownershipRegistry.grantRole(ownershipRegistry.PROPERTY_UPDATER_ROLE(), address(this));

        // Deploy handler
        handler = new PropertyTokenHandler(
            address(propertyToken),
            address(paymentToken),
            feeCollector,
            address(kycRegistry),
            address(ownershipRegistry),
            0 // propertyId
        );

        // Grant roles to handler for ownership registry
        ownershipRegistry.grantRole(ownershipRegistry.PROPERTY_UPDATER_ROLE(), address(handler));

        // Register property in ownership registry (required for token operations)
        ownershipRegistry.registerProperty(0, address(propertyToken), address(handler));

        // Setup KYC for investors
        kycRegistry.setAccreditedInvestor(investor1, true);
        kycRegistry.setAccreditedInvestor(investor2, true);

        // Grant minter role to handler
        propertyToken.grantRole(propertyToken.MINTER_ROLE(), address(handler));

        // Grant roles in handler
        handler.grantRole(OPERATOR_ROLE, operator);
        handler.grantRole(REVENUE_MANAGER_ROLE, revenueManager);
        handler.grantRole(MARKETPLACE_MANAGER_ROLE, marketplaceManager);

        // Set up investors with payment tokens
        paymentToken.transfer(investor1, 10000 * 10**18);
        paymentToken.transfer(investor2, 10000 * 10**18);
        paymentToken.transfer(nonAccredited, 1000 * 10**18);

        vm.stopPrank();
    }

    // ========== TOKEN SALE TESTS ==========

    function testConfigureSale() public {
        vm.startPrank(operator);

        handler.configureSale(
            1 * 10**18, // 1 HBAR per token
            10 * 10**18, // min 10 tokens
            1000 * 10**18, // max 1000 tokens
            100000 * 10**18 // max supply
        );

        (
            uint256 pricePerToken,
            uint256 minPurchase,
            uint256 maxPurchase,
            bool isActive,
            uint256 totalSold,
            uint256 maxSupply,
            uint256 saleEndTime,
            uint256 propertyId
        ) = handler.currentSale();

        assertEq(pricePerToken, 1 * 10**18);
        assertEq(minPurchase, 10 * 10**18);
        assertEq(maxPurchase, 1000 * 10**18);
        assertTrue(isActive);
        assertEq(totalSold, 0);
        assertEq(maxSupply, 100000 * 10**18);

        vm.stopPrank();
    }

    function testCannotConfigureSaleWithoutRole() public {
        vm.startPrank(nonAccredited);

        vm.expectRevert();
        handler.configureSale(1 * 10**18, 10 * 10**18, 1000 * 10**18, 100000 * 10**18);

        vm.stopPrank();
    }

    function testPurchaseTokens() public {
        // Configure sale first - price is 1 HBAR per token
        vm.prank(operator);
        handler.configureSale(1 * 10**18, 10, 1000, 100000); // price per token, min, max, supply in base units

        vm.startPrank(investor1);

        // Purchase 100 base units of tokens
        // Cost: 100 * (1 * 10**18) = 100 * 10**18 = 100 HBAR total
        uint256 tokenAmount = 100;
        uint256 totalCost = tokenAmount * (1 * 10**18); // 100 HBAR
        paymentToken.approve(address(handler), totalCost);

        // Purchase 100 tokens
        handler.purchaseTokens(tokenAmount);

        // Verify balances - tokens minted in wei units
        assertEq(propertyToken.balanceOf(investor1), 100 * 10**18);

        // Payment balance should be reduced by totalCost
        assertEq(paymentToken.balanceOf(investor1), (10000 * 10**18) - totalCost);

        vm.stopPrank();

        // Verify sale state - totalSold tracks base units purchased
        (, , , , uint256 totalSold, , , ) = handler.currentSale();
        assertEq(totalSold, 100);
    }

    function testCannotPurchaseTokensNotAccredited() public {
        vm.prank(operator);
        handler.configureSale(1 * 10**18, 10 * 10**18, 1000 * 10**18, 100000 * 10**18);

        vm.startPrank(nonAccredited);

        paymentToken.approve(address(handler), 100 * 10**18);

        vm.expectRevert(PropertyTokenHandler.NotAccreditedInvestor.selector);
        handler.purchaseTokens(100 * 10**18);

        vm.stopPrank();
    }

    function testCannotPurchaseBelowMinimum() public {
        vm.prank(operator);
        handler.configureSale(1 * 10**18, 100 * 10**18, 1000 * 10**18, 100000 * 10**18);

        vm.startPrank(investor1);

        paymentToken.approve(address(handler), 50 * 10**18);

        vm.expectRevert(PropertyTokenHandler.PurchaseAmountTooLow.selector);
        handler.purchaseTokens(50 * 10**18);

        vm.stopPrank();
    }

    function testCannotPurchaseAboveMaximum() public {
        vm.prank(operator);
        handler.configureSale(1 * 10**18, 10 * 10**18, 100 * 10**18, 100000 * 10**18);

        vm.startPrank(investor1);

        paymentToken.approve(address(handler), 200 * 10**18);

        vm.expectRevert(PropertyTokenHandler.PurchaseAmountTooHigh.selector);
        handler.purchaseTokens(200 * 10**18);

        vm.stopPrank();
    }

    // ========== MARKETPLACE TESTS ==========

    function testListTokensForSale() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        vm.startPrank(investor1);
        propertyToken.approve(address(handler), 100 * 10**18);
        handler.listTokensForSale(100 * 10**18, 2 * 10**18); // List 100 tokens at 2 HBAR each (price in 18 decimals)

        (
            address seller,
            uint256 amount,
            uint256 pricePerToken,
            uint256 listingTime,
            bool isActive,
            uint256 propertyId,
            address tokenContract
        ) = handler.marketplaceListings(0);

        assertEq(seller, investor1);
        assertEq(amount, 100 * 10**18);
        assertEq(pricePerToken, 2 * 10**18); // Price stored in 18 decimals
        assertEq(listingTime, block.timestamp);
        assertTrue(isActive);

        vm.stopPrank();
    }

    function testPurchaseFromMarketplace() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        // List tokens (seller needs to approve first)
        vm.startPrank(investor1);
        propertyToken.approve(address(handler), 100 * 10**18);
        handler.listTokensForSale(100 * 10**18, 2 * 10**18); // Price in 18 decimals
        vm.stopPrank();

        vm.startPrank(investor2);

        // Approve payment (100 tokens * 2 HBAR = 200 HBAR total)
        uint256 totalCost = 200 * 10**18; // Total cost after normalization: (amount * price) / 1e18
        paymentToken.approve(address(handler), totalCost);

        // Calculate expected fee (2.5% of total cost)
        uint256 expectedFee = (totalCost * 250) / 10000; // 250 basis points = 2.5%

        // Purchase tokens from marketplace
        handler.purchaseFromMarketplace(0, 100 * 10**18);

        // Verify balances
        assertEq(propertyToken.balanceOf(investor2), 100 * 10**18);
        assertEq(paymentToken.balanceOf(feeCollector), expectedFee);

        vm.stopPrank();

        // Verify listing is inactive
        (, , , , bool isActive, , ) = handler.marketplaceListings(0);
        assertFalse(isActive);
    }

    function testCannotListTokensWithoutBalance() public {
        vm.startPrank(investor1);

        vm.expectRevert(PropertyTokenHandler.InsufficientTokenBalance.selector);
        handler.listTokensForSale(100 * 10**18, 2 * 10**18);

        vm.stopPrank();
    }

    // ========== STAKING TESTS ==========

    function testStakeTokens() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        vm.startPrank(investor1);

        // Approve tokens for staking
        propertyToken.approve(address(handler), 500 * 10**18);

        // Stake tokens
        handler.stakeTokens(500 * 10**18);

        // Verify staking info
        (
            uint256 stakedAmount,
            uint256 stakeTime,
            uint256 lastRewardClaim,
            uint256 totalRewards,
            uint256 propertyId
        ) = handler.stakingInfo(investor1);

        assertEq(stakedAmount, 500 * 10**18);
        assertEq(stakeTime, block.timestamp);
        assertEq(lastRewardClaim, block.timestamp);
        assertEq(totalRewards, 0);

        // Verify token balance
        assertEq(propertyToken.balanceOf(investor1), 500 * 10**18);
        assertEq(propertyToken.balanceOf(address(handler)), 500 * 10**18);

        vm.stopPrank();
    }

    function testCalculateStakingRewards() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        vm.startPrank(investor1);
        propertyToken.approve(address(handler), 500 * 10**18);
        handler.stakeTokens(500 * 10**18);
        vm.stopPrank();

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        uint256 rewards = handler.calculateStakingRewards(investor1);

        // Expected reward: (500 tokens * 5% APY * 30 days) / 365 days
        // Calculate: 500e18 * 500 * 30 / (10000 * 365)
        uint256 annualReward = (500 * 10**18 * 500) / 10000; // 5% of 500 tokens
        uint256 expectedReward = (annualReward * 30) / 365;
        assertApproxEqRel(rewards, expectedReward, 1e17); // Within 10% tolerance for time calculations
    }

    function testUnstakeTokens() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        vm.startPrank(investor1);
        propertyToken.approve(address(handler), 500 * 10**18);
        handler.stakeTokens(500 * 10**18);
        vm.stopPrank();

        // Fast forward past minimum stake duration
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(investor1);

        uint256 balanceBeforeUnstake = propertyToken.balanceOf(investor1);

        handler.unstakeTokens(300 * 10**18);

        // The contract calculates and adds rewards during unstaking
        // We just verify the balance increased by unstaked amount + some rewards
        uint256 balanceAfterUnstake = propertyToken.balanceOf(investor1);
        assertGt(balanceAfterUnstake, balanceBeforeUnstake + 300 * 10**18); // Should be more than just unstaked
        assertLt(balanceAfterUnstake, balanceBeforeUnstake + 305 * 10**18); // But not too much more

        // Verify remaining stake
        (uint256 stakedAmount, , , uint256 totalRewards, ) = handler.stakingInfo(investor1);
        assertEq(stakedAmount, 200 * 10**18);
        assertGt(totalRewards, 0); // Should have earned rewards

        vm.stopPrank();
    }

    function testCannotUnstakeBeforeMinimumPeriod() public {
        _setupTokensForInvestor(investor1, 1000 * 10**18);

        vm.startPrank(investor1);
        propertyToken.approve(address(handler), 500 * 10**18);
        handler.stakeTokens(500 * 10**18);

        // Try to unstake before 30 days
        vm.warp(block.timestamp + 29 days);

        vm.expectRevert(PropertyTokenHandler.StakingPeriodNotMet.selector);
        handler.unstakeTokens(100 * 10**18);

        vm.stopPrank();
    }

    // ========== REVENUE DISTRIBUTION TESTS ==========

    function testDistributeRevenue() public {
        // Set up multiple token holders
        _setupTokensForInvestor(investor1, 600 * 10**18);
        _setupTokensForInvestor(investor2, 400 * 10**18);

        vm.startPrank(revenueManager);

        // Approve and distribute 1000 HBAR as revenue
        paymentToken.mint(revenueManager, 1000 * 10**18);
        paymentToken.approve(address(handler), 1000 * 10**18);

        handler.distributeRevenue(1000 * 10**18);

        // Verify revenue distribution
        (
            uint256 totalRevenue,
            uint256 distributedRevenue,
            uint256 revenuePerToken,
            uint256 lastDistribution,
            uint256 propertyId,
            address tokenContract
        ) = handler.propertyRevenue();

        assertEq(totalRevenue, 1000 * 10**18);
        assertEq(lastDistribution, block.timestamp);
        assertEq(revenuePerToken, 1e18); // With precision multiplier: (1000 * 10^18 * 1e18) / (1000 * 10^18) = 1e18

        vm.stopPrank();
    }

    function testClaimRevenue() public {
        _setupTokensForInvestor(investor1, 600 * 10**18);
        _setupTokensForInvestor(investor2, 400 * 10**18);

        // Distribute revenue
        vm.startPrank(revenueManager);
        paymentToken.mint(revenueManager, 1000 * 10**18);
        paymentToken.approve(address(handler), 1000 * 10**18);
        handler.distributeRevenue(1000 * 10**18);
        vm.stopPrank();

        // Check claimable revenue
        uint256 claimable1 = handler.getClaimableRevenue(investor1);
        uint256 claimable2 = handler.getClaimableRevenue(investor2);

        assertEq(claimable1, 600 * 10**18); // 600 tokens * 1 HBAR per token
        assertEq(claimable2, 400 * 10**18); // 400 tokens * 1 HBAR per token

        // Claim revenue
        uint256 balanceBefore = paymentToken.balanceOf(investor1);
        vm.prank(investor1);
        handler.claimRevenue();

        assertEq(paymentToken.balanceOf(investor1), balanceBefore + 600 * 10**18);
    }

    function testCannotClaimRevenueMultipleTimes() public {
        _setupTokensForInvestor(investor1, 500 * 10**18);

        // Distribute and claim once
        vm.startPrank(revenueManager);
        paymentToken.mint(revenueManager, 500 * 10**18);
        paymentToken.approve(address(handler), 500 * 10**18);
        handler.distributeRevenue(500 * 10**18);
        vm.stopPrank();

        vm.prank(investor1);
        handler.claimRevenue();

        // Try to claim again
        vm.prank(investor1);
        vm.expectRevert(PropertyTokenHandler.NoRewardsAvailable.selector);
        handler.claimRevenue();
    }

    // ========== ACCESS CONTROL TESTS ==========

    function testSetAccreditedInvestor() public {
        vm.startPrank(admin);

        assertTrue(kycRegistry.isAccreditedInvestor(investor1));

        kycRegistry.setAccreditedInvestor(investor1, false);
        assertFalse(kycRegistry.isAccreditedInvestor(investor1));

        vm.stopPrank();
    }

    function testCannotSetAccreditedInvestorWithoutRole() public {
        vm.startPrank(nonAccredited);

        vm.expectRevert();
        kycRegistry.setAccreditedInvestor(investor1, true);

        vm.stopPrank();
    }

    function testUpdateFees() public {
        vm.startPrank(admin);

        handler.updateMarketplaceFee(300); // 3%
        handler.updateStakingFee(150); // 1.5%

        vm.stopPrank();
    }

    function testCannotSetInvalidFees() public {
        vm.startPrank(admin);

        vm.expectRevert(PropertyTokenHandler.InvalidFeeAmount.selector);
        handler.updateMarketplaceFee(1001); // > 10%

        vm.expectRevert(PropertyTokenHandler.InvalidFeeAmount.selector);
        handler.updateStakingFee(1001); // > 10%

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);

        handler.pause();
        // Try operations while paused - they should fail

        handler.unpause();
        // Operations should work again

        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        vm.startPrank(admin);

        // Mint additional tokens to admin for this test
        paymentToken.mint(admin, 1000 * 10**18);

        // Send some tokens to the contract
        paymentToken.transfer(address(handler), 1000 * 10**18);

        uint256 balanceBefore = paymentToken.balanceOf(admin);
        handler.emergencyWithdraw(address(paymentToken), 1000 * 10**18);

        assertEq(paymentToken.balanceOf(admin), balanceBefore + 1000 * 10**18);

        vm.stopPrank();
    }

    // ========== HELPER FUNCTIONS ==========

    function _setupTokensForInvestor(address investor, uint256 amount) internal {
        // Configure sale - price per token in HBAR, min/max in base units
        vm.prank(operator);
        handler.configureSale(1 * 10**18, 1, type(uint256).max, type(uint256).max);

        // Set as accredited and purchase tokens
        vm.prank(admin);
        kycRegistry.setAccreditedInvestor(investor, true);

        vm.startPrank(investor);
        // Convert amount from wei to base units: amount / 10**18
        uint256 tokenAmountBaseUnits = amount / 10**18;
        // Calculate total payment needed: baseUnits * pricePerToken
        uint256 totalPayment = tokenAmountBaseUnits * (1 * 10**18);
        paymentToken.approve(address(handler), totalPayment);
        handler.purchaseTokens(tokenAmountBaseUnits);
        vm.stopPrank();
    }
}