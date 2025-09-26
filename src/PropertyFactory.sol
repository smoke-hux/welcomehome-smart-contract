// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SecureWelcomeHomeProperty.sol";
import "./PropertyTokenHandler.sol";
import "./interfaces/IPropertyToken.sol";
import "./MockKYCRegistry.sol";
import "./OwnershipRegistry.sol";

/// @title PropertyFactory
/// @notice Factory contract for deploying and managing multiple tokenized properties
/// @dev Creates and tracks property tokens and their handlers for the Welcome Home platform
contract PropertyFactory is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant PROPERTY_CREATOR_ROLE = keccak256("PROPERTY_CREATOR_ROLE");
    bytes32 public constant PROPERTY_MANAGER_ROLE = keccak256("PROPERTY_MANAGER_ROLE");

    struct PropertyInfo {
        address tokenContract;
        address handlerContract;
        string name;
        string symbol;
        string ipfsHash;
        uint256 totalValue;
        uint256 maxTokens;
        address creator;
        uint256 createdAt;
        bool isActive;
        PropertyType propertyType;
        string location;
    }

    enum PropertyType { RESIDENTIAL, COMMERCIAL, INDUSTRIAL, MIXED_USE, LAND }

    struct PropertyDeploymentParams {
        string name;
        string symbol;
        string ipfsHash;
        uint256 totalValue;
        uint256 maxTokens;
        PropertyType propertyType;
        string location;
        address paymentToken;
    }

    mapping(uint256 => PropertyInfo) public properties;
    mapping(address => uint256[]) public creatorProperties;
    mapping(address => bool) public verifiedProperties;

    uint256 public propertyCount;
    uint256 public constant MAX_PROPERTIES = 1000;
    uint256 public propertyCreationFee = 1 ether; // 1 HBAR
    address public feeCollector;
    MockKYCRegistry public immutable kycRegistry;
    OwnershipRegistry public immutable ownershipRegistry;

    event PropertyDeployed(
        uint256 indexed propertyId,
        address indexed tokenContract,
        address indexed handlerContract,
        string name,
        address creator
    );

    event PropertyUpdated(
        uint256 indexed propertyId,
        string ipfsHash,
        uint256 totalValue,
        bool isActive
    );

    event PropertyVerified(uint256 indexed propertyId, bool verified);
    event PropertyCreationFeeUpdated(uint256 oldFee, uint256 newFee);

    error MaxPropertiesReached();
    error PropertyNotFound();
    error PropertyAlreadyVerified();
    error InsufficientFee();
    error InvalidPropertyData();
    error ZeroAddress();
    error UnauthorizedAccess();

    modifier validPropertyId(uint256 propertyId) {
        if (propertyId >= propertyCount) revert PropertyNotFound();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    constructor(address _feeCollector, address _kycRegistry, address _ownershipRegistry)
        validAddress(_feeCollector)
        validAddress(_kycRegistry)
        validAddress(_ownershipRegistry)
    {
        feeCollector = _feeCollector;
        kycRegistry = MockKYCRegistry(_kycRegistry);
        ownershipRegistry = OwnershipRegistry(_ownershipRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPERTY_CREATOR_ROLE, msg.sender);
        _grantRole(PROPERTY_MANAGER_ROLE, msg.sender);
    }

    function deployProperty(PropertyDeploymentParams memory params)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyRole(PROPERTY_CREATOR_ROLE)
        returns (uint256 propertyId)
    {
        if (propertyCount >= MAX_PROPERTIES) revert MaxPropertiesReached();
        if (msg.value < propertyCreationFee) revert InsufficientFee();
        if (bytes(params.name).length == 0 || bytes(params.symbol).length == 0) revert InvalidPropertyData();
        if (params.totalValue == 0 || params.maxTokens == 0) revert InvalidPropertyData();

        // Deploy property token contract
        SecureWelcomeHomeProperty propertyToken = new SecureWelcomeHomeProperty(params.name, params.symbol);

        // Deploy property token handler
        PropertyTokenHandler tokenHandler = new PropertyTokenHandler(
            address(propertyToken),
            params.paymentToken,
            feeCollector,
            address(kycRegistry),
            address(ownershipRegistry),
            propertyId
        );

        // Grant necessary roles to the token handler
        propertyToken.grantRole(propertyToken.MINTER_ROLE(), address(tokenHandler));
        propertyToken.grantRole(propertyToken.PROPERTY_MANAGER_ROLE(), address(tokenHandler));

        // Grant DEFAULT_ADMIN_ROLE back to the caller for property management
        propertyToken.grantRole(0x00, msg.sender); // DEFAULT_ADMIN_ROLE

        // Grant property creator OPERATOR_ROLE on the PropertyTokenHandler to configure sales
        tokenHandler.grantRole(tokenHandler.OPERATOR_ROLE(), msg.sender);

        // Grant property creator REVENUE_MANAGER_ROLE on the PropertyTokenHandler to distribute revenue
        tokenHandler.grantRole(tokenHandler.REVENUE_MANAGER_ROLE(), msg.sender);

        // Grant PropertyTokenHandler the role to update ownership registry
        ownershipRegistry.grantRole(ownershipRegistry.PROPERTY_UPDATER_ROLE(), address(tokenHandler));

        // Initialize property token
        propertyToken.connectToProperty(address(this), string(abi.encodePacked("PROP-", propertyCount)));
        propertyToken.setMaxTokens(params.maxTokens);

        propertyId = propertyCount++;

        // Store property information
        properties[propertyId] = PropertyInfo({
            tokenContract: address(propertyToken),
            handlerContract: address(tokenHandler),
            name: params.name,
            symbol: params.symbol,
            ipfsHash: params.ipfsHash,
            totalValue: params.totalValue,
            maxTokens: params.maxTokens,
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true,
            propertyType: params.propertyType,
            location: params.location
        });

        // Track properties by creator
        creatorProperties[msg.sender].push(propertyId);

        // Register property with ownership registry
        ownershipRegistry.registerProperty(
            propertyId,
            address(propertyToken),
            address(tokenHandler)
        );

        // Transfer creation fee
        payable(feeCollector).transfer(msg.value);

        emit PropertyDeployed(
            propertyId,
            address(propertyToken),
            address(tokenHandler),
            params.name,
            msg.sender
        );
    }

    function updateProperty(
        uint256 propertyId,
        string memory _ipfsHash,
        uint256 _totalValue
    )
        external
        validPropertyId(propertyId)
        onlyRole(PROPERTY_MANAGER_ROLE)
    {
        PropertyInfo storage property = properties[propertyId];

        if (bytes(_ipfsHash).length > 0) {
            property.ipfsHash = _ipfsHash;
        }

        if (_totalValue > 0) {
            property.totalValue = _totalValue;
        }

        emit PropertyUpdated(propertyId, property.ipfsHash, property.totalValue, property.isActive);
    }

    function setPropertyStatus(
        uint256 propertyId,
        bool _isActive
    )
        external
        validPropertyId(propertyId)
        onlyRole(PROPERTY_MANAGER_ROLE)
    {
        properties[propertyId].isActive = _isActive;
        emit PropertyUpdated(propertyId, properties[propertyId].ipfsHash, properties[propertyId].totalValue, _isActive);
    }

    function verifyProperty(
        uint256 propertyId
    )
        external
        validPropertyId(propertyId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address tokenContract = properties[propertyId].tokenContract;

        if (verifiedProperties[tokenContract]) revert PropertyAlreadyVerified();

        verifiedProperties[tokenContract] = true;

        emit PropertyVerified(propertyId, true);
    }

    function getProperty(uint256 propertyId)
        external
        view
        validPropertyId(propertyId)
        returns (PropertyInfo memory)
    {
        return properties[propertyId];
    }

    function getPropertyList(uint256 offset, uint256 limit)
        external
        view
        returns (PropertyInfo[] memory propertyList)
    {
        uint256 end = offset + limit;
        if (end > propertyCount) {
            end = propertyCount;
        }

        propertyList = new PropertyInfo[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            propertyList[i - offset] = properties[i];
        }
    }

    function getActiveProperties()
        external
        view
        returns (PropertyInfo[] memory activeProperties)
    {
        uint256 activeCount = 0;

        // Count active properties
        for (uint256 i = 0; i < propertyCount; i++) {
            if (properties[i].isActive) {
                activeCount++;
            }
        }

        activeProperties = new PropertyInfo[](activeCount);
        uint256 index = 0;

        // Populate active properties array
        for (uint256 i = 0; i < propertyCount; i++) {
            if (properties[i].isActive) {
                activeProperties[index] = properties[i];
                index++;
            }
        }
    }

    function getCreatorProperties(address creator)
        external
        view
        returns (uint256[] memory)
    {
        return creatorProperties[creator];
    }

    function isPropertyVerified(address tokenContract)
        external
        view
        returns (bool)
    {
        return verifiedProperties[tokenContract];
    }

    function getPropertyByTokenContract(address tokenContract)
        external
        view
        returns (PropertyInfo memory)
    {
        for (uint256 i = 0; i < propertyCount; i++) {
            if (properties[i].tokenContract == tokenContract) {
                return properties[i];
            }
        }
        revert PropertyNotFound();
    }

    function setPropertyCreationFee(uint256 _newFee)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 oldFee = propertyCreationFee;
        propertyCreationFee = _newFee;

        emit PropertyCreationFeeUpdated(oldFee, _newFee);
    }

    function setFeeCollector(address _newFeeCollector)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(_newFeeCollector)
    {
        feeCollector = _newFeeCollector;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function emergencyWithdraw()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        payable(msg.sender).transfer(address(this).balance);
    }

    function getFactoryStats() external view returns (
        uint256 totalProperties,
        uint256 totalActiveProperties,
        uint256 creationFee
    ) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < propertyCount; i++) {
            if (properties[i].isActive) {
                activeCount++;
            }
        }

        return (propertyCount, activeCount, propertyCreationFee);
    }

    function getPropertySummary(uint256 propertyId) external view validPropertyId(propertyId) returns (
        string memory name,
        string memory location,
        uint256 totalValue,
        uint256 maxTokens,
        address creator,
        bool isActive,
        bool isVerified
    ) {
        PropertyInfo memory prop = properties[propertyId];
        return (
            prop.name,
            prop.location,
            prop.totalValue,
            prop.maxTokens,
            prop.creator,
            prop.isActive,
            verifiedProperties[prop.tokenContract]
        );
    }

    function getAllPropertiesPaginated(uint256 offset, uint256 limit) external view returns (
        PropertyInfo[] memory propertyList,
        uint256 totalCount
    ) {
        uint256 end = offset + limit;
        if (end > propertyCount) {
            end = propertyCount;
        }

        propertyList = new PropertyInfo[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            propertyList[i - offset] = properties[i];
        }

        return (propertyList, propertyCount);
    }

    function getUserCreatedProperties(address user) external view returns (
        uint256[] memory propertyIds,
        PropertyInfo[] memory propertyDetails
    ) {
        uint256[] memory userPropIds = creatorProperties[user];
        PropertyInfo[] memory details = new PropertyInfo[](userPropIds.length);

        for (uint256 i = 0; i < userPropIds.length; i++) {
            details[i] = properties[userPropIds[i]];
        }

        return (userPropIds, details);
    }

    receive() external payable {}
}