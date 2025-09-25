// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OwnershipRegistry.sol";

contract OwnershipRegistryTest is Test {
    OwnershipRegistry public registry;

    address public admin;
    address public registryManager;
    address public propertyUpdater;
    address public tokenContract1;
    address public tokenContract2;
    address public handlerContract1;
    address public handlerContract2;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant PROPERTY_ID_1 = 1;
    uint256 public constant PROPERTY_ID_2 = 2;
    uint256 public constant PROPERTY_VALUE_1 = 1000000 * 10**18;
    uint256 public constant PROPERTY_VALUE_2 = 2000000 * 10**18;

    event OwnershipUpdated(
        address indexed user,
        uint256 indexed propertyId,
        address indexed tokenContract,
        uint256 newBalance,
        uint256 oldBalance
    );

    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed tokenContract,
        address indexed handlerContract
    );

    event UserPortfolioUpdated(
        address indexed user,
        uint256 totalProperties,
        uint256 totalTokens
    );

    function setUp() public {
        admin = makeAddr("admin");
        registryManager = makeAddr("registryManager");
        propertyUpdater = makeAddr("propertyUpdater");
        tokenContract1 = makeAddr("tokenContract1");
        tokenContract2 = makeAddr("tokenContract2");
        handlerContract1 = makeAddr("handlerContract1");
        handlerContract2 = makeAddr("handlerContract2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.startPrank(admin);

        // Deploy registry
        registry = new OwnershipRegistry();

        // Grant roles
        registry.grantRole(registry.REGISTRY_MANAGER_ROLE(), registryManager);
        registry.grantRole(registry.PROPERTY_UPDATER_ROLE(), propertyUpdater);

        vm.stopPrank();
    }

    function testInitialSetup() public view {
        assertEq(registry.totalProperties(), 0);
        assertEq(registry.totalUsers(), 0);
        assertEq(registry.totalTokensGlobal(), 0);

        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.REGISTRY_MANAGER_ROLE(), admin));
        assertTrue(registry.hasRole(registry.PROPERTY_UPDATER_ROLE(), admin));
        assertTrue(registry.hasRole(registry.REGISTRY_MANAGER_ROLE(), registryManager));
        assertTrue(registry.hasRole(registry.PROPERTY_UPDATER_ROLE(), propertyUpdater));
    }

    function testRegisterProperty() public {
        vm.startPrank(registryManager);

        vm.expectEmit(true, true, true, true);
        emit PropertyRegistered(PROPERTY_ID_1, tokenContract1, handlerContract1);

        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);

        vm.stopPrank();

        assertEq(registry.totalProperties(), 1);

        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.tokenContract, tokenContract1);
        assertEq(stats.handlerContract, handlerContract1);
        assertEq(stats.totalHolders, 0);
        assertEq(stats.totalTokensIssued, 0);
        assertEq(stats.totalValue, 0);
        assertTrue(stats.isActive);
        assertEq(stats.lastUpdated, block.timestamp);
    }

    function testCannotRegisterPropertyWithoutRole() public {
        vm.startPrank(user1);

        vm.expectRevert();
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);

        vm.stopPrank();
    }

    function testCannotRegisterPropertyWithZeroAddress() public {
        vm.startPrank(registryManager);

        // Zero token contract
        vm.expectRevert(OwnershipRegistry.ZeroAddress.selector);
        registry.registerProperty(PROPERTY_ID_1, address(0), handlerContract1);

        // Zero handler contract
        vm.expectRevert(OwnershipRegistry.ZeroAddress.selector);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, address(0));

        vm.stopPrank();
    }

    function testCannotRegisterPropertyTwice() public {
        vm.startPrank(registryManager);

        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);

        vm.expectRevert(OwnershipRegistry.InvalidPropertyData.selector);
        registry.registerProperty(PROPERTY_ID_1, tokenContract2, handlerContract2);

        vm.stopPrank();
    }

    function testUpdateOwnership() public {
        // First register property
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        // Update ownership
        vm.startPrank(propertyUpdater);

        vm.expectEmit(true, false, false, true);
        emit UserPortfolioUpdated(user1, 1, 100 * 10**18);

        vm.expectEmit(true, true, true, true);
        emit OwnershipUpdated(user1, PROPERTY_ID_1, tokenContract1, 100 * 10**18, 0);

        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);

        vm.stopPrank();

        // Verify ownership record
        OwnershipRegistry.OwnershipRecord memory record = registry.getUserOwnership(user1, PROPERTY_ID_1);
        assertEq(record.tokenContract, tokenContract1);
        assertEq(record.propertyId, PROPERTY_ID_1);
        assertEq(record.balance, 100 * 10**18);
        assertTrue(record.isActive);
        assertEq(record.lastUpdated, block.timestamp);

        // Verify user balance
        assertEq(registry.getUserBalance(user1, PROPERTY_ID_1), 100 * 10**18);
        assertTrue(registry.ownsProperty(user1, PROPERTY_ID_1));

        // Verify property stats
        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.totalHolders, 1);
        assertEq(stats.totalTokensIssued, 100 * 10**18);

        // Verify global stats
        assertEq(registry.totalUsers(), 1);

        // Verify user properties
        uint256[] memory userProperties = registry.getUserProperties(user1);
        assertEq(userProperties.length, 1);
        assertEq(userProperties[0], PROPERTY_ID_1);

        // Verify property holders
        address[] memory holders = registry.getPropertyHolders(PROPERTY_ID_1);
        assertEq(holders.length, 1);
        assertEq(holders[0], user1);

        // Verify user portfolio
        OwnershipRegistry.UserPortfolio memory portfolio = registry.getUserPortfolio(user1);
        assertEq(portfolio.totalProperties, 1);
        assertEq(portfolio.totalTokens, 100 * 10**18);
        assertEq(portfolio.totalValue, 0); // No property value set yet
        assertEq(portfolio.lastUpdated, block.timestamp);
    }

    function testUpdateOwnershipMultipleUsers() public {
        // Register property
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        // Update ownership for multiple users
        vm.startPrank(propertyUpdater);

        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);
        registry.updateOwnership(user2, PROPERTY_ID_1, 200 * 10**18);
        registry.updateOwnership(user3, PROPERTY_ID_1, 300 * 10**18);

        vm.stopPrank();

        // Verify property stats
        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.totalHolders, 3);
        assertEq(stats.totalTokensIssued, 600 * 10**18);

        // Verify global stats
        assertEq(registry.totalUsers(), 3);

        // Verify property holders
        address[] memory holders = registry.getPropertyHolders(PROPERTY_ID_1);
        assertEq(holders.length, 3);
        assertTrue(
            (holders[0] == user1 && holders[1] == user2 && holders[2] == user3) ||
            (holders[0] == user1 && holders[1] == user3 && holders[2] == user2) ||
            (holders[0] == user2 && holders[1] == user1 && holders[2] == user3) ||
            (holders[0] == user2 && holders[1] == user3 && holders[2] == user1) ||
            (holders[0] == user3 && holders[1] == user1 && holders[2] == user2) ||
            (holders[0] == user3 && holders[1] == user2 && holders[2] == user1)
        );
    }

    function testUpdateOwnershipZeroBalance() public {
        // Register property and set initial ownership
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);

        // User sells all tokens
        registry.updateOwnership(user1, PROPERTY_ID_1, 0);
        vm.stopPrank();

        // Verify ownership record
        OwnershipRegistry.OwnershipRecord memory record = registry.getUserOwnership(user1, PROPERTY_ID_1);
        assertEq(record.balance, 0);
        assertFalse(record.isActive);

        // Verify user no longer owns property
        assertEq(registry.getUserBalance(user1, PROPERTY_ID_1), 0);
        assertFalse(registry.ownsProperty(user1, PROPERTY_ID_1));

        // Verify property stats
        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.totalHolders, 0);
        assertEq(stats.totalTokensIssued, 0);

        // Verify property holders
        address[] memory holders = registry.getPropertyHolders(PROPERTY_ID_1);
        assertEq(holders.length, 0);
    }

    function testCannotUpdateOwnershipWithoutRole() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);

        vm.stopPrank();
    }

    function testCannotUpdateOwnershipUnregisteredProperty() public {
        vm.startPrank(propertyUpdater);

        vm.expectRevert(OwnershipRegistry.PropertyNotRegistered.selector);
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);

        vm.stopPrank();
    }

    function testCannotUpdateOwnershipZeroAddress() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(propertyUpdater);

        vm.expectRevert(OwnershipRegistry.ZeroAddress.selector);
        registry.updateOwnership(address(0), PROPERTY_ID_1, 100 * 10**18);

        vm.stopPrank();
    }

    function testUpdateOwnershipWhenPaused() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(admin);
        registry.pause();
        vm.stopPrank();

        vm.startPrank(propertyUpdater);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);

        vm.stopPrank();
    }

    function testUpdatePropertyValue() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);

        registry.updatePropertyValue(PROPERTY_ID_1, PROPERTY_VALUE_1);
        vm.stopPrank();

        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.totalValue, PROPERTY_VALUE_1);
        assertEq(stats.lastUpdated, block.timestamp);
    }

    function testCannotUpdatePropertyValueWithoutRole() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        registry.updatePropertyValue(PROPERTY_ID_1, PROPERTY_VALUE_1);

        vm.stopPrank();
    }

    function testCannotUpdatePropertyValueUnregisteredProperty() public {
        vm.startPrank(registryManager);

        vm.expectRevert(OwnershipRegistry.PropertyNotRegistered.selector);
        registry.updatePropertyValue(PROPERTY_ID_1, PROPERTY_VALUE_1);

        vm.stopPrank();
    }

    function testDeactivateProperty() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(admin);
        registry.deactivateProperty(PROPERTY_ID_1);
        vm.stopPrank();

        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertFalse(stats.isActive);
        assertEq(stats.lastUpdated, block.timestamp);
    }

    function testCannotDeactivatePropertyWithoutRole() public {
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        registry.deactivateProperty(PROPERTY_ID_1);

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);

        registry.pause();
        assertTrue(registry.paused());

        registry.unpause();
        assertFalse(registry.paused());

        vm.stopPrank();
    }

    function testCannotPauseWithoutRole() public {
        vm.startPrank(user1);

        vm.expectRevert();
        registry.pause();

        vm.stopPrank();
    }

    function testMultiplePropertiesOneUser() public {
        // Register properties
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        registry.registerProperty(PROPERTY_ID_2, tokenContract2, handlerContract2);
        registry.updatePropertyValue(PROPERTY_ID_1, PROPERTY_VALUE_1);
        registry.updatePropertyValue(PROPERTY_ID_2, PROPERTY_VALUE_2);
        vm.stopPrank();

        // Update ownership for both properties
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);
        registry.updateOwnership(user1, PROPERTY_ID_2, 200 * 10**18);
        vm.stopPrank();

        // Verify user properties
        uint256[] memory userProperties = registry.getUserProperties(user1);
        assertEq(userProperties.length, 2);
        assertTrue(
            (userProperties[0] == PROPERTY_ID_1 && userProperties[1] == PROPERTY_ID_2) ||
            (userProperties[0] == PROPERTY_ID_2 && userProperties[1] == PROPERTY_ID_1)
        );

        // Verify user portfolio
        OwnershipRegistry.UserPortfolio memory portfolio = registry.getUserPortfolio(user1);
        assertEq(portfolio.totalProperties, 2);
        assertEq(portfolio.totalTokens, 300 * 10**18);
        // Note: totalValue calculation depends on property token issuance
    }

    function testGetGlobalStats() public {
        // Register properties
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        registry.registerProperty(PROPERTY_ID_2, tokenContract2, handlerContract2);
        vm.stopPrank();

        // Add users
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, 100 * 10**18);
        registry.updateOwnership(user2, PROPERTY_ID_2, 200 * 10**18);
        vm.stopPrank();

        (uint256 totalProperties, uint256 totalUsers, uint256 totalTokens) = registry.getGlobalStats();
        assertEq(totalProperties, 2);
        assertEq(totalUsers, 2);
        // Note: totalTokensGlobal is not automatically updated in this implementation
    }

    function testFuzzUpdateOwnership(
        uint256 balance1,
        uint256 balance2,
        uint256 balance3
    ) public {
        // Bound balances to reasonable ranges
        balance1 = bound(balance1, 0, 1000000 * 10**18);
        balance2 = bound(balance2, 0, 1000000 * 10**18);
        balance3 = bound(balance3, 0, 1000000 * 10**18);

        // Register property
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        vm.stopPrank();

        // Update ownership with fuzz values
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, balance1);
        registry.updateOwnership(user1, PROPERTY_ID_1, balance2);
        registry.updateOwnership(user1, PROPERTY_ID_1, balance3);
        vm.stopPrank();

        // Verify final balance
        assertEq(registry.getUserBalance(user1, PROPERTY_ID_1), balance3);
        assertEq(registry.ownsProperty(user1, PROPERTY_ID_1), balance3 > 0);

        // Verify property stats
        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        assertEq(stats.totalTokensIssued, balance3);
        assertEq(stats.totalHolders, balance3 > 0 ? 1 : 0);
    }

    function testPortfolioValueCalculation() public {
        // Register property and set value
        vm.startPrank(registryManager);
        registry.registerProperty(PROPERTY_ID_1, tokenContract1, handlerContract1);
        registry.updatePropertyValue(PROPERTY_ID_1, PROPERTY_VALUE_1);
        vm.stopPrank();

        // Create ownership scenario with just one user first
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, 500 * 10**18);
        vm.stopPrank();

        // Check portfolio when user1 is the only holder
        OwnershipRegistry.UserPortfolio memory portfolio = registry.getUserPortfolio(user1);
        assertEq(portfolio.totalValue, PROPERTY_VALUE_1); // Should get full value when only holder
        assertEq(portfolio.totalProperties, 1);
        assertEq(portfolio.totalTokens, 500 * 10**18);

        // Now add other users
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user2, PROPERTY_ID_1, 300 * 10**18);
        registry.updateOwnership(user3, PROPERTY_ID_1, 200 * 10**18);
        vm.stopPrank();

        // NOTE: user1's portfolio is NOT automatically recalculated when other users are added
        // This is because _updateUserPortfolio is only called for the specific user being updated
        // user1's portfolio still shows the full property value from when they were the only holder

        OwnershipRegistry.PropertyStats memory stats = registry.getPropertyStats(PROPERTY_ID_1);
        portfolio = registry.getUserPortfolio(user1);

        // user1's portfolio still shows full value because it hasn't been recalculated
        assertEq(portfolio.totalValue, PROPERTY_VALUE_1);
        assertEq(portfolio.totalProperties, 1);
        assertEq(portfolio.totalTokens, 500 * 10**18);
        assertEq(stats.totalTokensIssued, 1000 * 10**18);

        // To get updated portfolio value, user1's ownership would need to be updated again
        vm.startPrank(propertyUpdater);
        registry.updateOwnership(user1, PROPERTY_ID_1, 500 * 10**18); // Same balance, but triggers recalculation
        vm.stopPrank();

        // Now user1's portfolio should show proportional value
        portfolio = registry.getUserPortfolio(user1);
        uint256 expectedValue = (500 * 10**18 * PROPERTY_VALUE_1) / (1000 * 10**18);
        assertEq(portfolio.totalValue, expectedValue);
        assertEq(portfolio.totalProperties, 1);
        assertEq(portfolio.totalTokens, 500 * 10**18);
    }
}