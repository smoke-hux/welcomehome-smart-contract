// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPropertyToken.sol";
import "./MockKYCRegistry.sol";
import "./OwnershipRegistry.sol";

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
    MockKYCRegistry public immutable kycRegistry;
    OwnershipRegistry public immutable ownershipRegistry;
    uint256 public immutable propertyId;

    struct TokenSale {
        uint256 pricePerToken;
        uint256 minPurchase;
        uint256 maxPurchase;
        bool isActive;
        uint256 totalSold;
        uint256 maxSupply;
        uint256 saleEndTime;
        uint256 propertyId;
    }

    struct MarketplaceListing {
        address seller;
        uint256 amount;
        uint256 pricePerToken;
        uint256 listingTime;
        bool isActive;
        uint256 propertyId;
        address tokenContract;
    }

    struct StakingInfo {
        uint256 stakedAmount;
        uint256 stakeTime;
        uint256 lastRewardClaim;
        uint256 totalRewards;
        uint256 propertyId;
    }

    struct PropertyRevenue {
        uint256 totalRevenue;
        uint256 distributedRevenue;
        uint256 revenuePerToken;
        uint256 lastDistribution;
        uint256 propertyId;
        address tokenContract;
    }

    // Single property per handler - simplified storage
    TokenSale public currentSale;
    PropertyRevenue public propertyRevenue;

    mapping(uint256 => MarketplaceListing) public marketplaceListings;
    mapping(address => StakingInfo) public stakingInfo;
    mapping(address => uint256) public claimableRevenue;

    uint256 public nextListingId;
    uint256 public constant STAKING_REWARD_RATE = 500; // 5% APY (in basis points)
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_STAKE_DURATION = 30 days;
    uint256 public constant PRECISION_MULTIPLIER = 1e18; // For revenue per token precision

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
        if (!kycRegistry.isAccreditedInvestor(msg.sender)) revert NotAccreditedInvestor();
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
        address _feeCollector,
        address _kycRegistry,
        address _ownershipRegistry,
        uint256 _propertyId
    ) validAddress(_propertyToken) validAddress(_paymentToken) validAddress(_feeCollector) validAddress(_kycRegistry) validAddress(_ownershipRegistry) {
        propertyToken = IPropertyToken(_propertyToken);
        paymentToken = IERC20(_paymentToken);
        feeCollector = _feeCollector;
        kycRegistry = MockKYCRegistry(_kycRegistry);
        ownershipRegistry = OwnershipRegistry(_ownershipRegistry);
        propertyId = _propertyId;

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
            maxSupply: _maxSupply,
            saleEndTime: 0,
            propertyId: 0
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
        propertyToken.mint(msg.sender, tokenAmount * 10**18);

        currentSale.totalSold += tokenAmount;

        // Update ownership registry
        ownershipRegistry.updateOwnership(msg.sender, propertyId, propertyToken.balanceOf(msg.sender));

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
            isActive: true,
            propertyId: 0, // Single property mode
            tokenContract: address(propertyToken)
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

        uint256 totalCost = (amount * listing.pricePerToken) / 1e18; // Normalize 18+18 decimals back to 18
        uint256 fee = (totalCost * marketplaceFee) / BASIS_POINTS;
        uint256 sellerAmount = totalCost - fee;

        paymentToken.safeTransferFrom(msg.sender, listing.seller, sellerAmount);
        paymentToken.safeTransferFrom(msg.sender, feeCollector, fee);

        IERC20(address(propertyToken)).safeTransferFrom(listing.seller, msg.sender, amount);

        // Update ownership registry for both seller and buyer
        ownershipRegistry.updateOwnership(listing.seller, propertyId, propertyToken.balanceOf(listing.seller));
        ownershipRegistry.updateOwnership(msg.sender, propertyId, propertyToken.balanceOf(msg.sender));

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

        // Use precision multiplier to avoid integer division precision loss
        uint256 revenuePerToken = (revenueAmount * PRECISION_MULTIPLIER) / totalSupply;

        propertyRevenue.totalRevenue += revenueAmount;
        propertyRevenue.revenuePerToken += revenuePerToken;
        propertyRevenue.lastDistribution = block.timestamp;

        paymentToken.safeTransferFrom(msg.sender, address(this), revenueAmount);

        emit RevenueDistributed(revenueAmount, revenuePerToken);
    }

    function claimRevenue() external nonReentrant {
        // Include both liquid tokens and staked tokens for revenue calculation
        uint256 liquidBalance = propertyToken.balanceOf(msg.sender);
        uint256 stakedBalance = stakingInfo[msg.sender].stakedAmount;
        uint256 totalBalance = liquidBalance + stakedBalance;

        // Calculate total revenue owed (scaled by precision)
        uint256 totalOwed = (totalBalance * propertyRevenue.revenuePerToken) / PRECISION_MULTIPLIER;
        uint256 alreadyClaimed = claimableRevenue[msg.sender];

        if (totalOwed <= alreadyClaimed) revert NoRewardsAvailable();

        uint256 claimable = totalOwed - alreadyClaimed;
        claimableRevenue[msg.sender] = totalOwed; // Update total claimed

        paymentToken.safeTransfer(msg.sender, claimable);

        emit RevenueClaimedByHolder(msg.sender, claimable);
    }

    function calculateStakingRewards(address staker) public view returns (uint256) {
        StakingInfo memory stake = stakingInfo[staker];
        if (stake.stakedAmount == 0) return 0;

        uint256 timeStaked = block.timestamp - stake.lastRewardClaim;
        uint256 annualReward = (stake.stakedAmount * STAKING_REWARD_RATE) / BASIS_POINTS;
        return (annualReward * timeStaked) / 365 days;
    }

    function getClaimableRevenue(address holder) external view returns (uint256) {
        // Include both liquid tokens and staked tokens for revenue calculation
        uint256 liquidBalance = propertyToken.balanceOf(holder);
        uint256 stakedBalance = stakingInfo[holder].stakedAmount;
        uint256 totalBalance = liquidBalance + stakedBalance;

        // Calculate total revenue owed (scaled by precision)
        uint256 totalOwed = (totalBalance * propertyRevenue.revenuePerToken) / PRECISION_MULTIPLIER;
        uint256 alreadyClaimed = claimableRevenue[holder];

        return totalOwed > alreadyClaimed ? totalOwed - alreadyClaimed : 0;
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

    // Frontend-ready getter functions

    function getTokenSaleInfo() external view returns (
        uint256 pricePerToken,
        uint256 minPurchase,
        uint256 maxPurchase,
        uint256 totalSold,
        uint256 maxSupply,
        bool isActive
    ) {
        return (
            currentSale.pricePerToken,
            currentSale.minPurchase,
            currentSale.maxPurchase,
            currentSale.totalSold,
            currentSale.maxSupply,
            currentSale.isActive
        );
    }

    function getUserStakingInfo(address user) external view returns (
        uint256 stakedAmount,
        uint256 stakeTime,
        uint256 lastRewardClaim,
        uint256 totalRewards,
        uint256 pendingRewards
    ) {
        StakingInfo memory stake = stakingInfo[user];
        return (
            stake.stakedAmount,
            stake.stakeTime,
            stake.lastRewardClaim,
            stake.totalRewards,
            calculateStakingRewards(user)
        );
    }

    function getMarketplaceListing(uint256 listingId) external view returns (
        address seller,
        uint256 amount,
        uint256 pricePerToken,
        uint256 listingTime,
        bool isActive
    ) {
        MarketplaceListing memory listing = marketplaceListings[listingId];
        return (
            listing.seller,
            listing.amount,
            listing.pricePerToken,
            listing.listingTime,
            listing.isActive
        );
    }

    function getPropertyInfo() external view returns (
        address tokenContract,
        address paymentTokenAddress,
        uint256 totalSupply,
        uint256 currentPropertyId
    ) {
        return (
            address(propertyToken),
            address(paymentToken),
            propertyToken.totalSupply(),
            propertyId
        );
    }

    function getUserTokenBalance(address user) external view returns (uint256) {
        return propertyToken.balanceOf(user);
    }

    function getContractStats() external view returns (
        uint256 totalTokensSold,
        uint256 totalRevenue,
        uint256 totalStaked,
        uint256 activeListings,
        uint256 nextListing
    ) {
        uint256 totalStakedAmount = 0;
        uint256 activeCount = 0;

        // Note: These would need to be tracked in state variables for gas efficiency in production
        for (uint256 i = 0; i < nextListingId; i++) {
            if (marketplaceListings[i].isActive) {
                activeCount++;
            }
        }

        return (
            currentSale.totalSold,
            propertyRevenue.totalRevenue,
            totalStakedAmount, // Simplified for now
            activeCount,
            nextListingId
        );
    }

    // Simplified to single property per handler - multi-property functions removed
}