// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MinimalPropertyFactory.sol";
import "../src/SecureWelcomeHomeProperty.sol";
import "../src/PropertyTokenHandler.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for payments
contract MockPaymentToken is ERC20 {
    constructor() ERC20("Mock HBAR", "HBAR") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MinimalPropertyFactoryTest is Test {
    MinimalPropertyFactory public factory;
    SecureWelcomeHomeProperty public mockToken;
    PropertyTokenHandler public mockHandler;
    MockPaymentToken public paymentToken;

    address public admin;
    address public creator;
    address public feeCollector;
    address public user;

    uint256 public constant DEFAULT_FEE = 1 ether;

    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed tokenContract,
        address indexed handlerContract,
        string name,
        address creator
    );

    event PropertyVerified(uint256 indexed propertyId, bool verified);
    event PropertyCreationFeeUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        admin = makeAddr("admin");
        creator = makeAddr("creator");
        feeCollector = makeAddr("feeCollector");
        user = makeAddr("user");

        vm.startPrank(admin);

        // Deploy factory
        factory = new MinimalPropertyFactory(feeCollector);

        // Deploy mock payment token
        paymentToken = new MockPaymentToken();

        // Deploy mock contracts for testing
        mockToken = new SecureWelcomeHomeProperty(
            "Test Property",
            "TEST"
        );

        mockHandler = new PropertyTokenHandler(
            address(mockToken),
            address(paymentToken),
            feeCollector
        );

        // Grant creator role
        factory.grantRole(factory.PROPERTY_CREATOR_ROLE(), creator);

        vm.stopPrank();

        // Give creator some ETH for fees
        vm.deal(creator, 10 ether);
        vm.deal(user, 10 ether);
    }

    function testInitialSetup() public view {
        assertEq(factory.propertyCount(), 0);
        assertEq(factory.propertyCreationFee(), DEFAULT_FEE);
        assertEq(factory.feeCollector(), feeCollector);
        assertEq(factory.MAX_PROPERTIES(), 1000);

        assertTrue(factory.hasRole(factory.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(factory.hasRole(factory.PROPERTY_CREATOR_ROLE(), admin));
        assertTrue(factory.hasRole(factory.PROPERTY_MANAGER_ROLE(), admin));
    }

    function testRegisterProperty() public {
        vm.startPrank(creator);

        vm.expectEmit(true, true, true, true);
        emit PropertyRegistered(
            0,
            address(mockToken),
            address(mockHandler),
            "Test Property",
            creator
        );

        uint256 propertyId = factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        vm.stopPrank();

        assertEq(propertyId, 0);
        assertEq(factory.propertyCount(), 1);

        MinimalPropertyFactory.PropertyInfo memory property = factory.getProperty(0);
        assertEq(property.tokenContract, address(mockToken));
        assertEq(property.handlerContract, address(mockHandler));
        assertEq(property.name, "Test Property");
        assertEq(property.symbol, "TEST");
        assertEq(property.ipfsHash, "QmTest123");
        assertEq(property.totalValue, 1000000 * 10**18);
        assertEq(property.maxTokens, 1000000 * 10**18);
        assertEq(property.creator, creator);
        assertEq(property.createdAt, block.timestamp);
        assertTrue(property.isActive);
        assertEq(uint256(property.propertyType), uint256(MinimalPropertyFactory.PropertyType.RESIDENTIAL));
        assertEq(property.location, "Test Location");

        uint256[] memory creatorProperties = factory.getCreatorProperties(creator);
        assertEq(creatorProperties.length, 1);
        assertEq(creatorProperties[0], 0);
    }

    function testCannotRegisterWithoutRole() public {
        vm.startPrank(user);

        vm.expectRevert();
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        vm.stopPrank();
    }

    function testCannotRegisterWithInsufficientFee() public {
        vm.startPrank(creator);

        vm.expectRevert(MinimalPropertyFactory.InsufficientFee.selector);
        factory.registerProperty{value: DEFAULT_FEE - 1}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        vm.stopPrank();
    }

    function testCannotRegisterWithZeroAddress() public {
        vm.startPrank(creator);

        // Zero token contract
        vm.expectRevert(MinimalPropertyFactory.ZeroAddress.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(0),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        // Zero handler contract
        vm.expectRevert(MinimalPropertyFactory.ZeroAddress.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(0),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidData() public {
        vm.startPrank(creator);

        // Empty name
        vm.expectRevert(MinimalPropertyFactory.InvalidPropertyData.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        // Empty symbol
        vm.expectRevert(MinimalPropertyFactory.InvalidPropertyData.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        // Zero total value
        vm.expectRevert(MinimalPropertyFactory.InvalidPropertyData.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            0,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        // Zero max tokens
        vm.expectRevert(MinimalPropertyFactory.InvalidPropertyData.selector);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            0,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );

        vm.stopPrank();
    }

    function testGetPropertyInvalidId() public {
        vm.expectRevert(MinimalPropertyFactory.PropertyNotFound.selector);
        factory.getProperty(0);
    }

    function testVerifyProperty() public {
        // First register a property
        vm.startPrank(creator);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );
        vm.stopPrank();

        // Verify it
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit PropertyVerified(0, true);

        factory.verifyProperty(0);

        assertTrue(factory.isPropertyVerified(address(mockToken)));

        vm.stopPrank();
    }

    function testCannotVerifyPropertyTwice() public {
        // Register and verify a property
        vm.startPrank(creator);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );
        vm.stopPrank();

        vm.startPrank(admin);
        factory.verifyProperty(0);

        // Try to verify again
        vm.expectRevert(MinimalPropertyFactory.PropertyAlreadyVerified.selector);
        factory.verifyProperty(0);

        vm.stopPrank();
    }

    function testCannotVerifyWithoutRole() public {
        // Register a property
        vm.startPrank(creator);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );
        vm.stopPrank();

        // Try to verify without admin role
        vm.startPrank(user);
        vm.expectRevert();
        factory.verifyProperty(0);
        vm.stopPrank();
    }

    function testSetPropertyCreationFee() public {
        vm.startPrank(admin);

        uint256 newFee = 2 ether;

        vm.expectEmit(false, false, false, true);
        emit PropertyCreationFeeUpdated(DEFAULT_FEE, newFee);

        factory.setPropertyCreationFee(newFee);

        assertEq(factory.propertyCreationFee(), newFee);

        vm.stopPrank();
    }

    function testCannotSetFeeWithoutRole() public {
        vm.startPrank(user);

        vm.expectRevert();
        factory.setPropertyCreationFee(2 ether);

        vm.stopPrank();
    }

    function testSetFeeCollector() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.startPrank(admin);

        factory.setFeeCollector(newFeeCollector);

        assertEq(factory.feeCollector(), newFeeCollector);

        vm.stopPrank();
    }

    function testCannotSetZeroFeeCollector() public {
        vm.startPrank(admin);

        vm.expectRevert(MinimalPropertyFactory.ZeroAddress.selector);
        factory.setFeeCollector(address(0));

        vm.stopPrank();
    }

    function testCannotSetFeeCollectorWithoutRole() public {
        address newFeeCollector = makeAddr("newFeeCollector");

        vm.startPrank(user);

        vm.expectRevert();
        factory.setFeeCollector(newFeeCollector);

        vm.stopPrank();
    }

    function testFeeCollectorReceivesPayment() public {
        uint256 balanceBefore = feeCollector.balance;

        vm.startPrank(creator);
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Test Property",
            "TEST",
            "QmTest123",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Test Location"
        );
        vm.stopPrank();

        assertEq(feeCollector.balance, balanceBefore + DEFAULT_FEE);
    }

    function testMultiplePropertiesSameCreator() public {
        vm.startPrank(creator);

        // Register first property
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Property 1",
            "PROP1",
            "QmTest1",
            1000000 * 10**18,
            1000000 * 10**18,
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            "Location 1"
        );

        // Register second property
        factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Property 2",
            "PROP2",
            "QmTest2",
            2000000 * 10**18,
            2000000 * 10**18,
            MinimalPropertyFactory.PropertyType.COMMERCIAL,
            "Location 2"
        );

        vm.stopPrank();

        uint256[] memory creatorProperties = factory.getCreatorProperties(creator);
        assertEq(creatorProperties.length, 2);
        assertEq(creatorProperties[0], 0);
        assertEq(creatorProperties[1], 1);

        assertEq(factory.propertyCount(), 2);
    }

    function testPropertyTypes() public {
        vm.startPrank(creator);

        // Test all property types
        MinimalPropertyFactory.PropertyType[5] memory types = [
            MinimalPropertyFactory.PropertyType.RESIDENTIAL,
            MinimalPropertyFactory.PropertyType.COMMERCIAL,
            MinimalPropertyFactory.PropertyType.INDUSTRIAL,
            MinimalPropertyFactory.PropertyType.MIXED_USE,
            MinimalPropertyFactory.PropertyType.LAND
        ];

        for (uint i = 0; i < types.length; i++) {
            factory.registerProperty{value: DEFAULT_FEE}(
                address(mockToken),
                address(mockHandler),
                string(abi.encodePacked("Property ", i)),
                string(abi.encodePacked("PROP", i)),
                string(abi.encodePacked("QmTest", i)),
                1000000 * 10**18,
                1000000 * 10**18,
                types[i],
                string(abi.encodePacked("Location ", i))
            );

            MinimalPropertyFactory.PropertyInfo memory property = factory.getProperty(i);
            assertEq(uint256(property.propertyType), uint256(types[i]));
        }

        vm.stopPrank();
    }

    function testReceiveFunction() public {
        // Test that contract can receive ETH
        vm.deal(user, 1 ether);

        vm.startPrank(user);
        (bool success, ) = address(factory).call{value: 1 ether}("");
        assertTrue(success);
        vm.stopPrank();

        assertEq(address(factory).balance, 1 ether);
    }

    function testFuzzRegisterProperty(
        uint256 totalValue,
        uint256 maxTokens,
        uint8 propertyTypeIndex
    ) public {
        // Bound inputs to valid ranges
        totalValue = bound(totalValue, 1, type(uint256).max);
        maxTokens = bound(maxTokens, 1, type(uint256).max);
        propertyTypeIndex = uint8(bound(propertyTypeIndex, 0, 4));

        MinimalPropertyFactory.PropertyType propertyType = MinimalPropertyFactory.PropertyType(propertyTypeIndex);

        vm.startPrank(creator);

        uint256 propertyId = factory.registerProperty{value: DEFAULT_FEE}(
            address(mockToken),
            address(mockHandler),
            "Fuzz Property",
            "FUZZ",
            "QmFuzz123",
            totalValue,
            maxTokens,
            propertyType,
            "Fuzz Location"
        );

        vm.stopPrank();

        MinimalPropertyFactory.PropertyInfo memory property = factory.getProperty(propertyId);
        assertEq(property.totalValue, totalValue);
        assertEq(property.maxTokens, maxTokens);
        assertEq(uint256(property.propertyType), uint256(propertyType));
    }
}