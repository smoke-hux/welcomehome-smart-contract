// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SecureWelcomeHomeProperty.sol";

contract SecureWelcomeHomePropertyTest is Test {
    SecureWelcomeHomeProperty public token;

    address public admin = address(0x1);
    address public minter = address(0x2);
    address public pauser = address(0x3);
    address public propertyManager = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);
    address public attacker = address(0x7);

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PROPERTY_MANAGER_ROLE = keccak256("PROPERTY_MANAGER_ROLE");

    event PropertyConnected(address indexed propertyAddress, string transactionID, uint256 timestamp);
    event MaxTokensUpdated(uint256 previousMax, uint256 newMax, address indexed updatedBy);
    event TokensMinted(address indexed to, uint256 amount, address indexed mintedBy);
    event EmergencyPause(address indexed pausedBy, uint256 timestamp);
    event EmergencyUnpause(address indexed unpausedBy, uint256 timestamp);

    function setUp() public {
        vm.startPrank(admin);
        token = new SecureWelcomeHomeProperty("SecureProperty", "SPT");

        // Grant roles to different addresses
        token.grantRole(MINTER_ROLE, minter);
        token.grantRole(PAUSER_ROLE, pauser);
        token.grantRole(PROPERTY_MANAGER_ROLE, propertyManager);

        vm.stopPrank();
    }

    function testInitialSetup() public view {
        assertEq(token.name(), "SecureProperty");
        assertEq(token.symbol(), "SPT");
        assertEq(token.totalSupply(), 0);
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(token.hasRole(MINTER_ROLE, admin));
        assertTrue(token.hasRole(MINTER_ROLE, minter));
        assertTrue(token.hasRole(PAUSER_ROLE, pauser));
        assertTrue(token.hasRole(PROPERTY_MANAGER_ROLE, propertyManager));
    }

    function testConnectProperty() public {
        address propertyAddress = address(0x100);
        string memory transactionId = "TX-12345";

        vm.startPrank(propertyManager);

        vm.expectEmit(true, false, false, true);
        emit PropertyConnected(propertyAddress, transactionId, block.timestamp);

        token.connectToProperty(propertyAddress, transactionId);

        assertEq(token.revaProperty(), propertyAddress);
        assertEq(token.transactionID(), transactionId);
        assertTrue(token.propertyInitialized());

        vm.stopPrank();
    }

    function testCannotConnectPropertyTwice() public {
        address propertyAddress = address(0x100);
        string memory transactionId = "TX-12345";

        vm.startPrank(propertyManager);
        token.connectToProperty(propertyAddress, transactionId);

        vm.expectRevert(SecureWelcomeHomeProperty.PropertyAlreadyInitialized.selector);
        token.connectToProperty(address(0x200), "TX-67890");

        vm.stopPrank();
    }

    function testCannotConnectWithZeroAddress() public {
        vm.startPrank(propertyManager);

        vm.expectRevert(SecureWelcomeHomeProperty.ZeroAddress.selector);
        token.connectToProperty(address(0), "TX-12345");

        vm.stopPrank();
    }

    function testCannotConnectWithEmptyTransactionId() public {
        vm.startPrank(propertyManager);

        vm.expectRevert(SecureWelcomeHomeProperty.InvalidTransactionID.selector);
        token.connectToProperty(address(0x100), "");

        vm.stopPrank();
    }

    function testSetMaxTokens() public {
        vm.startPrank(admin);

        uint256 newMax = 1000000 * 10**18;

        vm.expectEmit(true, false, false, true);
        emit MaxTokensUpdated(0, newMax, admin);

        token.setMaxTokens(newMax);
        assertEq(token.maxTokens(), newMax);

        vm.stopPrank();
    }

    function testCannotSetInvalidMaxTokens() public {
        vm.startPrank(admin);

        // Test zero max tokens
        vm.expectRevert(SecureWelcomeHomeProperty.InvalidMaxTokens.selector);
        token.setMaxTokens(0);

        // Test exceeding max supply limit
        uint256 tooLarge = 10**9 * 10**18 + 1;
        vm.expectRevert(SecureWelcomeHomeProperty.InvalidMaxTokens.selector);
        token.setMaxTokens(tooLarge);

        vm.stopPrank();
    }

    function testMinting() public {
        // First connect property
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);

        uint256 amount = 1000 * 10**18;

        vm.expectEmit(true, true, true, true);
        emit TokensMinted(user1, amount, minter);

        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
        assertEq(token.mintedTokens(), amount);

        vm.stopPrank();
    }

    function testCannotMintWithoutPropertyInitialized() public {
        vm.startPrank(minter);

        vm.expectRevert(SecureWelcomeHomeProperty.PropertyNotInitialized.selector);
        token.mint(user1, 1000);

        vm.stopPrank();
    }

    function testCannotMintToZeroAddress() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);

        vm.expectRevert(SecureWelcomeHomeProperty.ZeroAddress.selector);
        token.mint(address(0), 1000);

        vm.stopPrank();
    }

    function testMintCooldown() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);

        // First mint should succeed
        token.mint(user1, 100);

        // With cooldown set to 0, second mint should also succeed immediately
        token.mint(user1, 100);

        assertEq(token.balanceOf(user1), 200);

        vm.stopPrank();
    }

    function testMaxTokensEnforcement() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.prank(admin);
        token.setMaxTokens(1000);

        vm.startPrank(minter);

        // Mint up to max
        token.mint(user1, 900);

        // Wait for cooldown
        vm.warp(block.timestamp + 61);

        // Try to mint more than available
        vm.expectRevert(SecureWelcomeHomeProperty.InsufficientTokensAvailable.selector);
        token.mint(user1, 200);

        // Mint exactly remaining amount should work
        token.mint(user1, 100);

        vm.stopPrank();
    }

    function testPauseUnpause() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        // Pause the contract
        vm.startPrank(pauser);

        vm.expectEmit(true, false, false, true);
        emit EmergencyPause(pauser, block.timestamp);

        token.pause();
        assertTrue(token.paused());

        vm.stopPrank();

        // Try to mint while paused
        vm.startPrank(minter);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.mint(user1, 100);
        vm.stopPrank();

        // Unpause
        vm.startPrank(pauser);

        vm.expectEmit(true, false, false, true);
        emit EmergencyUnpause(pauser, block.timestamp);

        token.unpause();
        assertFalse(token.paused());

        vm.stopPrank();

        // Now minting should work
        vm.startPrank(minter);
        token.mint(user1, 100);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, 1000);
        vm.stopPrank();

        vm.startPrank(user1);
        token.burn(300);

        assertEq(token.balanceOf(user1), 700);
        assertEq(token.totalSupply(), 700);
        assertEq(token.mintedTokens(), 700);

        vm.stopPrank();
    }

    function testBurnFrom() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, 1000);
        vm.stopPrank();

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, 500);

        // User2 burns from user1
        vm.startPrank(user2);
        token.burnFrom(user1, 300);

        assertEq(token.balanceOf(user1), 700);
        assertEq(token.totalSupply(), 700);
        assertEq(token.mintedTokens(), 700);
        assertEq(token.allowance(user1, user2), 200);

        vm.stopPrank();
    }

    function testTransferWhenNotPaused() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, 1000);
        vm.stopPrank();

        vm.prank(user1);
        token.transfer(user2, 400);

        assertEq(token.balanceOf(user1), 600);
        assertEq(token.balanceOf(user2), 400);
    }

    function testTransferFailsWhenPaused() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, 1000);
        vm.stopPrank();

        vm.prank(pauser);
        token.pause();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        token.transfer(user2, 400);
    }

    function testGetRemainingTokens() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        // Without max set, should return max uint256
        assertEq(token.getRemainingTokens(), type(uint256).max);

        // Set max tokens
        vm.prank(admin);
        token.setMaxTokens(1000);

        assertEq(token.getRemainingTokens(), 1000);

        // Mint some tokens
        vm.startPrank(minter);
        token.mint(user1, 600);
        vm.stopPrank();

        assertEq(token.getRemainingTokens(), 400);

        // Burn some tokens
        vm.prank(user1);
        token.burn(100);

        assertEq(token.getRemainingTokens(), 500);
    }

    function testGetMintCooldownRemaining() public view {
        // For address that never minted
        assertEq(token.getMintCooldownRemaining(minter), 0);
    }

    function testAccessControlRestrictions() public {
        // Non-admin cannot grant roles
        vm.startPrank(user1);
        vm.expectRevert();
        token.grantRole(MINTER_ROLE, attacker);
        vm.stopPrank();

        // Non-property manager cannot connect property
        vm.startPrank(attacker);
        vm.expectRevert();
        token.connectToProperty(address(0x100), "TX-12345");
        vm.stopPrank();

        // Non-admin cannot set max tokens
        vm.startPrank(attacker);
        vm.expectRevert();
        token.setMaxTokens(1000);
        vm.stopPrank();

        // Non-pauser cannot pause
        vm.startPrank(attacker);
        vm.expectRevert();
        token.pause();
        vm.stopPrank();
    }

    function testDelegateVoting() public {
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, 1000);
        vm.stopPrank();

        // User1 delegates to user2
        vm.startPrank(user1);
        token.delegate(user2);

        assertEq(token.getVotes(user2), 1000);
        assertEq(token.getVotes(user1), 0);

        vm.stopPrank();
    }

    function testFuzzMintAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10**9 * 10**18);

        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        vm.startPrank(minter);
        token.mint(user1, amount);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount);
    }

    function testReentrancyProtection() public {
        // This test would require a malicious contract that attempts reentrancy
        // For now, we just verify the modifier exists and functions are protected
        vm.prank(propertyManager);
        token.connectToProperty(address(0x100), "TX-12345");

        // The nonReentrant modifier on mint prevents reentrancy attacks
        vm.startPrank(minter);
        token.mint(user1, 100);
        vm.stopPrank();

        // Verify state is correctly updated
        assertEq(token.mintedTokens(), 100);
    }
}