// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./MockKYCRegistry.sol";
import "./OwnershipRegistry.sol";

/// @title MinimalPropertyFactory
/// @notice Lightweight factory for registering pre-deployed property contracts
/// @dev Size-optimized version that registers rather than deploys contracts
contract MinimalPropertyFactory is AccessControl, ReentrancyGuard, Pausable {
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

    MockKYCRegistry public kycRegistry;
    OwnershipRegistry public ownershipRegistry;
    address public feeCollector;

    uint256 public propertyCount;
    uint256 public constant MAX_PROPERTIES = 1000;
    uint256 public propertyCreationFee = 1 ether; // 1 HBAR

    event PropertyRegistered(uint256 indexed propertyId, address indexed tokenContract, address indexed handlerContract);
    event PropertyVerified(uint256 indexed propertyId, bool verified);
    event PropertyDeactivated(uint256 indexed propertyId);
    event FeeUpdated(uint256 oldFee, uint256 newFee);

    error MaxPropertiesReached();
    error InsufficientFee();
    error PropertyNotFound();
    error PropertyNotActive();
    error InvalidPropertyData();
    error PropertyAlreadyRegistered();
    error InvalidAddress();

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    modifier propertyExists(uint256 propertyId) {
        if (propertyId >= propertyCount) revert PropertyNotFound();
        _;
    }

    constructor(
        address _feeCollector,
        address _kycRegistry,
        address _ownershipRegistry
    ) validAddress(_feeCollector) validAddress(_kycRegistry) validAddress(_ownershipRegistry) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROPERTY_CREATOR_ROLE, msg.sender);
        _grantRole(PROPERTY_MANAGER_ROLE, msg.sender);

        feeCollector = _feeCollector;
        kycRegistry = MockKYCRegistry(_kycRegistry);
        ownershipRegistry = OwnershipRegistry(_ownershipRegistry);
    }

    /// @notice Register a pre-deployed property (size-optimized approach)
    function registerProperty(
        address tokenContract,
        address handlerContract,
        string calldata name,
        string calldata symbol,
        string calldata ipfsHash,
        uint256 totalValue,
        uint256 maxTokens,
        PropertyType propertyType,
        string calldata location
    ) external payable nonReentrant whenNotPaused onlyRole(PROPERTY_CREATOR_ROLE) returns (uint256 propertyId) {
        if (propertyCount >= MAX_PROPERTIES) revert MaxPropertiesReached();
        if (msg.value < propertyCreationFee) revert InsufficientFee();
        if (tokenContract == address(0) || handlerContract == address(0)) revert InvalidAddress();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidPropertyData();
        if (totalValue == 0 || maxTokens == 0) revert InvalidPropertyData();
        if (verifiedProperties[tokenContract]) revert PropertyAlreadyRegistered();

        propertyId = propertyCount;

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
        verifiedProperties[tokenContract] = true;
        propertyCount++;

        // Register with ownership registry
        ownershipRegistry.registerProperty(propertyId, tokenContract, handlerContract);

        // Transfer fee to collector
        payable(feeCollector).transfer(msg.value);

        emit PropertyRegistered(propertyId, tokenContract, handlerContract);
    }

    /// @notice Get property information
    function getProperty(uint256 propertyId) external view propertyExists(propertyId) returns (PropertyInfo memory) {
        return properties[propertyId];
    }

    /// @notice Get properties created by an address
    function getCreatorProperties(address creator) external view returns (uint256[] memory) {
        return creatorProperties[creator];
    }

    /// @notice Deactivate a property
    function deactivateProperty(uint256 propertyId)
        external
        propertyExists(propertyId)
        onlyRole(PROPERTY_MANAGER_ROLE)
    {
        properties[propertyId].isActive = false;
        emit PropertyDeactivated(propertyId);
    }

    /// @notice Update property creation fee
    function updatePropertyCreationFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = propertyCreationFee;
        propertyCreationFee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    /// @notice Emergency withdrawal function
    function emergencyWithdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Pause contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}