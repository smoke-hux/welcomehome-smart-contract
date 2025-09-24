// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SecureWelcomeHomeProperty
/// @notice Enhanced security version of property tokenization contract for Hedera
/// @dev Implements additional security measures including reentrancy protection, input validation, and event logging
/// @custom:security-contact security@welcomehome.com
contract SecureWelcomeHomeProperty is
    ERC20,
    ERC20Pausable,
    AccessControl,
    ERC20Permit,
    ERC20Votes,
    ReentrancyGuard
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PROPERTY_MANAGER_ROLE = keccak256("PROPERTY_MANAGER_ROLE");

    address public revaProperty;
    string public transactionID;
    uint256 public maxTokens;
    uint256 public mintedTokens;
    bool public propertyInitialized;

    uint256 private constant MAX_SUPPLY_LIMIT = 10**9 * 10**18; // 1 billion tokens max
    uint256 private constant MIN_MINT_AMOUNT = 1;

    mapping(address => uint256) private lastMintTimestamp;
    uint256 public constant MINT_COOLDOWN = 0; // No cooldown for now, can be updated later

    event PropertyConnected(address indexed propertyAddress, string transactionID, uint256 timestamp);
    event MaxTokensUpdated(uint256 previousMax, uint256 newMax, address indexed updatedBy);
    event TokensMinted(address indexed to, uint256 amount, address indexed mintedBy);
    event EmergencyPause(address indexed pausedBy, uint256 timestamp);
    event EmergencyUnpause(address indexed unpausedBy, uint256 timestamp);

    error InvalidPropertyAddress();
    error InvalidTransactionID();
    error InvalidMaxTokens();
    error MaxSupplyExceeded();
    error InsufficientTokensAvailable();
    error MintAmountTooSmall();
    error PropertyAlreadyInitialized();
    error PropertyNotInitialized();
    error MintCooldownNotMet();
    error ZeroAddress();
    error InvalidMintAmount();

    modifier onlyInitializedProperty() {
        if (!propertyInitialized) revert PropertyNotInitialized();
        _;
    }

    modifier validAddress(address _addr) {
        if (_addr == address(0)) revert ZeroAddress();
        _;
    }

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PROPERTY_MANAGER_ROLE, msg.sender);

        _setRoleAdmin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(PROPERTY_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function connectToProperty(
        address propertyAddress,
        string memory newTransactionID
    )
        public
        onlyRole(PROPERTY_MANAGER_ROLE)
        validAddress(propertyAddress)
    {
        if (propertyInitialized) revert PropertyAlreadyInitialized();
        if (bytes(newTransactionID).length == 0) revert InvalidTransactionID();

        revaProperty = propertyAddress;
        transactionID = newTransactionID;
        propertyInitialized = true;

        emit PropertyConnected(propertyAddress, newTransactionID, block.timestamp);
    }

    function setMaxTokens(uint256 newMax)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newMax == 0 || newMax > MAX_SUPPLY_LIMIT) revert InvalidMaxTokens();
        if (mintedTokens > newMax) revert MaxSupplyExceeded();

        uint256 previousMax = maxTokens;
        maxTokens = newMax;

        emit MaxTokensUpdated(previousMax, newMax, msg.sender);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }

    function mint(address to, uint256 amount)
        public
        onlyRole(MINTER_ROLE)
        onlyInitializedProperty
        nonReentrant
        validAddress(to)
        whenNotPaused
    {
        if (amount < MIN_MINT_AMOUNT) revert MintAmountTooSmall();
        if (amount == 0 || amount > MAX_SUPPLY_LIMIT) revert InvalidMintAmount();

        // Check mint cooldown for the minter (not the recipient)
        if (block.timestamp < lastMintTimestamp[msg.sender] + MINT_COOLDOWN) {
            revert MintCooldownNotMet();
        }

        if (maxTokens > 0) {
            if (mintedTokens + amount > maxTokens) {
                revert InsufficientTokensAvailable();
            }
        }

        mintedTokens += amount;
        lastMintTimestamp[msg.sender] = block.timestamp;

        _mint(to, amount);

        emit TokensMinted(to, amount, msg.sender);
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
        if (mintedTokens >= amount) {
            mintedTokens -= amount;
        }
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
        if (mintedTokens >= amount) {
            mintedTokens -= amount;
        }
    }

    function getRemainingTokens() public view returns (uint256) {
        if (maxTokens == 0) return type(uint256).max;
        return maxTokens > mintedTokens ? maxTokens - mintedTokens : 0;
    }

    function getMintCooldownRemaining(address minter) public view returns (uint256) {
        uint256 lastMint = lastMintTimestamp[minter];
        if (lastMint == 0) return 0;

        uint256 cooldownEnd = lastMint + MINT_COOLDOWN;
        if (block.timestamp >= cooldownEnd) return 0;

        return cooldownEnd - block.timestamp;
    }

    // Required overrides for multiple inheritance
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}