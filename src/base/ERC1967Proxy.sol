// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @dev Minimal ERC1967 proxy implementation for testing
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
contract ERC1967Proxy {
    /// @dev Storage slot with the address of the current implementation (ERC-1967)
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Initializes the proxy with an implementation and optional data
     */
    constructor(address implementation, bytes memory data) payable {
        _setImplementation(implementation);
        if (data.length > 0) {
            (bool success,) = implementation.delegatecall(data);
            require(success, "ERC1967Proxy: delegatecall failed");
        }
    }

    /**
     * @dev Fallback function that delegates calls to the implementation
     */
    fallback() external payable {
        _delegate(_getImplementation());
    }

    /**
     * @dev Receive function for plain ether transfers
     */
    receive() external payable {
        _delegate(_getImplementation());
    }

    /**
     * @dev Delegates the current call to implementation
     */
    function _delegate(address implementation) private {
        assembly {
            // Copy msg.data
            calldatacopy(0, 0, calldatasize())

            // Call the implementation
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot
     */
    function _setImplementation(address newImplementation) private {
        require(newImplementation.code.length > 0, "ERC1967Proxy: new implementation is not a contract");
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    /**
     * @dev Returns the current implementation address
     */
    function _getImplementation() private view returns (address implementation) {
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }
}
