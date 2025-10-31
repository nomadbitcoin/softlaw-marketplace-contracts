// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Initializable.sol";

/**
 * @dev Minimal implementation for PolkaVM deployment
 * Removes rollback protection to reduce bytecode size
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
abstract contract UUPSUpgradeable is Initializable {
    /// @dev Emitted when the implementation is upgraded
    event Upgraded(address indexed implementation);

    /// @dev ERC-1967 implementation storage slot
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Initializes the UUPS upgradeable contract
     */
    function __UUPSUpgradeable_init() internal {
        // No initialization needed for minimal implementation
    }

    /**
     * @dev Modifier to restrict functions to only be called via delegatecall
     */
    modifier onlyProxy() {
        require(address(this) != _getImplementation(), "Function must be called through delegatecall");
        _;
    }

    /**
     * @dev Upgrade the implementation of the proxy
     */
    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    /**
     * @dev Upgrade the implementation and call a function on the new implementation
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCall(newImplementation, data, true);
    }

    /**
     * @dev Function that should revert when msg.sender is not authorized to upgrade the contract
     * Must be overridden in derived contracts
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev Perform implementation upgrade with security checks and optional setup call
     */
    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            (bool success, ) = newImplementation.delegatecall(data);
            require(success, "UUPSUpgradeable: delegatecall failed");
        }
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot
     */
    function _setImplementation(address newImplementation) private {
        require(newImplementation.code.length > 0, "ERC1967: new implementation is not a contract");
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Returns the current implementation address from ERC-1967 slot
     */
    function _getImplementation() private view returns (address implementation) {
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }
}
