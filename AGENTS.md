# Agents

## OVERVIEW

This document provides comprehensive information for deploying smart contracts to Polkadot Hub TestNet (Paseo) using Claude Code. It covers **two development environments**:

1. **Hardhat** - JavaScript/TypeScript-based development with full testing support
2. **Foundry-Polkadot** - Rust-based, fast compilation and deployment toolkit

Both environments support the same Solidity contracts and deploy to the same Polkadot Hub network. Choose based on your team's preferences and workflow.

**CRITICAL: For Hardhat, always start new projects with `kitdot@latest init` for proper network configuration and dependency management.**

## NETWORK INFORMATION

### Paseo TestNet Details

- **Network Name**: Polkadot Hub TestNet
- **Chain ID**: 420420422 (0x1911f0a6 in hex)
- **RPC URL**: https://testnet-passet-hub-eth-rpc.polkadot.io
- **Block Explorer**: https://blockscout-passet-hub.parity-testnet.parity.io
- **Currency**: PAS
- **Faucet**: https://faucet.polkadot.io/?parachain=1111
- **Status**: PolkaVM Preview Release (early development stage)

### Key Characteristics

- **EVM Compatibility**: Ethereum-compatible smart contract deployment
- **PolkaVM**: Requires specific configuration for compatibility
- **Bytecode Limit**: ~100KB maximum contract size
- **Gas Model**: Standard EVM gas mechanics
- **Node Version Warning**: Works with Node.js v21+ despite warnings

## REQUIRED DEPENDENCIES

### Core Dependencies

```bash
npm install --save-dev @parity/hardhat-polkadot solc@0.8.28
npm install --force @nomicfoundation/hardhat-toolbox
npm install dotenv
```

### Package.json Requirements

```json
{
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^5.0.0",
    "@parity/hardhat-polkadot": "^0.1.7",
    "solc": "^0.8.28",
    "hardhat": "^2.22.0"
  },
  "dependencies": {
    "dotenv": "^17.0.1",
    "ethers": "^6.13.5"
  }
}
```

**CRITICAL**: Use `--force` flag when installing hardhat-toolbox to resolve dependency conflicts.

## DEVELOPMENT ENVIRONMENT OPTIONS

This guide covers two development environments for Polkadot Hub:
1. **Hardhat** - Full-featured with testing and deployment automation
2. **Foundry-Polkadot** - Fast, efficient, Rust-based tooling

Choose based on your preference and familiarity. Both work seamlessly with Polkadot Hub.

---

## HARDHAT CONFIGURATION

### Complete Working hardhat.config.js

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("@parity/hardhat-polkadot");
const { vars } = require("hardhat/config");

module.exports = {
  solidity: "0.8.28",
  resolc: {
    version: "0.3.0",
    compilerSource: "npm",
  },
  networks: {
    hardhat: {
      polkavm: true,
    },
    localNode: {
      polkavm: true,
      url: "http://127.0.0.1:8545",
    },
    passetHub: {
      polkavm: true,
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
      accounts: [vars.get("PRIVATE_KEY")],
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};
```

### Configuration Requirements

1. **Must use string format for Solidity version**: `solidity: "0.8.28"`
2. **Must include resolc configuration**: Required for PolkaVM compatibility
3. **Must set polkavm: true**: In all network configurations
4. **Must use hardhat vars**: For private key management
5. **Network name**: Use `passetHub` (not paseo or other names)

## SETUP PROCESS

### Step 1: Initialize Project with kitdot@latest (Recommended)

```bash
npm install -g kitdot@latest
kitdot init your-project
cd your-project
```

**Alternative Manual Setup:**

```bash
mkdir your-project
cd your-project
npm init -y
```

**Why kitdot@latest?** Automatically configures proper network settings, dependencies, and project structure. Eliminates common setup errors.

### Step 2: Install Dependencies

**If using kitdot@latest:** Dependencies are automatically installed.

**Manual installation:**

```bash
npm install --save-dev @parity/hardhat-polkadot solc@0.8.28
npm install --force @nomicfoundation/hardhat-toolbox
npm install dotenv
```

### Step 3: Initialize Polkadot Plugin

**If using kitdot@latest:** Already configured.

**Manual setup:**

```bash
npx hardhat-polkadot init
```

### Step 4: Configure Private Key

```bash
npx hardhat vars set PRIVATE_KEY
# Enter your private key when prompted (without 0x prefix)
```

### Step 5: Get Test Tokens

1. Visit https://faucet.polkadot.io/?parachain=1111
2. Enter your wallet address
3. Request PAS tokens
4. Verify balance in wallet or block explorer

### Step 6: Create Hardhat Config

**If using kitdot@latest:** Configuration file already created with proper settings.

**Manual setup:** Copy the exact configuration above into `hardhat.config.js`

## CONTRACT DEVELOPMENT

### Solidity Version Requirements

- **Required Version**: ^0.8.28
- **EVM Target**: paris (default)
- **Optimizer**: Enabled by default

### Example Simple Contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract SimpleStorage {
    uint256 public value;

    constructor() {
        value = 42;
    }

    function setValue(uint256 _value) external {
        value = _value;
    }

    function getValue() external view returns (uint256) {
        return value;
    }
}
```

### Contract Size Limitations

- **Maximum Bytecode**: ~100KB
- **OpenZeppelin Impact**: Official standard imports exceed limit
- **Solution**: Use PolkaVM-optimized contracts from https://github.com/papermoonio/openzeppelin-contracts-polkadot
- **Optimization Required**: Copy only needed code, avoid installing as dependency

## DEPLOYMENT PROCESS

### Using Hardhat Ignition (Recommended)

#### Step 1: Create Ignition Module

```javascript
// ignition/modules/YourModule.js
const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("YourModule", (m) => {
  const contract = m.contract("YourContract", [
    // constructor arguments
  ]);
  return { contract };
});
```

#### Step 2: Compile Contracts

```bash
npx hardhat compile
# Should output: "Successfully compiled X Solidity files"
```

#### Step 3: Deploy to Paseo

```bash
npx hardhat ignition deploy ./ignition/modules/YourModule.js --network passetHub
# Confirm with 'y' when prompted
```

### Deployment States

- **Clean State**: `rm -rf ignition/deployments/` to start fresh
- **Resume**: Ignition automatically resumes interrupted deployments
- **Track Transactions**: Use block explorer for failed transaction tracking

---

## FOUNDRY-POLKADOT CONFIGURATION

### Overview

Foundry-Polkadot is a specialized fork of Foundry specifically engineered for Polkadot Hub development. It provides a fast, portable, and modular toolkit for developers familiar with Foundry who want to leverage its capabilities in the Polkadot ecosystem.

**Key Advantage**: Blazing fast compilation and deployment using Rust-based tooling.

### Installation

#### Step 1: Install Foundry-Polkadot

```bash
# Download and install foundryup-polkadot
curl -L https://raw.githubusercontent.com/paritytech/foundry-polkadot/refs/heads/master/foundryup/install | bash

# Follow on-screen instructions, then install the toolchain
foundryup-polkadot
```

This installs two main tools:
- **forge** - Contract compilation, building, and deployment
- **cast** - Blockchain interaction and RPC calls

#### Step 2: Verify Installation

```bash
forge --version
cast --version
```

### Key Differences from Standard Foundry

**Critical Distinctions**:

1. **Compiler**: Uses `resolc` instead of `solc` to generate PolkaVM-compatible bytecode
2. **Bytecode Prefix**: PolkaVM bytecode starts with `0x505` (not standard EVM)
3. **Unsupported Features** (as of 2025):
   - Anvil (local blockchain)
   - `forge test` (Solidity testing)
   - Factory contract deployment
   - Yul code compilation

**Supported Commands**:
- `forge init`, `forge build`, `forge create`, `forge bind`, `forge inspect`
- Full `cast` RPC and blockchain interaction capabilities

### Project Setup

#### Initialize New Project

```bash
# Create new Foundry project
forge init your-project
cd your-project

# Project structure created:
# ├── src/           # Contract source files
# ├── script/        # Deployment scripts
# ├── test/          # Test files (note: forge test not yet supported)
# └── foundry.toml   # Configuration file
```

#### Configure foundry.toml for Polkadot

Create or update `foundry.toml`:

```toml
[profile.default]
src = 'src'
out = 'out'
libs = ['lib']
solc = '0.8.28'

# Resolc configuration for PolkaVM
[profile.default.resolc]
resolc_compile = true
resolc_version = "0.3.0"
resolc_optimizer_mode = "3"

# Network configurations
[rpc_endpoints]
passetHub = "https://testnet-passet-hub-eth-rpc.polkadot.io"
localNode = "http://127.0.0.1:8545"
```

### Compilation

#### Basic Compilation

```bash
# Compile contracts for PolkaVM
forge build --resolc

# Expected output:
# [⠊] Compiling...
# [⠘] Compiling 1 files with Resolc 0.3.0
# [⠃] Resolc 0.3.0 finished in XXms
# Compiler run successful!
```

#### Compilation with Optimization

```bash
# Specify optimization level (0-3, higher = more optimized)
forge build --resolc --resolc-optimizer-mode 3

# Configure memory limits
forge build --resolc --heap-size 1024 --stack-size 256
```

#### Verify Bytecode

```bash
# Inspect compiled contract bytecode
forge inspect Counter bytecode

# Should start with 0x505... (PolkaVM prefix)
```

### Contract Development

Use the same Solidity version and structure as with Hardhat:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract Counter {
    uint256 public number;

    constructor() {
        number = 0;
    }

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
```

**Size Limitations**: Same ~100KB bytecode limit applies. Keep contracts minimal.

### Deployment

#### Step 1: Set Up Private Key

```bash
# Set private key as environment variable
export PRIVATE_KEY="your_private_key_here"

# Or create .env file
echo "PRIVATE_KEY=your_private_key_here" > .env
```

#### Step 2: Deploy to Paseo TestNet

```bash
# Deploy contract with forge create
forge create src/Counter.sol:Counter \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
    --private-key $PRIVATE_KEY \
    --resolc

# With constructor arguments
forge create src/MyContract.sol:MyContract \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
    --private-key $PRIVATE_KEY \
    --constructor-args "arg1" "arg2" \
    --resolc
```

#### Step 3: Verify Deployment

```bash
# Get contract bytecode
cast code <CONTRACT_ADDRESS> --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Call contract function
cast call <CONTRACT_ADDRESS> "number()" --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io
```

### Contract Interaction

#### Reading Contract State

```bash
# Call view functions (no gas required)
cast call <CONTRACT_ADDRESS> "getValue()(uint256)" \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io
```

#### Sending Transactions

```bash
# Send transaction to modify state
cast send <CONTRACT_ADDRESS> "setValue(uint256)" 123 \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
    --private-key $PRIVATE_KEY

# Check transaction receipt
cast receipt <TX_HASH> --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io
```

#### Advanced Cast Commands

```bash
# Get account balance
cast balance <ADDRESS> --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Get block information
cast block latest --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Estimate gas
cast estimate <CONTRACT_ADDRESS> "setValue(uint256)" 123 \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io

# Get chain ID
cast chain-id --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io
```

### Deployment Scripts

Create Solidity deployment scripts in `script/` directory:

```solidity
// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/Counter.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Counter counter = new Counter();
        console.log("Counter deployed to:", address(counter));

        vm.stopBroadcast();
    }
}
```

Run deployment script:

```bash
forge script script/Deploy.s.sol:DeployScript \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
    --broadcast \
    --resolc
```

### Configuration Best Practices

#### Using RPC Aliases

Update `foundry.toml`:

```toml
[rpc_endpoints]
paseo = "https://testnet-passet-hub-eth-rpc.polkadot.io"
```

Then use alias in commands:

```bash
forge create src/Counter.sol:Counter \
    --rpc-url paseo \
    --private-key $PRIVATE_KEY \
    --resolc
```

#### Environment Variables

Create `.env` file:

```bash
PRIVATE_KEY=your_private_key_here
RPC_URL=https://testnet-passet-hub-eth-rpc.polkadot.io
```

Load in commands:

```bash
source .env
forge create src/Counter.sol:Counter \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --resolc
```

### Troubleshooting

#### Common Issues

**Issue**: "unknown flag: --resolc"
**Solution**: Ensure you installed `foundry-polkadot`, not standard Foundry:
```bash
foundryup-polkadot
forge --version  # Should show Polkadot fork version
```

**Issue**: Compilation fails with "command not found: resolc"
**Solution**: Update to latest version:
```bash
foundryup-polkadot
```

**Issue**: Bytecode doesn't start with 0x505
**Solution**: Ensure `--resolc` flag is used or `resolc_compile = true` in foundry.toml

**Issue**: "initcode is too big" error
**Solution**: Same as Hardhat - optimize contract size, remove heavy dependencies

### Foundry vs Hardhat Comparison

| Feature | Hardhat | Foundry-Polkadot |
|---------|---------|------------------|
| **Language** | JavaScript/TypeScript | Rust/Solidity |
| **Speed** | Moderate | Very Fast |
| **Testing** | Full support | Not yet supported |
| **Deployment** | Ignition modules | forge create / scripts |
| **Local Network** | Built-in | Not available (Anvil unsupported) |
| **Learning Curve** | Easier for JS devs | Easier for Rust devs |
| **Tooling** | Extensive plugins | Powerful CLI tools |
| **Best For** | Full development lifecycle | Fast compilation/deployment |

### Essential Foundry-Polkadot Commands

```bash
# Project management
forge init <project>           # Initialize new project
forge install <dependency>     # Install dependencies
forge update                   # Update dependencies
forge remove <dependency>      # Remove dependencies

# Compilation
forge build --resolc           # Compile contracts for PolkaVM
forge clean                    # Remove build artifacts
forge inspect <contract> <field>  # Inspect contract details

# Deployment
forge create <contract> \      # Deploy contract
    --rpc-url <url> \
    --private-key <key> \
    --resolc

forge script <script> \        # Run deployment script
    --rpc-url <url> \
    --broadcast \
    --resolc

# Blockchain interaction (cast)
cast call <address> <sig>      # Call view function
cast send <address> <sig>      # Send transaction
cast balance <address>         # Check balance
cast receipt <tx>              # Get transaction receipt
cast code <address>            # Get contract bytecode
cast storage <address> <slot>  # Read storage slot
cast chain-id                  # Get chain ID
cast block <block>             # Get block info
```

### Resources

- **Official Docs**: https://docs.polkadot.com/develop/smart-contracts/dev-environments/foundry/
- **GitHub**: https://github.com/paritytech/foundry-polkadot
- **Foundry Book (Polkadot)**: https://github.com/paritytech/foundry-book-polkadot

---

## COMMON ERRORS AND SOLUTIONS

### 1. "CodeRejected" Error

**Error**: `Failed to instantiate contract: Module(ModuleError { index: 60, error: [27, 0, 0, 0], message: Some("CodeRejected") })`

**Causes**:

- Missing PolkaVM configuration
- Incorrect network settings
- Missing resolc configuration

**Solutions**:

- Ensure `polkavm: true` in network config
- Add resolc configuration block
- Use exact hardhat.config.js format above

### 2. "initcode is too big" Error

**Error**: `initcode is too big: 125282` (or similar number)

**Cause**: Contract bytecode exceeds ~100KB limit

**Solutions**:

- Use PolkaVM-optimized OpenZeppelin contracts from https://github.com/papermoonio/openzeppelin-contracts-polkadot
- Copy minimal implementations directly (don't install as dependency)
- Split large contracts into smaller components
- Remove unnecessary features and imports

### 3. Configuration Errors

**Error**: `Cannot read properties of undefined (reading 'settings')`

**Solution**: Use string format for Solidity version: `solidity: "0.8.28"`

### 4. Dependency Issues

**Error**: `Cannot find module 'run-container'` or similar

**Solutions**:

- Install dependencies with `--force` flag
- Clear node_modules and reinstall
- Verify @parity/hardhat-polkadot version compatibility

### 5. Private Key Issues

**Error**: `No signers found` or authentication failures

**Solutions**:

- Set private key via `npx hardhat vars set PRIVATE_KEY`
- Ensure account has PAS tokens
- Verify private key format (no 0x prefix in vars)

## CONTRACT OPTIMIZATION

### Using OpenZeppelin Contracts with PolkaVM

**CRITICAL:** The official OpenZeppelin contracts are too large for PolkaVM's 100KB bytecode limit. When OpenZeppelin functionality is needed, use these alternatives in order of preference:

#### Option 1: Use OpenZeppelin-Polkadot (Recommended)

**Repository**: https://github.com/papermoonio/openzeppelin-contracts-polkadot

This repository contains PolkaVM-optimized versions of OpenZeppelin contracts that are specifically designed to work within the 100KB limit.

**How to Use:**

1. **Browse the repository** for the contract you need
2. **Copy the minimal implementation** directly into your project
3. **Do NOT install as a dependency** (to avoid size bloat)

**Example - Using Ownable from OpenZeppelin-Polkadot:**

```solidity
// Copy from: https://github.com/papermoonio/openzeppelin-contracts-polkadot
// Path: contracts/access/Ownable.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @dev PolkaVM-optimized Ownable contract
 * Source: papermoonio/openzeppelin-contracts-polkadot
 */
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
```

**Available Contracts in OpenZeppelin-Polkadot:**

Check the repository for PolkaVM-optimized versions of:
- **Access Control**: Ownable, AccessControl
- **Security**: ReentrancyGuard, Pausable
- **Token Standards**: ERC20, ERC721, ERC1155
- **Utils**: Context, Strings, Math

**Important Notes:**
- Always copy the latest version from the repository
- Test contract size after adding: `forge inspect YourContract bytecode --resolc`
- Combine multiple features only if they fit within 100KB
- Reference the source URL in your code comments

#### Option 2: Write Minimal Custom Implementations

If OpenZeppelin-Polkadot doesn't have the contract you need, create minimal implementations:

**Minimal Ownable:**

```solidity
contract SimpleOwnable {
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
```

**Minimal ReentrancyGuard:**

```solidity
contract SimpleReentrancyGuard {
    bool private locked;

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }
}
```

#### Option 3: Split Functionality Across Contracts

For complex requirements, split functionality:

```solidity
// Contract 1: Core Logic (< 100KB)
contract CoreLogic is Ownable {
    // Main business logic
}

// Contract 2: Extensions (< 100KB)
contract Extensions {
    address public coreLogic;
    // Extended functionality
}
```

### Contract Size Verification

Always verify your contract size during development:

**Using Foundry:**
```bash
# Check bytecode size
forge inspect YourContract bytecode --resolc | wc -c

# Build with size reporting
forge build --resolc --sizes
```

**Using Hardhat:**
```bash
# Compilation shows warnings for large contracts
npx hardhat compile

# Check specific contract
npx hardhat size-contracts
```

**Size Guidelines:**
- **< 50KB**: Safe, plenty of room
- **50-80KB**: Acceptable, monitor additions
- **80-100KB**: Approaching limit, optimize carefully
- **> 100KB**: Will fail deployment, must reduce

## FRONTEND INTEGRATION

### Frontend Transaction Issues (Legacy/Gas Estimation Problems)

**CRITICAL FOR AGENTS:** Frontend applications frequently encounter gas estimation issues when sending transactions to Polkadot networks. Always implement these strategies:

#### Method 1: Legacy Gas Estimation with Buffer

```javascript
// Use legacy gas estimation with safety buffer
const gasLimit = await provider.estimateGas({
  to: contractAddress,
  data: contractInterface.encodeFunctionData("functionName", [args]),
});

// Add 10-20% buffer for safety
const adjustedGasLimit = gasLimit.mul(120).div(100);

// Send transaction with explicit gas and legacy type
const tx = await contract.functionName(args, {
  gasLimit: adjustedGasLimit,
  type: 0, // Use legacy transaction type
});
```

#### Method 2: Fixed Gas Limits

```javascript
// Use fixed gas limits for predictable operations
const tx = await contract.functionName(args, {
  gasLimit: 100000, // Adjust based on function complexity
  type: 0, // Legacy transaction type
  gasPrice: ethers.utils.parseUnits("20", "gwei"), // Optional: set gas price
});
```

#### Method 3: Error Handling and Retry Logic

```javascript
async function sendTransactionWithRetry(
  contract,
  functionName,
  args,
  retries = 3
) {
  for (let i = 0; i < retries; i++) {
    try {
      // Try with estimated gas first
      const estimatedGas = await contract.estimateGas[functionName](...args);
      const tx = await contract[functionName](...args, {
        gasLimit: estimatedGas.mul(120).div(100),
        type: 0,
      });
      return tx;
    } catch (error) {
      if (i === retries - 1) throw error;

      // Fallback to fixed gas limit
      try {
        const tx = await contract[functionName](...args, {
          gasLimit: 200000, // Higher fixed limit
          type: 0,
        });
        return tx;
      } catch (fallbackError) {
        if (i === retries - 1) throw fallbackError;
      }
    }
  }
}
```

### Network Configuration for MetaMask

```javascript
const paseoConfig = {
  chainId: "0x1911f0a6", // 420420422 in hex
  chainName: "Polkadot Hub TestNet",
  nativeCurrency: {
    name: "PAS",
    symbol: "PAS",
    decimals: 18,
  },
  rpcUrls: ["https://testnet-passet-hub-eth-rpc.polkadot.io"],
  blockExplorerUrls: ["https://blockscout-passet-hub.parity-testnet.parity.io"],
};

// Add network to MetaMask
await window.ethereum.request({
  method: "wallet_addEthereumChain",
  params: [paseoConfig],
});
```

### Contract Interaction with Ethers.js

```javascript
import { ethers } from "ethers";

// Connect to Paseo
const provider = new ethers.JsonRpcProvider(
  "https://testnet-passet-hub-eth-rpc.polkadot.io"
);

// Contract instance
const contract = new ethers.Contract(contractAddress, abi, signer);

// Call functions
const result = await contract.someFunction();
```

## TESTING AND VERIFICATION

### Compilation Verification

```bash
npx hardhat compile
# Expected output: "Successfully compiled X Solidity files"
# Should NOT show contract size warnings for contracts <100KB
```

### Deployment Verification

1. **Successful Deployment Output**:

```
[ YourModule ] successfully deployed 🚀

Deployed Addresses
YourModule#YourContract - 0x1234567890abcdef...
```

2. **Block Explorer Verification**:

- Visit https://blockscout-passet-hub.parity-testnet.parity.io
- Search for contract address
- Verify contract creation transaction

3. **Contract Interaction Test**:

```bash
npx hardhat console --network passetHub
> const Contract = await ethers.getContractFactory("YourContract");
> const contract = Contract.attach("0x...");
> await contract.someFunction();
```

## DEBUGGING STRATEGIES

### Check Network Connectivity

```bash
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' \
  https://testnet-passet-hub-eth-rpc.polkadot.io
```

### Verify Account Balance

```bash
npx hardhat console --network passetHub
> await ethers.provider.getBalance("YOUR_ADDRESS")
```

### Clean Build and Deploy

```bash
npx hardhat clean
rm -rf ignition/deployments/
npx hardhat compile
npx hardhat ignition deploy ./ignition/modules/YourModule.js --network passetHub
```

### Transaction Tracking

If deployment fails:

1. Check block explorer for account transactions
2. Look for failed transactions with gas errors
3. Use `npx hardhat ignition track-tx <txHash> <deploymentId> --network passetHub`

## BEST PRACTICES

### Development Workflow

1. **Start Simple**: Deploy basic contracts first to verify setup
2. **Optimize Early**: Check contract sizes during development
3. **Test Locally**: Use local hardhat network for initial testing
4. **Incremental Deployment**: Deploy components separately if too large
5. **Document Addresses**: Keep track of all deployed contract addresses

### Contract Design for Paseo

1. **Minimize Dependencies**: Avoid heavy libraries
2. **Custom Implementations**: Write minimal versions of standard contracts
3. **Modular Design**: Split functionality across multiple contracts
4. **Gas Optimization**: Use efficient data structures and algorithms
5. **Proxy Patterns**: Consider upgradeable contracts for complex logic

### Security Considerations

1. **Private Key Management**: Always use hardhat vars, never commit keys
2. **Test Network Only**: Paseo is for testing, not production value
3. **Code Verification**: Verify contracts on block explorer when possible
4. **Access Controls**: Implement proper ownership and permission systems

## REFERENCE COMMANDS

### Hardhat Essential Commands

```bash
# Project setup
npm install --save-dev @parity/hardhat-polkadot solc@0.8.28
npm install --force @nomicfoundation/hardhat-toolbox
npx hardhat-polkadot init

# Configuration
npx hardhat vars set PRIVATE_KEY
npx hardhat vars list

# Development
npx hardhat compile
npx hardhat clean
npx hardhat test

# Deployment
npx hardhat ignition deploy ./ignition/modules/Module.js --network passetHub
rm -rf ignition/deployments/  # Clean deployment state

# Debugging
npx hardhat console --network passetHub
npx hardhat node  # Local development
```

### Foundry-Polkadot Essential Commands

```bash
# Installation
curl -L https://raw.githubusercontent.com/paritytech/foundry-polkadot/refs/heads/master/foundryup/install | bash
foundryup-polkadot

# Project setup
forge init my-project
cd my-project

# Compilation
forge build --resolc
forge build --resolc --resolc-optimizer-mode 3
forge clean

# Deployment
forge create src/Contract.sol:Contract \
    --rpc-url https://testnet-passet-hub-eth-rpc.polkadot.io \
    --private-key $PRIVATE_KEY \
    --resolc

# Contract interaction
cast call <address> "function()" --rpc-url <rpc-url>
cast send <address> "function(uint256)" 123 \
    --rpc-url <rpc-url> --private-key $PRIVATE_KEY

# Inspection and debugging
forge inspect Contract bytecode
cast code <address> --rpc-url <rpc-url>
cast balance <address> --rpc-url <rpc-url>
cast receipt <tx-hash> --rpc-url <rpc-url>
cast chain-id --rpc-url <rpc-url>
```

### Environment Variables

```bash
# Optional .env configuration
REPORT_GAS=true
ETHERSCAN_API_KEY=your_key_here
```

## POLKADOT CLOUD DEPLOYMENT (APILLON)

### Setting Up Apillon Account and Website UUID

**CRITICAL FOR AGENTS:** When deploying frontend applications to Polkadot Cloud, follow these steps:

#### Step 1: Create Apillon Account

**INSTRUCT USER TO:**

1. **Visit Apillon Console:** https://app.apillon.io
2. **Register Account:** Use email and create secure password
3. **Verify Email:** Complete email verification process
4. **Connect Wallet:** Link your Polkadot/Substrate wallet for payments
5. **Generate API Credentials:**
   - Go to **Settings** → **API Keys**
   - Click **Create New API Key**
   - Name it (e.g., "Hackathon Project")
   - Copy **API Key** and **API Secret** immediately
   - Store securely - API Secret is only shown once

#### Step 2: Create Website Project

**INSTRUCT USER TO:**

1. **Navigate to Hosting Section:** In Apillon console
2. **Create New Website:** Click "New Website" button
3. **Configure Project:**
   ```
   Project Name: [Your Project Name]
   Environment: Production
   Domain: [Optional custom domain]
   ```
4. **Copy Website UUID:** After creation, copy the generated UUID (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
5. **Provide UUID to Agent:** Share the Website UUID so the agent can configure deployment

#### Step 3: Get Website UUID for Deployment

```bash
# Example UUID format
WEBSITE_UUID="12345678-1234-5678-9abc-123456789def"
```

### MCP Setup for Polkadot Cloud Hosting

**Model Context Protocol (MCP) Configuration:**

#### Step 1: MCP Server Configuration

**CRITICAL FOR AGENTS:** Configure your MCP client to use the Apillon MCP server.

##### For Claude Desktop:

Add this to your MCP configuration file:

```json
{
  "mcpServers": {
    "apillon-mcp-server": {
      "command": "npx",
      "args": ["-y", "@apillon/mcp-server"],
      "env": {
        "APILLON_API_KEY": "<APILLON_API_KEY>",
        "APILLON_API_SECRET": "<APILLON_API_SECRET>"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/your-username/Desktop"
      ]
    }
  }
}
```

**Claude Desktop Configuration Steps:**

1. **Locate MCP config file:** Usually at `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS)
2. **Add Apillon server:** Insert the configuration above
3. **Replace placeholders:** Update `<APILLON_API_KEY>` and `<APILLON_API_SECRET>` with actual values
4. **Update filesystem path:** Change `/Users/your-username/Desktop` to your project directory
5. **Restart Claude Desktop:** Required for MCP changes to take effect

##### For Cursor IDE:

**Cursor MCP Setup:**

1. **Install MCP extension:** In Cursor, go to Extensions and search for "Model Context Protocol"
2. **Open Cursor settings:** `Cmd/Ctrl + ,` → Search "MCP"
3. **Add server configuration:**

```json
{
  "mcp.servers": {
    "apillon-mcp-server": {
      "command": "npx",
      "args": ["-y", "@apillon/mcp-server"],
      "env": {
        "APILLON_API_KEY": "<APILLON_API_KEY>",
        "APILLON_API_SECRET": "<APILLON_API_SECRET>"
      }
    }
  }
}
```

**Cursor Configuration Steps:**

1. **Open settings.json:** `Cmd/Ctrl + Shift + P` → "Preferences: Open Settings (JSON)"
2. **Add MCP configuration:** Insert the above configuration
3. **Replace placeholders:** Update API credentials
4. **Restart Cursor:** Required for MCP changes to take effect
5. **Verify connection:** Check MCP status in Cursor's command palette

#### Step 2: Install Apillon CLI (Alternative Method)

```bash
npm install -g @apillon/cli
```

#### Step 3: Configure Authentication

```bash
# Login to Apillon
apillon login

# Verify authentication
apillon whoami
```

#### Step 3: Configure MCP for Automated Deployment

Create `.apillon.json` in project root:

```json
{
  "websites": [
    {
      "uuid": "YOUR_WEBSITE_UUID_HERE",
      "name": "Your Project Name",
      "source": "./dist",
      "environment": "production"
    }
  ]
}
```

#### Step 4: MCP Deployment Script

```bash
#!/bin/bash
# deploy-to-polkadot-cloud.sh

# Build the project
npm run build

# Deploy to Apillon
apillon hosting deploy \
  --uuid $WEBSITE_UUID \
  --source ./dist \
  --environment production

# Verify deployment
apillon hosting info --uuid $WEBSITE_UUID
```

#### Step 5: Environment Variables

```bash
# Set in your environment
export APILLON_API_KEY="your_api_key_here"
export WEBSITE_UUID="your_website_uuid_here"
```

### Best Practices for Agents

1. **Configure MCP first:** Set up Apillon MCP server in your IDE (Claude Desktop or Cursor) before starting the deployment.
2. **Always use latest Apillon CLI:** `npm install -g @apillon/cli@latest`
3. **Secure credentials:** Store API keys and UUIDs as environment variables, never in code
4. **Guide user through account setup:** Clearly instruct users on Apillon account creation and API key generation
5. **Verify deployments:** Always check deployment status after upload
6. **Use production environment:** For final hackathon submissions
7. **Monitor costs:** Apillon uses pay-per-use model
8. **Test locally first:** Always test builds before deploying
9. **Restart your IDE:** After MCP configuration changes (Claude Desktop or Cursor)
10. **Check MCP connection:** Verify Apillon MCP server is properly connected before deployment

## WRITING GUIDELINES FOR LLMs

When creating documentation or helping developers:

- [ ] **Reference writing-guidelines.md for documentation standards**
- [ ] Use active voice: "Deploy the contract" not "The contract should be deployed"
- [ ] Lead with results, not process
- [ ] Cut qualifiers: "very", "quite", "rather"
- [ ] Choose simple words over complex ones
- [ ] State conclusions first, explain if needed

## TROUBLESHOOTING CHECKLIST

### For Hardhat

**First: Try kitdot@latest init with fresh project and copy existing code**

When deployment fails, check:

- [ ] Used kitdot@latest init for proper setup (recommended)
- [ ] Hardhat config matches exact format above
- [ ] Private key set via `npx hardhat vars set PRIVATE_KEY`
- [ ] Account has sufficient PAS tokens
- [ ] Contract compiles without errors
- [ ] Contract size under 100KB
- [ ] Network connectivity to RPC endpoint
- [ ] No OpenZeppelin dependencies causing size issues
- [ ] Clean deployment state if resuming failed deployment

### For Foundry-Polkadot

When compilation or deployment fails, check:

- [ ] Installed foundry-polkadot (not standard Foundry)
- [ ] Using `--resolc` flag or `resolc_compile = true` in foundry.toml
- [ ] Private key set as environment variable (`$PRIVATE_KEY`)
- [ ] Account has sufficient PAS tokens
- [ ] Contract compiles with `forge build --resolc`
- [ ] Contract size under 100KB
- [ ] Bytecode starts with `0x505` (PolkaVM prefix)
- [ ] Network connectivity to RPC endpoint
- [ ] No OpenZeppelin dependencies causing size issues
- [ ] Using correct RPC URL in commands

## ADVANCED TROUBLESHOOTING

### GitHub Issue Trackers for Known Problems

When encountering issues not covered in this guide, search these official Parity GitHub repositories for known issues, workarounds, and solutions:

#### General Contract Issues

Search these pages for contract-related problems, deployment errors, and PolkaVM compatibility issues:

- **Page 1**: https://github.com/paritytech/contract-issues/issues?page=1
- **Page 2**: https://github.com/paritytech/contract-issues/issues?page=2
- **Page 3**: https://github.com/paritytech/contract-issues/issues?page=3
- **Page 4**: https://github.com/paritytech/contract-issues/issues?page=4
- **Page 5**: https://github.com/paritytech/contract-issues/issues?page=5

**Common issues found here:**
- PolkaVM bytecode compatibility problems
- Contract deployment failures
- RPC endpoint connectivity issues
- Gas estimation errors
- Network configuration problems

#### Hardhat-Polkadot Specific Issues

For Hardhat-related problems with Polkadot plugin:

- **Page 1**: https://github.com/paritytech/hardhat-polkadot/issues?page=1
- **Page 2**: https://github.com/paritytech/hardhat-polkadot/issues?page=2

**Common issues found here:**
- `@parity/hardhat-polkadot` plugin errors
- Resolc configuration problems
- Hardhat Ignition deployment issues
- Dependency conflicts with hardhat-toolbox
- Network configuration with `polkavm: true`

#### Foundry-Polkadot Specific Issues

For Foundry-Polkadot compiler and deployment problems:

- **Page 1**: https://github.com/paritytech/foundry-polkadot/issues?page=1
- **Page 2**: https://github.com/paritytech/foundry-polkadot/issues?page=2

**Common issues found here:**
- `--resolc` flag not recognized
- Resolc compiler installation problems
- `forge create` deployment failures
- `cast` command errors with PolkaVM
- `foundry.toml` configuration issues

### How to Search Issues Effectively

#### Step 1: Identify Your Error Type

Categorize your error:

- **Compilation Error**: Search foundry-polkadot or hardhat-polkadot issues
- **Deployment Error**: Search contract-issues or specific tool issues
- **Runtime Error**: Search contract-issues for PolkaVM execution problems
- **Configuration Error**: Search specific tool (hardhat or foundry) issues

#### Step 2: Extract Key Error Messages

Look for unique identifiers in your error:

```bash
# Example error
Error: initcode is too big: 125282

# Search term: "initcode too big"
# Search term: "125282"
# Search term: "contract size limit"
```

#### Step 3: Search GitHub Issues

**Using GitHub Search:**

```
# In GitHub search bar:
repo:paritytech/contract-issues "initcode is too big"
repo:paritytech/foundry-polkadot "--resolc flag"
repo:paritytech/hardhat-polkadot "polkavm true"
```

**Using Advanced Search:**

1. Go to the specific repository issues page
2. Use the search bar with filters:
   - `is:issue is:open` - Open issues only
   - `is:issue is:closed` - Include closed (solved) issues
   - `label:bug` - Bug reports
   - `label:enhancement` - Feature requests
   - Sort by: "Most commented" or "Recently updated"

#### Step 4: Check Issue Comments

- Read through entire thread, not just the initial post
- Solutions often appear in comments, not the original issue
- Look for Parity team responses (marked with contributor badge)
- Check if issue is marked as "resolved" or "fixed"

#### Step 5: Apply Workarounds

Common workaround patterns found in issues:

**Contract Size Issues:**
```solidity
// Mentioned in: paritytech/contract-issues#XX
// Solution: Remove OpenZeppelin, use minimal implementations
contract MinimalOwnable {
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
}
```

**Hardhat Configuration Issues:**
```javascript
// Mentioned in: paritytech/hardhat-polkadot#XX
// Solution: Explicit resolc version configuration
module.exports = {
  resolc: {
    version: "0.3.0",
    compilerSource: "npm",
  },
  networks: {
    passetHub: {
      polkavm: true, // Critical setting
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
    }
  }
};
```

**Foundry Build Issues:**
```bash
# Mentioned in: paritytech/foundry-polkadot#XX
# Solution: Clean build cache and force recompile
forge clean
forge build --resolc --force
```

### Creating New Issues

If you encounter a unique problem not found in existing issues:

#### Before Creating an Issue:

- [ ] Search all three repositories thoroughly
- [ ] Check closed issues (may be solved already)
- [ ] Verify you're using latest versions
- [ ] Test with minimal reproduction example
- [ ] Collect all error messages and logs

#### When Creating an Issue:

**Include this information:**

```markdown
**Environment:**
- Tool: Hardhat / Foundry-Polkadot
- Version: [forge --version output]
- OS: macOS / Linux / Windows
- Node.js: [node --version]
- Solidity: 0.8.28

**Problem Description:**
[Clear description of the issue]

**Steps to Reproduce:**
1. [Step 1]
2. [Step 2]
3. [Step 3]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Error Output:**
```
[Paste complete error message]
```

**Contract Code (if relevant):**
```solidity
[Minimal contract that reproduces issue]
```

**Configuration:**
```javascript
// hardhat.config.js or foundry.toml
[Your configuration]
```
```

#### Provide Minimal Reproduction

Create a minimal example that reproduces the issue:

```bash
# For Hardhat issues
npx create-hardhat-project test-reproduction
cd test-reproduction
npm install @parity/hardhat-polkadot
# Add minimal code that causes the issue

# For Foundry issues
forge init test-reproduction
cd test-reproduction
# Add minimal contract that causes the issue
forge build --resolc
```

### Community Resources

Beyond GitHub issues:

- **Polkadot Stack Exchange**: https://substrate.stackexchange.com/
  - Tag questions with `polkadot`, `smart-contracts`, `evm`
  - Search existing answers before posting

- **Polkadot Forum**: https://forum.polkadot.network/
  - Category: Technical Discussion → Smart Contracts
  - Check announcements for known issues

- **Discord Communities**:
  - Polkadot Technical Support
  - Substrate Developers

### Troubleshooting Workflow

```
1. Encounter Error
   ↓
2. Search This AGENTS.md Guide
   ↓ (If not found)
3. Search GitHub Issues (contract-issues, tool-specific)
   ↓ (If not found)
4. Search Polkadot Forum / Stack Exchange
   ↓ (If not found)
5. Check Polkadot Developer Docs
   ↓ (If not found)
6. Create New GitHub Issue with reproduction
```

### Keeping Track of Known Issues

**For Agents Working on Polkadot Projects:**

Create a `KNOWN_ISSUES.md` in your project documenting encountered problems:

```markdown
# Known Issues and Workarounds

## Contract Size Exceeds Limit
**Status**: Ongoing limitation
**Issue**: https://github.com/paritytech/contract-issues/issues/XX
**Workaround**: Remove OpenZeppelin, implement minimal versions
**Applied**: ✓ Implemented in src/SimpleOwnable.sol

## Gas Estimation Fails on Frontend
**Status**: Known bug in ethers.js integration
**Issue**: https://github.com/paritytech/contract-issues/issues/YY
**Workaround**: Use legacy transaction type and fixed gas limits
**Applied**: ✓ Implemented in src/utils/transactions.js
```

This helps track issues, solutions applied, and provides reference for other developers.

## LIMITATIONS AND WORKAROUNDS

### Current Limitations

- **Contract Size**: 100KB bytecode limit
- **OpenZeppelin**: Official libraries too large for PolkaVM
- **Network Stability**: Preview release, potential downtime
- **Debugging Tools**: Limited compared to mainnet
- **Documentation**: Sparse, community-driven solutions

### Recommended Workarounds

- **Size Issues**: Use PolkaVM-optimized OpenZeppelin contracts (https://github.com/papermoonio/openzeppelin-contracts-polkadot)
- **Complex Logic**: Split across multiple contracts
- **State Management**: Use events for off-chain data
- **User Experience**: Provide clear error messages
- **Testing**: Extensive local testing before deployment

This guide provides comprehensive information for successful smart contract deployment to Paseo TestNet using Claude Code, including all critical configurations, common issues, and optimization strategies.
