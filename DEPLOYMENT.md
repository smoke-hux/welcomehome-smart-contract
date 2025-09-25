# Smart Contract Deployment Guide - Hedera Network

## Overview

This guide documents the complete process for deploying the Welcome Home Property smart contracts to Hedera Testnet and Mainnet. The deployment includes two main contracts:

- **SecureWelcomeHomeProperty** (PropertyToken) - ERC-20 token representing property ownership
- **PropertyTokenHandler** - Handles token sales, marketplace, staking, and revenue distribution

## ✅ Successfully Deployed Contracts (Testnet)

- **PropertyToken**: [`0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7`](https://hashscan.io/testnet/address/0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7)
- **PropertyTokenHandler**: [`0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb`](https://hashscan.io/testnet/address/0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb)

## 📋 Prerequisites

### 1. Development Environment
- **Foundry** (forge, cast, anvil) - Latest version
- **Git** - For submodule management
- **Hedera Account** - With HBAR balance for gas fees

### 2. Account Setup
- Create Hedera testnet account at [portal.hedera.com](https://portal.hedera.com)
- Fund account using [Hedera Faucet](https://portal.hedera.com/faucet)
- Export private key (ensure you have at least 10 HBAR for deployments)

### 3. Project Dependencies
```bash
# Install Foundry if not already installed
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and setup project
git clone <your-repo>
cd welcomehome-smart-contract
forge install
```

## ⚙️ Configuration

### 1. Environment Variables

Create and configure `.env` file:

```bash
# Hedera Network Configuration
PRIVATE_KEY=0x315de70eead99e32247c1c99ad835893f111240427c7cc889a85c3f6d50fa235
RPC_URL=https://testnet.hashio.io/api

# Token Configuration
TOKEN_NAME=Welcome Home Property
TOKEN_SYMBOL=WHP

# Deployment Configuration
PROPERTY_ADDRESS=0x0000000000000000000000000000000000000000
TRANSACTION_ID=
MAX_TOKENS=1000000

# Payment token for TokenHandler (use deployer address for testing)
PAYMENT_TOKEN=0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D
```

**⚠️ Security Note**: Never commit your private key to version control. Use environment variables or secure key management in production.

### 2. Foundry Configuration

Update `foundry.toml` with Hedera-specific settings:

```toml
[profile.hedera]
eth_rpc_url = "https://testnet.hashio.io/api"
chain_id = 296
gas_limit = 6000000
gas_price = 2000000000

[profile.hedera_mainnet]
eth_rpc_url = "https://mainnet.hashio.io/api"
chain_id = 295
gas_limit = 6000000
gas_price = 2000000000
```

## 🚀 Deployment Process

### Method 1: Using Cast (Recommended for Hedera)

This method works reliably with Hedera's JSON-RPC implementation.

#### Step 1: Compile Contracts
```bash
forge build
```

#### Step 2: Deploy PropertyToken Contract
```bash
# Deploy SecureWelcomeHomeProperty
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  --create $(cat out/SecureWelcomeHomeProperty.sol/SecureWelcomeHomeProperty.json | jq -r '.bytecode.object')$(cast abi-encode "constructor(string,string)" "Welcome Home Property Token" "WHPT")
```

**Expected Output:**
```
Transaction Hash: 0x[transaction_hash]
Contract deployed to: 0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7
```

#### Step 3: Deploy PropertyTokenHandler Contract
```bash
# Replace addresses with your actual deployed contract addresses
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  --create $(cat out/PropertyTokenHandler.sol/PropertyTokenHandler.json | jq -r '.bytecode.object')$(cast abi-encode "constructor(address,address,address)" 0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D 0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D)
```

### Method 2: Using Forge Create (Alternative)

```bash
# Deploy PropertyToken
forge create src/SecureWelcomeHomeProperty.sol:SecureWelcomeHomeProperty \
  --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  --constructor-args "Welcome Home Property Token" "WHPT"

# Deploy PropertyTokenHandler
forge create src/PropertyTokenHandler.sol:PropertyTokenHandler \
  --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  --constructor-args <PROPERTY_TOKEN_ADDRESS> <PAYMENT_TOKEN_ADDRESS> <FEE_COLLECTOR_ADDRESS>
```

### ⚠️ Why Forge Script Doesn't Work

The `forge script` approach fails on Hedera because:
1. Hedera's JSON-RPC implementation has different transaction broadcasting behavior
2. Forge script expects Ethereum-specific receipt formats
3. Gas estimation and nonce management work differently

## 🔧 Post-Deployment Configuration

### 1. Grant Necessary Roles

```bash
# Grant MINTER_ROLE to PropertyTokenHandler
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "grantRole(bytes32,address)" \
  0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 \
  0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb

# Grant PROPERTY_MANAGER_ROLE to PropertyTokenHandler
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "grantRole(bytes32,address)" \
  0x5aa58c694aeb083df8754bf5e98675317e4137a5a8a2c6188d0228869e43da7e \
  0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb
```

### 2. Initialize Property Contract

```bash
# Connect to property (placeholder for now)
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "connectToProperty(address,string)" \
  0x0000000000000000000000000000000001 \
  "PROPERTY-001"

# Set maximum token supply
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "setMaxTokens(uint256)" \
  1000000000000000000000000

# Mint initial test tokens
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "mint(address,uint256)" \
  0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D \
  100000000000000000000
```

### 3. Configure Token Sale

```bash
# Configure sale parameters on PropertyTokenHandler
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb \
  "configureSale(uint256,uint256,uint256,uint256)" \
  1000000000000000000 \
  1000000000000000000 \
  1000000000000000000000 \
  500000000000000000000000

# Set accredited investor status (for testing)
cast send --rpc-url https://testnet.hashio.io/api \
  --private-key $PRIVATE_KEY \
  0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb \
  "setAccreditedInvestor(address,bool)" \
  0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D \
  true
```

## ✅ Verification

### 1. Verify Contract Deployment

Check contracts on HashScan:
- Visit [hashscan.io/testnet](https://hashscan.io/testnet)
- Search for your contract addresses
- Verify transaction history and contract creation

### 2. Test Contract Functions

```bash
# Check token name
cast call --rpc-url https://testnet.hashio.io/api \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "name()" | cast to-ascii

# Check token balance
cast call --rpc-url https://testnet.hashio.io/api \
  0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7 \
  "balanceOf(address)" \
  0x0A3bb08b3a15A19b4De82F8AcFc862606FB69A2D

# Check sale configuration
cast call --rpc-url https://testnet.hashio.io/api \
  0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb \
  "currentSale()"
```

### 3. Update Frontend Configuration

Update your frontend `.env.local`:

```bash
# Add deployed contract addresses
NEXT_PUBLIC_PROPERTY_TOKEN_ADDRESS=0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7
NEXT_PUBLIC_PROPERTY_MANAGER_ADDRESS=0x71d91F4Ad42aa2f1A118dE372247630D8C3f30cb
```

## 🔧 Troubleshooting

### Common Issues

#### 1. "Transaction failed" or hanging deployment
**Cause**: Network congestion or gas issues
**Solution**:
- Increase gas limit: `--gas-limit 6000000`
- Wait and retry
- Check account HBAR balance

#### 2. "InvalidAddress()" error during PropertyTokenHandler deployment
**Cause**: Zero address passed as payment token
**Solution**: Use a valid address (deployer address for testing)

#### 3. Role assignment fails
**Cause**: Using wrong role hash
**Solution**: Use keccak256 hash of role name:
- MINTER_ROLE: `0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
- PROPERTY_MANAGER_ROLE: `0x5aa58c694aeb083df8754bf5e98675317e4137a5a8a2c6188d0228869e43da7e`

#### 4. Frontend can't connect to contracts
**Cause**: Contract addresses not updated in environment
**Solution**: Update `.env.local` with deployed addresses

## 📊 Gas Costs (Testnet)

Typical deployment costs:
- **SecureWelcomeHomeProperty**: ~2.5 HBAR
- **PropertyTokenHandler**: ~4.0 HBAR
- **Role Configuration**: ~0.1 HBAR per transaction
- **Initial Setup**: ~0.5 HBAR total

**Total Estimated Cost**: ~7.5 HBAR for complete deployment

## 🌐 Mainnet Deployment

For mainnet deployment:

1. **Update RPC URL**: `https://mainnet.hashio.io/api`
2. **Update Chain ID**: `295`
3. **Ensure sufficient HBAR**: ~10-15 HBAR recommended
4. **Use production private key**: Store securely, never commit
5. **Test thoroughly**: Deploy to testnet first

### Mainnet Configuration

```bash
# Mainnet environment variables
RPC_URL=https://mainnet.hashio.io/api
CHAIN_ID=295
```

## 🔒 Security Considerations

### 1. Private Key Management
- Use hardware wallets for mainnet
- Never commit private keys to version control
- Use environment variables or secure key management
- Rotate keys after deployment if needed

### 2. Contract Security
- Audit contracts before mainnet deployment
- Use multi-signature wallets for admin functions
- Implement proper access controls
- Monitor contract activity

### 3. Access Control
- Grant minimal necessary roles
- Use separate accounts for different roles
- Implement timelock for critical functions
- Regular security reviews

## 📚 Additional Resources

- [Hedera Developer Portal](https://docs.hedera.com)
- [Foundry Documentation](https://book.getfoundry.sh/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [HashScan Explorer](https://hashscan.io)

## 🆘 Support

If you encounter issues:

1. **Check HashScan**: Verify transaction status
2. **Review Logs**: Check error messages carefully
3. **Network Status**: Verify Hedera network status
4. **Community Support**: Hedera Discord/Telegram channels

---

**Last Updated**: January 2025
**Network**: Hedera Testnet (296) / Mainnet (295)
**Solidity Version**: 0.8.20
**Foundry Version**: Latest