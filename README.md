# Welcome Home Property - Hedera Smart Contract Suite

A comprehensive property tokenization platform deployed on Hedera blockchain using Foundry. Features multiple deployment patterns for different use cases, from lightweight property registration to full ERC-20 property tokens.

## Contract Architecture

### Deployed Contracts (Hedera Testnet)

1. **PropertyTokenHandler** ([`0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7`](https://hashscan.io/testnet/address/0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7))
   - ERC-20 token with property tokenization features
   - Role-based access control with admin, minter, pauser, and property manager roles
   - Reentrancy protection and comprehensive security features

2. **MinimalPropertyFactory** ([`0x710d1E7F345CA3D893511743A00De2cFC1eAb6De`](https://hashscan.io/testnet/address/0x710d1E7F345CA3D893511743A00De2cFC1eAb6De))
   - Lightweight property registration system
   - Registry pattern optimized for Hedera's 24KB contract size limit
   - Gas-efficient property creation and management

3. **PropertyGovernance** ([`0x75A63900FF55F27975005FB8299e3C1b42e28dD6`](https://hashscan.io/testnet/address/0x75A63900FF55F27975005FB8299e3C1b42e28dD6))
   - Governance system for property-related decisions
   - Voting mechanisms and proposal management

### Security Features

- **Reentrancy Protection**: OpenZeppelin ReentrancyGuard
- **Access Control**: Role-based permissions (RBAC)
- **Input Validation**: Comprehensive parameter checking
- **Event Logging**: Detailed audit trail
- **Rate Limiting**: Mint cooldown periods
- **Supply Management**: Token tracking and limits

### Roles (PropertyTokenHandler)

- **DEFAULT_ADMIN_ROLE** (`0x00...`): Master admin, can manage all roles
- **MINTER_ROLE** (`0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`): Token minting permissions
- **PROPERTY_MANAGER_ROLE** (`0x5aa58c694aeb083df8754bf5e98675317e4137a5a8a2c6188d0228869e43da7e`): Property connection management

## Quick Start

### Prerequisites

1. **Install Foundry**:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Install Dependencies**:
```bash
forge install
```

3. **Configure Environment** (Hedera Testnet):
```bash
# Create .env file with Hedera configuration
echo 'HEDERA_RPC_URL=https://testnet.hashio.io/api' > .env
echo 'HEDERA_PRIVATE_KEY=your_private_key_here' >> .env
```

**Important**: This project follows the official Hedera Foundry documentation exactly. Use `HEDERA_RPC_URL` and `HEDERA_PRIVATE_KEY` environment variables as recommended by Hedera.

### System Testing

Test the complete deployed system:
```bash
# Test all contracts and interactions
forge script script/TestSystem.s.sol --rpc-url hedera
```

### Unit Testing

```bash
# Run all tests
forge test

# Gas reporting
forge test --gas-report

# Specific test with verbose output
forge test --match-test testMinting -vvv

# Coverage analysis
forge coverage
```

## Deployment

📋 **For complete deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md)**

### Production Deployments (Hedera Testnet)

All contracts deployed using official Hedera Foundry configuration:

| Contract | Address | HashScan Link |
|----------|---------|---------------|
| PropertyTokenHandler | `0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7` | [View on HashScan](https://hashscan.io/testnet/address/0xA4469cCf38cc88bA64c9d570692872c5c2A13aF7) |
| MinimalPropertyFactory | `0x710d1E7F345CA3D893511743A00De2cFC1eAb6De` | [View on HashScan](https://hashscan.io/testnet/address/0x710d1E7F345CA3D893511743A00De2cFC1eAb6De) |
| PropertyGovernance | `0x75A63900FF55F27975005FB8299e3C1b42e28dD6` | [View on HashScan](https://hashscan.io/testnet/address/0x75A63900FF55F27975005FB8299e3C1b42e28dD6) |

### New Deployment (Using Hedera Best Practices)

```bash
# 1. Build contracts
forge build

# 2. Deploy MinimalPropertyFactory (lightweight)
forge script script/DeployMinimalFactory.s.sol --rpc-url hedera --broadcast

# 3. Deploy PropertyGovernance
forge script script/DeployGovernance.s.sol --rpc-url hedera --broadcast

# 4. Deploy PropertyTokenHandler (full ERC-20)
forge script script/Deploy.s.sol --rpc-url hedera --broadcast
```

**Key Improvements:**
- Uses `hedera` RPC alias from foundry.toml
- Follows official Hedera environment variable naming
- Includes `--broadcast` flag for actual deployment
- MinimalPropertyFactory solves 24KB contract size limits

### Hedera Configuration (foundry.toml)

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.20"
optimizer = true
optimizer_runs = 200
gas_limit = 30000000
gas_price = 100000000000

[rpc_endpoints]
hedera = "${HEDERA_RPC_URL}"
```

### Environment Variables

**Hedera Configuration:**
- `HEDERA_RPC_URL`: https://testnet.hashio.io/api (Testnet) or https://mainnet.hashio.io/api (Mainnet)
- `HEDERA_PRIVATE_KEY`: Your account private key

**Contract Configuration:**
- `TOKEN_NAME`: Property token name
- `TOKEN_SYMBOL`: Property token symbol
- `MAX_TOKENS`: Maximum token supply (0 for unlimited)
- `MINTERS`: Comma-separated minter addresses
- `PAUSERS`: Comma-separated pauser addresses
- `PROPERTY_MANAGERS`: Comma-separated property manager addresses

## Hedera-Specific Implementation Details

### Contract Size Optimization

**Problem**: Hedera EVM enforces a 24KB (24,576 bytes) contract size limit.

**Solution**: Created MinimalPropertyFactory (5,598 bytes) vs original PropertyFactory (37,648 bytes):
- Uses registry pattern instead of embedded contract deployment
- Removed complex factory logic for gas efficiency
- Maintains full functionality for property registration

### Deployment Best Practices

1. **Use Official Hedera RPC**: `https://testnet.hashio.io/api`
2. **Environment Variables**: `HEDERA_RPC_URL` and `HEDERA_PRIVATE_KEY`
3. **Broadcast Flag**: Always use `--broadcast` for actual deployment
4. **Gas Configuration**: Set appropriate gas limits (30M recommended)

### Network Considerations

- **Consensus**: Hashgraph consensus (not PoW/PoS)
- **Finality**: Immediate finality vs probabilistic
- **Gas Model**: Different pricing structure than Ethereum
- **Account Model**: Hedera account ID system
- **Native Services**: Consider HTS (Hedera Token Service) for production tokens

## Development Workflow

### Build and Compilation

```bash
# Build all contracts
forge build

# Check contract sizes (important for Hedera 24KB limit)
forge build --sizes

# Format code
forge fmt
```

### Testing and Analysis

```bash
# Complete system test
forge script script/TestSystem.s.sol --rpc-url hedera

# Unit tests
forge test

# Gas analysis
forge snapshot
forge test --gas-report
```

### Property Registration Example

```bash
# Register a new property using MinimalPropertyFactory
cast send --rpc-url hedera \
  --private-key $HEDERA_PRIVATE_KEY \
  0x710d1E7F345CA3D893511743A00De2cFC1eAb6De \
  "registerProperty(string,string,uint256,string)" \
  "Property Name" "Property Location" 1000000000000000000 "QmPropertyHash"
```

### Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `Deploy.s.sol` | Deploy PropertyTokenHandler | `forge script script/Deploy.s.sol --rpc-url hedera --broadcast` |
| `DeployMinimalFactory.s.sol` | Deploy MinimalPropertyFactory | `forge script script/DeployMinimalFactory.s.sol --rpc-url hedera --broadcast` |
| `DeployGovernance.s.sol` | Deploy PropertyGovernance | `forge script script/DeployGovernance.s.sol --rpc-url hedera --broadcast` |
| `TestSystem.s.sol` | Test complete system | `forge script script/TestSystem.s.sol --rpc-url hedera` |
| `RegisterProperty.s.sol` | Register new property | `forge script script/RegisterProperty.s.sol --rpc-url hedera --broadcast` |

## Security and Auditing

### Pre-Production Checklist

```bash
# 1. Static analysis
slither src/

# 2. Mythril analysis
myth analyze src/

# 3. Contract size validation
forge build --sizes

# 4. Gas optimization
forge test --gas-report

# 5. System integration test
forge script script/TestSystem.s.sol --rpc-url hedera
```

### Production Deployment Verification

All contracts have been verified on HashScan:
- ✅ PropertyTokenHandler: Role assignments confirmed
- ✅ MinimalPropertyFactory: Property registration tested
- ✅ PropertyGovernance: Governance functions operational

## Contributing

When contributing:
1. Follow existing code patterns
2. Ensure contracts stay under 24KB for Hedera compatibility
3. Test with `forge script script/TestSystem.s.sol --rpc-url hedera`
4. Update documentation for any new features

## License

MIT License - see [LICENSE](LICENSE) file for details.
