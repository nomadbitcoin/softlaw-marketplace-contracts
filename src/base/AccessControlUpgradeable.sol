// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Initializable.sol";

/**
 * @dev Minimal implementation for PolkaVM deployment
 * Removes role hierarchy to reduce bytecode size
 * Based on OpenZeppelin Contracts (MIT License)
 * Source: https://github.com/OpenZeppelin/openzeppelin-contracts
 */
abstract contract AccessControlUpgradeable is Initializable {
    /// @dev Emitted when account is granted role
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /// @dev Emitted when account is revoked role
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /// @dev Default admin role identifier
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev Role assignments: role => account => hasRole
    mapping(bytes32 => mapping(address => bool)) private _roles;

    /**
     * @dev Initializes the contract
     */
    function __AccessControl_init() internal {
        // No initialization needed for minimal implementation
    }

    /**
     * @dev Modifier that checks that an account has a specific role
     */
    modifier onlyRole(bytes32 role) {
        require(hasRole(role, msg.sender), "AccessControl: account missing role");
        _;
    }

    /**
     * @dev Returns true if account has been granted role
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _roles[role][account];
    }

    /**
     * @dev Returns the admin role that controls role
     * Minimal implementation: all roles are controlled by DEFAULT_ADMIN_ROLE
     */
    function getRoleAdmin(bytes32 /* role */) public view virtual returns (bytes32) {
        return DEFAULT_ADMIN_ROLE;
    }

    /**
     * @dev Grants role to account
     * Only callable by accounts with DEFAULT_ADMIN_ROLE
     */
    function grantRole(bytes32 role, address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes role from account
     * Only callable by accounts with DEFAULT_ADMIN_ROLE
     */
    function revokeRole(bytes32 role, address account) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes role from the calling account
     */
    function renounceRole(bytes32 role, address account) public virtual {
        require(account == msg.sender, "AccessControl: can only renounce roles for self");
        _revokeRole(role, account);
    }

    /**
     * @dev Grants role to account (internal)
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        if (!hasRole(role, account)) {
            _roles[role][account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    /**
     * @dev Revokes role from account (internal)
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            _roles[role][account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    /**
     * @dev ERC-165 support
     */
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 interface ID for ERC165
            interfaceId == 0x7965db0b;   // ERC165 interface ID for IAccessControl
    }
}
