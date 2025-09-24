.PHONY: all build test deploy clean install

# Default target
all: clean install build test

# Install dependencies
install:
	@echo "Installing dependencies..."
	@forge install

# Build contracts
build:
	@echo "Building contracts..."
	@forge build

# Run tests
test:
	@echo "Running tests..."
	@forge test

# Run tests with gas reporting
test-gas:
	@echo "Running tests with gas report..."
	@forge test --gas-report

# Run tests with verbosity
test-verbose:
	@echo "Running tests with verbosity..."
	@forge test -vvv

# Run coverage
coverage:
	@echo "Running coverage..."
	@forge coverage

# Deploy to Hedera testnet
deploy-testnet:
	@echo "Deploying to Hedera testnet..."
	@forge script script/Deploy.s.sol:DeployScript --rpc-url https://testnet.hashio.io/api --broadcast

# Deploy with configuration to Hedera testnet
deploy-config-testnet:
	@echo "Deploying with configuration to Hedera testnet..."
	@forge script script/Deploy.s.sol:DeployWithConfigScript --rpc-url https://testnet.hashio.io/api --broadcast

# Deploy to Hedera mainnet
deploy-mainnet:
	@echo "Deploying to Hedera mainnet..."
	@forge script script/Deploy.s.sol:DeployScript --rpc-url https://mainnet.hashio.io/api --broadcast

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@forge clean

# Format code
format:
	@echo "Formatting code..."
	@forge fmt

# Check contract sizes
size:
	@echo "Checking contract sizes..."
	@forge build --sizes

# Create gas snapshot
snapshot:
	@echo "Creating gas snapshot..."
	@forge snapshot

# Run slither (requires slither installed)
slither:
	@echo "Running slither security analysis..."
	@slither src/

# Help
help:
	@echo "Available commands:"
	@echo "  make install         - Install dependencies"
	@echo "  make build          - Build contracts"
	@echo "  make test           - Run tests"
	@echo "  make test-gas       - Run tests with gas reporting"
	@echo "  make test-verbose   - Run tests with verbosity"
	@echo "  make coverage       - Run coverage"
	@echo "  make deploy-testnet - Deploy to Hedera testnet"
	@echo "  make deploy-mainnet - Deploy to Hedera mainnet"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make format         - Format code"
	@echo "  make size           - Check contract sizes"
	@echo "  make snapshot       - Create gas snapshot"
	@echo "  make slither        - Run security analysis"