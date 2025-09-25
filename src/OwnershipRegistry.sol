// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title OwnershipRegistry
/// @notice Centralized registry for tracking property token ownership across all properties
/// @dev Maps user addresses to token holdings and provides queryable ownership data
contract OwnershipRegistry is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");
    bytes32 public constant PROPERTY_UPDATER_ROLE = keccak256("PROPERTY_UPDATER_ROLE");

    struct OwnershipRecord {
        address tokenContract;
        uint256 propertyId;
        uint256 balance;
        uint256 lastUpdated;
        bool isActive;
    }

    struct UserPortfolio {
        uint256[] propertyIds;
        uint256 totalProperties;
        uint256 totalTokens;
        uint256 totalValue; // Estimated value in payment token
        uint256 lastUpdated;
    }

    struct PropertyStats {
        address tokenContract;
        address handlerContract;
        uint256 totalHolders;
        uint256 totalTokensIssued;
        uint256 totalValue;
        uint256 lastUpdated;
        bool isActive;
    }

    // Mappings for ownership tracking
    mapping(address => mapping(uint256 => OwnershipRecord)) public userOwnership; // user => propertyId => record
    mapping(address => UserPortfolio) public userPortfolios;
    mapping(uint256 => PropertyStats) public propertyStats;
    mapping(uint256 => address[]) public propertyHolders; // propertyId => holders array
    mapping(address => uint256[]) public userProperties; // user => propertyIds array

    // Global statistics
    uint256 public totalProperties;
    uint256 public totalUsers;
    uint256 public totalTokensGlobal;

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

    error PropertyNotRegistered();
    error InvalidPropertyData();
    error UnauthorizedUpdate();
    error ZeroAddress();
    error InvalidAmount();

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount();
        _;
    }

    modifier registeredProperty(uint256 propertyId) {
        if (!propertyStats[propertyId].isActive) revert PropertyNotRegistered();
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_MANAGER_ROLE, msg.sender);
        _grantRole(PROPERTY_UPDATER_ROLE, msg.sender);
    }

    /// @notice Register a new property in the ownership registry
    function registerProperty(
        uint256 propertyId,
        address tokenContract,
        address handlerContract
    )
        external
        onlyRole(REGISTRY_MANAGER_ROLE)
        validAddress(tokenContract)
        validAddress(handlerContract)
    {
        if (propertyStats[propertyId].isActive) revert InvalidPropertyData();

        propertyStats[propertyId] = PropertyStats({
            tokenContract: tokenContract,
            handlerContract: handlerContract,
            totalHolders: 0,
            totalTokensIssued: 0,
            totalValue: 0,
            lastUpdated: block.timestamp,
            isActive: true
        });

        totalProperties++;

        emit PropertyRegistered(propertyId, tokenContract, handlerContract);
    }

    /// @notice Update user ownership when tokens are transferred
    function updateOwnership(
        address user,
        uint256 propertyId,
        uint256 newBalance
    )
        external
        onlyRole(PROPERTY_UPDATER_ROLE)
        registeredProperty(propertyId)
        validAddress(user)
        whenNotPaused
    {
        uint256 oldBalance = userOwnership[user][propertyId].balance;
        address tokenContract = propertyStats[propertyId].tokenContract;

        // Update ownership record
        userOwnership[user][propertyId] = OwnershipRecord({
            tokenContract: tokenContract,
            propertyId: propertyId,
            balance: newBalance,
            lastUpdated: block.timestamp,
            isActive: newBalance > 0
        });

        // Update property holders list
        if (oldBalance == 0 && newBalance > 0) {
            // New holder
            propertyHolders[propertyId].push(user);
            userProperties[user].push(propertyId);
            propertyStats[propertyId].totalHolders++;

            if (userPortfolios[user].totalProperties == 0) {
                totalUsers++;
            }
        } else if (oldBalance > 0 && newBalance == 0) {
            // Holder selling all tokens
            _removeFromHoldersList(propertyId, user);
            _removeFromUserProperties(user, propertyId);
            propertyStats[propertyId].totalHolders--;
        }

        // Update property stats
        propertyStats[propertyId].totalTokensIssued = propertyStats[propertyId].totalTokensIssued - oldBalance + newBalance;
        propertyStats[propertyId].lastUpdated = block.timestamp;

        // Update user portfolio
        _updateUserPortfolio(user);

        emit OwnershipUpdated(user, propertyId, tokenContract, newBalance, oldBalance);
    }

    /// @notice Get user's ownership record for a specific property
    function getUserOwnership(address user, uint256 propertyId)
        external
        view
        returns (OwnershipRecord memory)
    {
        return userOwnership[user][propertyId];
    }

    /// @notice Get user's complete portfolio
    function getUserPortfolio(address user)
        external
        view
        returns (UserPortfolio memory)
    {
        return userPortfolios[user];
    }

    /// @notice Get all properties owned by a user
    function getUserProperties(address user)
        external
        view
        returns (uint256[] memory)
    {
        return userProperties[user];
    }

    /// @notice Get all holders of a specific property
    function getPropertyHolders(uint256 propertyId)
        external
        view
        returns (address[] memory)
    {
        return propertyHolders[propertyId];
    }

    /// @notice Get property statistics
    function getPropertyStats(uint256 propertyId)
        external
        view
        returns (PropertyStats memory)
    {
        return propertyStats[propertyId];
    }

    /// @notice Get global registry statistics
    function getGlobalStats()
        external
        view
        returns (
            uint256 _totalProperties,
            uint256 _totalUsers,
            uint256 _totalTokens
        )
    {
        return (totalProperties, totalUsers, totalTokensGlobal);
    }

    /// @notice Check if user owns tokens in a specific property
    function ownsProperty(address user, uint256 propertyId)
        external
        view
        returns (bool)
    {
        return userOwnership[user][propertyId].balance > 0;
    }

    /// @notice Get user's token balance for a specific property
    function getUserBalance(address user, uint256 propertyId)
        external
        view
        returns (uint256)
    {
        return userOwnership[user][propertyId].balance;
    }

    /// @notice Update property value estimation
    function updatePropertyValue(uint256 propertyId, uint256 newValue)
        external
        onlyRole(REGISTRY_MANAGER_ROLE)
        registeredProperty(propertyId)
    {
        propertyStats[propertyId].totalValue = newValue;
        propertyStats[propertyId].lastUpdated = block.timestamp;
    }

    /// @notice Deactivate a property (for emergency use)
    function deactivateProperty(uint256 propertyId)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        propertyStats[propertyId].isActive = false;
        propertyStats[propertyId].lastUpdated = block.timestamp;
    }

    /// @notice Internal function to update user portfolio summary
    function _updateUserPortfolio(address user) internal {
        uint256[] memory properties = userProperties[user];
        uint256 totalTokens = 0;
        uint256 totalValue = 0;
        uint256 activeProperties = 0;

        for (uint256 i = 0; i < properties.length; i++) {
            uint256 propertyId = properties[i];
            uint256 balance = userOwnership[user][propertyId].balance;

            if (balance > 0) {
                activeProperties++;
                totalTokens += balance;
                totalValue += (balance * propertyStats[propertyId].totalValue) / propertyStats[propertyId].totalTokensIssued;
            }
        }

        userPortfolios[user] = UserPortfolio({
            propertyIds: properties,
            totalProperties: activeProperties,
            totalTokens: totalTokens,
            totalValue: totalValue,
            lastUpdated: block.timestamp
        });

        emit UserPortfolioUpdated(user, activeProperties, totalTokens);
    }

    /// @notice Remove user from property holders list
    function _removeFromHoldersList(uint256 propertyId, address user) internal {
        address[] storage holders = propertyHolders[propertyId];
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == user) {
                holders[i] = holders[holders.length - 1];
                holders.pop();
                break;
            }
        }
    }

    /// @notice Remove property from user's properties list
    function _removeFromUserProperties(address user, uint256 propertyId) internal {
        uint256[] storage properties = userProperties[user];
        for (uint256 i = 0; i < properties.length; i++) {
            if (properties[i] == propertyId) {
                properties[i] = properties[properties.length - 1];
                properties.pop();
                break;
            }
        }
    }

    /// @notice Emergency pause function
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause function
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}