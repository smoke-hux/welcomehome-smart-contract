// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IPropertyToken {
    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getRemainingTokens() external view returns (uint256);
}

/// @title PropertyTokenHandler
/// @notice Handles token operations, marketplace functionality, and property investment management
/// @dev Manages token sales, transfers, staking, and property revenue distribution
contract PropertyTokenHandler is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REVENUE_MANAGER_ROLE = keccak256("REVENUE_MANAGER_ROLE");
    bytes32 public constant MARKETPLACE_MANAGER_ROLE = keccak256("MARKETPLACE_MANAGER_ROLE");

    IPropertyToken public immutable propertyToken;
    IERC20 public paymentToken; // HBAR or other payment token

    struct TokenSale {
        uint256 pricePerToken;
        uint256 minPurchase;
        uint256 maxPurchase;
        bool isActive;
        uint256 totalSold;
        uint256 maxSupply;
    }

    struct MarketplaceListing {
        address seller;
        uint256 amount;
        uint256 pricePerToken;
        uint256 listingTime;
        bool isActive;
    }

    struct StakingInfo {
        uint256 stakedAmount;
        uint256 stakeTime;
        uint256 lastRewardClaim;
        uint256 totalRewards;
    }

    struct PropertyRevenue {
        uint256 totalRevenue;
        uint256 distributedRevenue;
        uint256 revenuePerToken;
        uint256 lastDistribution;
    }

    TokenSale public currentSale;
    PropertyRevenue public propertyRevenue;

    mapping(uint256 => MarketplaceListing) public marketplaceListings;
    mapping(address => StakingInfo) public stakingInfo;
    mapping(address => uint256) public claimableRevenue;
    mapping(address => bool) public accreditedInvestors;

    uint256 public nextListingId;
    uint256 public constant STAKING_REWARD_RATE = 500; // 5% APY (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_STAKE_DURATION = 30 days;

    // Fees
    uint256 public marketplaceFee = 250; // 2.5% in basis points
    uint256 public stakingFee = 100; // 1% in basis points
    address public feeCollector;

    event TokensPurchased(address indexed buyer, uint256 amount, uint256 totalCost);
    event TokensListed(uint256 indexed listingId, address indexed seller, uint256 amount, uint256 pricePerToken);
    event TokensPurchasedFromMarketplace(uint256 indexed listingId, address indexed buyer, uint256 amount);
    event TokensStaked(address indexed staker, uint256 amount);
    event TokensUnstaked(address indexed staker, uint256 amount, uint256 rewards);
    event RevenueDistributed(uint256 totalRevenue, uint256 revenuePerToken);
    event RevenueClaimedByHolder(address indexed holder, uint256 amount);
    event SaleConfigured(uint256 pricePerToken, uint256 minPurchase, uint256 maxPurchase, uint256 maxSupply);
    event MarketplaceListingCancelled(uint256 indexed listingId);
    event AccreditedInvestorUpdated(address indexed investor, bool status);

    error TokenSaleNotActive();
    error InsufficientPayment();
    error PurchaseAmountTooLow();
    error PurchaseAmountTooHigh();
    error InsufficientTokenBalance();
    error ListingNotFound();
    error ListingNotActive();
    error NotListingSeller();
    error InvalidStakeAmount();
    error StakingPeriodNotMet();
    error NoRewardsAvailable();
    error NotAccreditedInvestor();
    error InvalidFeeAmount();
    error ZeroAmount();
    error InvalidAddress();

    modifier onlyAccredited() {
        if (!accreditedInvestors[msg.sender]) revert NotAccreditedInvestor();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    constructor(
        address _propertyToken,
        address _paymentToken,
        address _feeCollector
    ) validAddress(_propertyToken) validAddress(_paymentToken) validAddress(_feeCollector) {
        propertyToken = IPropertyToken(_propertyToken);
        paymentToken = IERC20(_paymentToken);
        feeCollector = _feeCollector;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        _grantRole(REVENUE_MANAGER_ROLE, msg.sender);
        _grantRole(MARKETPLACE_MANAGER_ROLE, msg.sender);
    }

    function configureSale(
        uint256 _pricePerToken,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _maxSupply
    ) external onlyRole(OPERATOR_ROLE) validAmount(_pricePerToken) {
        currentSale = TokenSale({
            pricePerToken: _pricePerToken,
            minPurchase: _minPurchase,
            maxPurchase: _maxPurchase,
            isActive: true,
            totalSold: 0,
            maxSupply: _maxSupply
        });

        emit SaleConfigured(_pricePerToken, _minPurchase, _maxPurchase, _maxSupply);
    }

    function purchaseTokens(uint256 tokenAmount)
        external
        nonReentrant
        whenNotPaused
        onlyAccredited
        validAmount(tokenAmount)
    {
        if (!currentSale.isActive) revert TokenSaleNotActive();
        if (tokenAmount < currentSale.minPurchase) revert PurchaseAmountTooLow();
        if (tokenAmount > currentSale.maxPurchase) revert PurchaseAmountTooHigh();

        uint256 totalCost = tokenAmount * currentSale.pricePerToken;
        if (paymentToken.balanceOf(msg.sender) < totalCost) revert InsufficientPayment();

        if (currentSale.maxSupply > 0 && currentSale.totalSold + tokenAmount > currentSale.maxSupply) {
            revert PurchaseAmountTooHigh();
        }

        paymentToken.safeTransferFrom(msg.sender, address(this), totalCost);
        propertyToken.mint(msg.sender, tokenAmount);

        currentSale.totalSold += tokenAmount;

        emit TokensPurchased(msg.sender, tokenAmount, totalCost);
    }

    function listTokensForSale(
        uint256 amount,
        uint256 pricePerToken
    ) external nonReentrant whenNotPaused validAmount(amount) validAmount(pricePerToken) {
        if (propertyToken.balanceOf(msg.sender) < amount) revert InsufficientTokenBalance();

        uint256 listingId = nextListingId++;
        marketplaceListings[listingId] = MarketplaceListing({
            seller: msg.sender,
            amount: amount,
            pricePerToken: pricePerToken,
            listingTime: block.timestamp,
            isActive: true
        });

        emit TokensListed(listingId, msg.sender, amount, pricePerToken);
    }

    function purchaseFromMarketplace(uint256 listingId, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        validAmount(amount)
    {
        MarketplaceListing storage listing = marketplaceListings[listingId];
        if (!listing.isActive) revert ListingNotActive();
        if (listing.amount < amount) revert PurchaseAmountTooHigh();

        uint256 totalCost = amount * listing.pricePerToken;
        uint256 fee = (totalCost * marketplaceFee) / BASIS_POINTS;
        uint256 sellerAmount = totalCost - fee;

        paymentToken.safeTransferFrom(msg.sender, listing.seller, sellerAmount);
        paymentToken.safeTransferFrom(msg.sender, feeCollector, fee);

        IERC20(address(propertyToken)).safeTransferFrom(listing.seller, msg.sender, amount);

        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.isActive = false;
        }

        emit TokensPurchasedFromMarketplace(listingId, msg.sender, amount);
    }

    function stakeTokens(uint256 amount) external nonReentrant whenNotPaused validAmount(amount) {
        if (propertyToken.balanceOf(msg.sender) < amount) revert InsufficientTokenBalance();

        StakingInfo storage stake = stakingInfo[msg.sender];

        if (stake.stakedAmount > 0) {
            uint256 pendingRewards = calculateStakingRewards(msg.sender);
            stake.totalRewards += pendingRewards;
        }

        IERC20(address(propertyToken)).safeTransferFrom(msg.sender, address(this), amount);

        stake.stakedAmount += amount;
        stake.stakeTime = block.timestamp;
        stake.lastRewardClaim = block.timestamp;

        emit TokensStaked(msg.sender, amount);
    }

    function unstakeTokens(uint256 amount) external nonReentrant validAmount(amount) {
        StakingInfo storage stake = stakingInfo[msg.sender];
        if (stake.stakedAmount < amount) revert InsufficientTokenBalance();
        if (block.timestamp < stake.stakeTime + MIN_STAKE_DURATION) revert StakingPeriodNotMet();

        uint256 rewards = calculateStakingRewards(msg.sender);
        uint256 fee = (rewards * stakingFee) / BASIS_POINTS;
        uint256 netRewards = rewards - fee;

        stake.stakedAmount -= amount;
        stake.totalRewards += netRewards;
        stake.lastRewardClaim = block.timestamp;

        IERC20(address(propertyToken)).safeTransfer(msg.sender, amount);

        if (netRewards > 0) {
            propertyToken.mint(msg.sender, netRewards);
            if (fee > 0) {
                propertyToken.mint(feeCollector, fee);
            }
        }

        emit TokensUnstaked(msg.sender, amount, netRewards);
    }

    function distributeRevenue(uint256 revenueAmount)
        external
        onlyRole(REVENUE_MANAGER_ROLE)
        validAmount(revenueAmount)
    {
        uint256 totalSupply = propertyToken.totalSupply();
        if (totalSupply == 0) return;

        uint256 revenuePerToken = revenueAmount / totalSupply;

        propertyRevenue.totalRevenue += revenueAmount;
        propertyRevenue.revenuePerToken += revenuePerToken;
        propertyRevenue.lastDistribution = block.timestamp;

        paymentToken.safeTransferFrom(msg.sender, address(this), revenueAmount);

        emit RevenueDistributed(revenueAmount, revenuePerToken);
    }

    function claimRevenue() external nonReentrant {
        uint256 balance = propertyToken.balanceOf(msg.sender);
        uint256 totalClaimable = (balance * propertyRevenue.revenuePerToken) - claimableRevenue[msg.sender];

        if (totalClaimable == 0) revert NoRewardsAvailable();

        claimableRevenue[msg.sender] += totalClaimable;
        paymentToken.safeTransfer(msg.sender, totalClaimable);

        emit RevenueClaimedByHolder(msg.sender, totalClaimable);
    }

    function calculateStakingRewards(address staker) public view returns (uint256) {
        StakingInfo memory stake = stakingInfo[staker];
        if (stake.stakedAmount == 0) return 0;

        uint256 timeStaked = block.timestamp - stake.lastRewardClaim;
        uint256 annualReward = (stake.stakedAmount * STAKING_REWARD_RATE) / BASIS_POINTS;
        return (annualReward * timeStaked) / 365 days;
    }

    function getClaimableRevenue(address holder) external view returns (uint256) {
        uint256 balance = propertyToken.balanceOf(holder);
        return (balance * propertyRevenue.revenuePerToken) - claimableRevenue[holder];
    }

    function setAccreditedInvestor(address investor, bool status)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(investor)
    {
        accreditedInvestors[investor] = status;
        emit AccreditedInvestorUpdated(investor, status);
    }

    function cancelListing(uint256 listingId) external {
        MarketplaceListing storage listing = marketplaceListings[listingId];
        if (listing.seller != msg.sender) revert NotListingSeller();

        listing.isActive = false;
        emit MarketplaceListingCancelled(listingId);
    }

    function updateMarketplaceFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > 1000) revert InvalidFeeAmount(); // Max 10%
        marketplaceFee = newFee;
    }

    function updateStakingFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > 1000) revert InvalidFeeAmount(); // Max 10%
        stakingFee = newFee;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function emergencyWithdraw(address token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(token)
    {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}