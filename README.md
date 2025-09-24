# Secure Welcome Home Property - Hedera Blockchain

A secure, enhanced version of the WelcomeHome property tokenization smart contract optimized for deployment on Hedera blockchain using Foundry.

## Security Improvements

The enhanced contract includes the following security features:

1. **Reentrancy Protection**: Uses OpenZeppelin's ReentrancyGuard
2. **Input Validation**: Comprehensive checks for all inputs
3. **Access Control**: Fine-grained role-based permissions with separate Property Manager role
4. **Rate Limiting**: Mint cooldown period to prevent spam
5. **Event Logging**: Detailed events for all critical actions
6. **Error Handling**: Custom errors for gas efficiency
7. **Supply Management**: Enhanced tracking of minted vs burned tokens
8. **Property Initialization**: One-time property connection to prevent changes
9. **Zero Address Checks**: Protection against accidental burns
10. **Maximum Supply Limits**: Configurable caps with validation

## Roles

- **DEFAULT_ADMIN_ROLE**: Can manage all other roles and set max tokens
- **MINTER_ROLE**: Can mint new tokens (with cooldown)
- **PAUSER_ROLE**: Can pause/unpause all token transfers
- **PROPERTY_MANAGER_ROLE**: Can connect the token to a property (one-time)

## Setup

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
forge install
```

3. Configure environment:
```bash
cp .env.example .env
# Edit .env with your Hedera account details
```

## Testing

Run all tests:
```bash
forge test
```

Run tests with gas reporting:
```bash
forge test --gas-report
```

Run specific test:
```bash
forge test --match-test testMinting -vvv
```

Run with coverage:
```bash
forge coverage
```

## Deployment

### Deploy to Hedera Testnet:
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $HEDERA_TESTNET_RPC_URL --broadcast --verify
```

### Deploy with configuration:
```bash
forge script script/Deploy.s.sol:DeployWithConfigScript --rpc-url $HEDERA_TESTNET_RPC_URL --broadcast --verify
```

### Deploy to Hedera Mainnet:
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url $HEDERA_MAINNET_RPC_URL --broadcast --verify
```

## Configuration

The contract can be configured through environment variables:

- `TOKEN_NAME`: Name of the token
- `TOKEN_SYMBOL`: Symbol of the token
- `PROPERTY_ADDRESS`: Address of the property contract
- `TRANSACTION_ID`: Transaction ID for property connection
- `MAX_TOKENS`: Maximum supply (0 for unlimited)
- `MINTERS`: Comma-separated addresses for minter role
- `PAUSERS`: Comma-separated addresses for pauser role
- `PROPERTY_MANAGERS`: Comma-separated addresses for property manager role

## Hedera-Specific Considerations

1. **Gas Costs**: Hedera has different gas pricing than Ethereum
2. **Transaction Limits**: Be aware of Hedera's transaction size limits
3. **Consensus**: Hedera uses Hashgraph consensus, not PoW/PoS
4. **Native Token Service**: Consider using Hedera Token Service for production

## Development Commands

Build contracts:
```bash
forge build
```

Format code:
```bash
forge fmt
```

Check contract size:
```bash
forge build --sizes
```

Gas snapshot:
```bash
forge snapshot
```

## Security Auditing

Before mainnet deployment:

1. Run slither:
```bash
slither src/
```

2. Run mythril:
```bash
myth analyze src/SecureWelcomeHomeProperty.sol
```

3. Consider professional audit for production use

## License

MIT
