// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MinimalPropertyFactory
/// @notice Minimal factory contract for registering tokenized properties
/// @dev Lightweight version that uses external contract registration instead of deployment
contract MinimalPropertyFactory is AccessControl {
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

    mapping(uint256 => PropertyInfo) public properties;
    mapping(address => uint256[]) public creatorProperties;
    mapping(address => bool) public verifiedProperties;

    uint256 public propertyCount;
    uint256 public constant MAX_PROPERTIES = 1000;
    uint256 public propertyCreationFee = 1 ether;
    address public feeCollector;

    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed tokenContract,
        address indexed handlerContract,
        string name,
        address creator
    );

    event PropertyVerified(uint256 indexed propertyId, bool verified);
    event PropertyCreationFeeUpdated(uint256 oldFee, uint256 newFee);

    error MaxPropertiesReached();
    error PropertyNotFound();
    error PropertyAlreadyVerified();
    error InsufficientFee();
    error InvalidPropertyData();
    error ZeroAddress();

    modifier validPropertyId(uint256 propertyId) {
        if (propertyId >= propertyCount) revert PropertyNotFound();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    constructor(address _feeCollector) validAddress(_feeCollector) {
        feeCollector = _feeCollector;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPERTY_CREATOR_ROLE, msg.sender);
        _grantRole(PROPERTY_MANAGER_ROLE, msg.sender);
    }

    function registerProperty(
        address tokenContract,
        address handlerContract,
        string memory name,
        string memory symbol,
        string memory ipfsHash,
        uint256 totalValue,
        uint256 maxTokens,
        PropertyType propertyType,
        string memory location
    )
        external
        payable
        onlyRole(PROPERTY_CREATOR_ROLE)
        validAddress(tokenContract)
        validAddress(handlerContract)
        returns (uint256 propertyId)
    {
        if (propertyCount >= MAX_PROPERTIES) revert MaxPropertiesReached();
        if (msg.value < propertyCreationFee) revert InsufficientFee();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidPropertyData();
        if (totalValue == 0 || maxTokens == 0) revert InvalidPropertyData();

        propertyId = propertyCount++;

        properties[propertyId] = PropertyInfo({
            tokenContract: tokenContract,
            handlerContract: handlerContract,
            name: name,
            symbol: symbol,
            ipfsHash: ipfsHash,
            totalValue: totalValue,
            maxTokens: maxTokens,
            creator: msg.sender,
            createdAt: block.timestamp,
            isActive: true,
            propertyType: propertyType,
            location: location
        });

        creatorProperties[msg.sender].push(propertyId);
        payable(feeCollector).transfer(msg.value);

        emit PropertyRegistered(
            propertyId,
            tokenContract,
            handlerContract,
            name,
            msg.sender
        );
    }

    function getProperty(uint256 propertyId)
        external
        view
        validPropertyId(propertyId)
        returns (PropertyInfo memory)
    {
        return properties[propertyId];
    }

    function verifyProperty(uint256 propertyId)
        external
        validPropertyId(propertyId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address tokenContract = properties[propertyId].tokenContract;
        if (verifiedProperties[tokenContract]) revert PropertyAlreadyVerified();

        verifiedProperties[tokenContract] = true;
        emit PropertyVerified(propertyId, true);
    }

    function isPropertyVerified(address tokenContract)
        external
        view
        returns (bool)
    {
        return verifiedProperties[tokenContract];
    }

    function getCreatorProperties(address creator)
        external
        view
        returns (uint256[] memory)
    {
        return creatorProperties[creator];
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

    receive() external payable {}
}