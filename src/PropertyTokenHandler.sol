// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IPropertyToken.sol";

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

    struct PropertyMetrics {
        uint256 totalTokensSold;
        uint256 totalRevenue;
        uint256 averageTokenPrice;
        uint256 totalStaked;
        uint256 activeListings;
        uint256 lastUpdated;
    }

    // Multi-property support
    mapping(uint256 => TokenSale) public propertySales;
    mapping(uint256 => PropertyRevenue) public propertyRevenues;
    mapping(uint256 => PropertyMetrics) public propertyMetrics;
    mapping(uint256 => mapping(address => StakingInfo)) public propertyStaking; // propertyId => user => staking info
    mapping(uint256 => mapping(address => uint256)) public propertyClaimableRevenue; // propertyId => user => amount

    // Legacy support (backwards compatibility)
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
            maxSupply: _maxSupply,
            saleEndTime: 0,
            propertyId: 0
        });

        emit SaleConfigured(_pricePerToken, _minPurchase, _maxPurchase, _maxSupply);
    }

    function configureSaleForProperty(
        uint256 _propertyId,
        uint256 _pricePerToken,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _maxSupply,
        uint256 _saleEndTime
    ) external onlyRole(OPERATOR_ROLE) validAmount(_pricePerToken) {
        propertySales[_propertyId] = TokenSale({
            pricePerToken: _pricePerToken,
            minPurchase: _minPurchase,
            maxPurchase: _maxPurchase,
            isActive: true,
            totalSold: 0,
            maxSupply: _maxSupply,
            saleEndTime: _saleEndTime,
            propertyId: _propertyId
        });

        // Initialize property metrics if not exists
        if (propertyMetrics[_propertyId].lastUpdated == 0) {
            propertyMetrics[_propertyId] = PropertyMetrics({
                totalTokensSold: 0,
                totalRevenue: 0,
                averageTokenPrice: _pricePerToken,
                totalStaked: 0,
                activeListings: 0,
                lastUpdated: block.timestamp
            });
        }

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

    // Multi-Property Functions

    function purchaseTokensFromProperty(
        uint256 propertyId,
        address tokenContract,
        uint256 tokenAmount
    )
        external
        payable
        nonReentrant
        whenNotPaused
        onlyAccredited
        validAmount(tokenAmount)
    {
        TokenSale storage sale = propertySales[propertyId];
        if (!sale.isActive) revert TokenSaleNotActive();
        if (sale.saleEndTime > 0 && block.timestamp > sale.saleEndTime) revert TokenSaleNotActive();
        if (tokenAmount < sale.minPurchase) revert PurchaseAmountTooLow();
        if (tokenAmount > sale.maxPurchase) revert PurchaseAmountTooHigh();

        uint256 totalCost = tokenAmount * sale.pricePerToken;
        if (address(paymentToken) == address(0)) {
            // Native token payment (HBAR)
            if (msg.value < totalCost) revert InsufficientPayment();
        } else {
            if (paymentToken.balanceOf(msg.sender) < totalCost) revert InsufficientPayment();
            paymentToken.safeTransferFrom(msg.sender, address(this), totalCost);
        }

        if (sale.maxSupply > 0 && sale.totalSold + tokenAmount > sale.maxSupply) {
            revert PurchaseAmountTooHigh();
        }

        // Mint tokens from the specific property contract
        IPropertyToken(tokenContract).mint(msg.sender, tokenAmount);

        sale.totalSold += tokenAmount;
        _updatePropertyMetrics(propertyId, tokenAmount, totalCost, 0, 0);

        emit TokensPurchased(msg.sender, tokenAmount, totalCost);
    }

    function distributeRevenueForProperty(
        uint256 propertyId,
        address tokenContract,
        uint256 revenueAmount
    )
        external
        onlyRole(REVENUE_MANAGER_ROLE)
        validAmount(revenueAmount)
    {
        IPropertyToken tokenInstance = IPropertyToken(tokenContract);
        uint256 totalSupply = tokenInstance.totalSupply();
        if (totalSupply == 0) return;

        uint256 revenuePerToken = revenueAmount / totalSupply;

        PropertyRevenue storage revenue = propertyRevenues[propertyId];
        revenue.totalRevenue += revenueAmount;
        revenue.revenuePerToken += revenuePerToken;
        revenue.lastDistribution = block.timestamp;
        revenue.propertyId = propertyId;
        revenue.tokenContract = tokenContract;

        paymentToken.safeTransferFrom(msg.sender, address(this), revenueAmount);
        _updatePropertyMetrics(propertyId, 0, revenueAmount, 0, 0);

        emit RevenueDistributed(revenueAmount, revenuePerToken);
    }

    function claimRevenueForProperty(
        uint256 propertyId,
        address tokenContract
    ) external nonReentrant {
        IPropertyToken tokenInstance = IPropertyToken(tokenContract);
        uint256 balance = tokenInstance.balanceOf(msg.sender);
        PropertyRevenue storage revenue = propertyRevenues[propertyId];

        uint256 totalClaimable = (balance * revenue.revenuePerToken) - propertyClaimableRevenue[propertyId][msg.sender];

        if (totalClaimable == 0) revert NoRewardsAvailable();

        propertyClaimableRevenue[propertyId][msg.sender] += totalClaimable;
        paymentToken.safeTransfer(msg.sender, totalClaimable);

        emit RevenueClaimedByHolder(msg.sender, totalClaimable);
    }

    function stakeTokensForProperty(
        uint256 propertyId,
        address tokenContract,
        uint256 amount
    ) external nonReentrant whenNotPaused validAmount(amount) {
        IPropertyToken tokenInstance = IPropertyToken(tokenContract);
        if (tokenInstance.balanceOf(msg.sender) < amount) revert InsufficientTokenBalance();

        StakingInfo storage stake = propertyStaking[propertyId][msg.sender];

        if (stake.stakedAmount > 0) {
            uint256 pendingRewards = calculateStakingRewardsForProperty(propertyId, msg.sender);
            stake.totalRewards += pendingRewards;
        }

        IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), amount);

        stake.stakedAmount += amount;
        stake.stakeTime = block.timestamp;
        stake.lastRewardClaim = block.timestamp;
        stake.propertyId = propertyId;

        _updatePropertyMetrics(propertyId, 0, 0, int256(amount), 0);

        emit TokensStaked(msg.sender, amount);
    }

    function unstakeTokensForProperty(
        uint256 propertyId,
        address tokenContract,
        uint256 amount
    ) external nonReentrant validAmount(amount) {
        StakingInfo storage stake = propertyStaking[propertyId][msg.sender];
        if (stake.stakedAmount < amount) revert InsufficientTokenBalance();
        if (block.timestamp < stake.stakeTime + MIN_STAKE_DURATION) revert StakingPeriodNotMet();

        uint256 rewards = calculateStakingRewardsForProperty(propertyId, msg.sender);
        uint256 fee = (rewards * stakingFee) / BASIS_POINTS;
        uint256 netRewards = rewards - fee;

        stake.stakedAmount -= amount;
        stake.totalRewards += netRewards;
        stake.lastRewardClaim = block.timestamp;

        IERC20(tokenContract).safeTransfer(msg.sender, amount);

        if (netRewards > 0) {
            IPropertyToken(tokenContract).mint(msg.sender, netRewards);
            if (fee > 0) {
                IPropertyToken(tokenContract).mint(feeCollector, fee);
            }
        }

        _updatePropertyMetrics(propertyId, 0, 0, -int256(amount), 0);

        emit TokensUnstaked(msg.sender, amount, netRewards);
    }

    function calculateStakingRewardsForProperty(
        uint256 propertyId,
        address staker
    ) public view returns (uint256) {
        StakingInfo memory stake = propertyStaking[propertyId][staker];
        if (stake.stakedAmount == 0) return 0;

        uint256 timeStaked = block.timestamp - stake.lastRewardClaim;
        uint256 annualReward = (stake.stakedAmount * STAKING_REWARD_RATE) / BASIS_POINTS;
        return (annualReward * timeStaked) / 365 days;
    }

    function getPropertySale(uint256 propertyId)
        external
        view
        returns (TokenSale memory)
    {
        return propertySales[propertyId];
    }

    function getPropertyRevenue(uint256 propertyId)
        external
        view
        returns (PropertyRevenue memory)
    {
        return propertyRevenues[propertyId];
    }

    function getPropertyMetrics(uint256 propertyId)
        external
        view
        returns (PropertyMetrics memory)
    {
        return propertyMetrics[propertyId];
    }

    function getPropertyStaking(uint256 propertyId, address user)
        external
        view
        returns (StakingInfo memory)
    {
        return propertyStaking[propertyId][user];
    }

    function getClaimableRevenueForProperty(
        uint256 propertyId,
        address tokenContract,
        address holder
    ) external view returns (uint256) {
        IPropertyToken tokenInstance = IPropertyToken(tokenContract);
        uint256 balance = tokenInstance.balanceOf(holder);
        PropertyRevenue storage revenue = propertyRevenues[propertyId];
        return (balance * revenue.revenuePerToken) - propertyClaimableRevenue[propertyId][holder];
    }

    function _updatePropertyMetrics(
        uint256 propertyId,
        uint256 tokensSold,
        uint256 revenue,
        int256 stakingChange,
        int256 listingChange
    ) internal {
        PropertyMetrics storage metrics = propertyMetrics[propertyId];

        metrics.totalTokensSold += tokensSold;
        metrics.totalRevenue += revenue;

        if (tokensSold > 0 && revenue > 0) {
            metrics.averageTokenPrice = metrics.totalRevenue / metrics.totalTokensSold;
        }

        if (stakingChange > 0) {
            metrics.totalStaked += uint256(stakingChange);
        } else if (stakingChange < 0) {
            metrics.totalStaked -= uint256(-stakingChange);
        }

        if (listingChange > 0) {
            metrics.activeListings += uint256(listingChange);
        } else if (listingChange < 0) {
            metrics.activeListings -= uint256(-listingChange);
        }

        metrics.lastUpdated = block.timestamp;
    }

    function setPropertyActive(uint256 propertyId, bool isActive)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        propertySales[propertyId].isActive = isActive;
    }
}