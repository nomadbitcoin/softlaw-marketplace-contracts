// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Initializable.sol";

/**
 * @dev Minimal implementation for PolkaVM deployment
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
abstract contract PausableUpgradeable is Initializable {
    /// @dev Emitted when the pause is triggered by account
    event Paused(address account);

    /// @dev Emitted when the pause is lifted by account
    event Unpaused(address account);

    /// @dev Pause state storage slot
    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state
     */
    function __Pausable_init() internal {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused
     */
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused
     */
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal state
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
