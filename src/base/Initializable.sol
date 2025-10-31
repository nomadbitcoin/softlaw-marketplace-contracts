// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @dev Minimal implementation for PolkaVM deployment
 * Removes nested initializer support and complex reentrancy guards to reduce bytecode size
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
abstract contract Initializable {
    /**
     * @dev Storage slot for initialization state
     * 0 = not initialized
     * 1 = initialized
     * 2 = initializers disabled
     */
    uint8 private _initialized;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice
     */
    modifier initializer() {
        require(_initialized == 0, "Initializable: contract is already initialized");
        _initialized = 1;
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization
     * Used in constructors of implementation contracts to prevent initialization
     */
    function _disableInitializers() internal {
        _initialized = 2;
    }
}
