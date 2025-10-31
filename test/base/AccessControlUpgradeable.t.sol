// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/base/AccessControlUpgradeable.sol";

contract AccessControlUpgradeableTest is Test {
    MockAccessControl public accessControl;
    bytes32 public constant TEST_ROLE = keccak256("TEST_ROLE");
    address public admin = address(1);
    address public user = address(2);

    function setUp() public {
        accessControl = new MockAccessControl();
        accessControl.initialize(admin);
    }

    function testGrantRole() public {
        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);
        assertTrue(accessControl.hasRole(TEST_ROLE, user), "User should have test role");
    }

    function testRevokeRole() public {
        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);
        vm.prank(admin);
        accessControl.revokeRole(TEST_ROLE, user);
        assertFalse(accessControl.hasRole(TEST_ROLE, user), "User should not have test role");
    }

    function testRenounceRole() public {
        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);
        vm.prank(user);
        accessControl.renounceRole(TEST_ROLE, user);
        assertFalse(accessControl.hasRole(TEST_ROLE, user), "User should have renounced role");
    }

    function testCannotRenounceForOthers() public {
        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);
        vm.prank(admin);
        vm.expectRevert("AccessControl: can only renounce roles for self");
        accessControl.renounceRole(TEST_ROLE, user);
    }

    function testOnlyRoleModifier() public {
        vm.prank(user);
        vm.expectRevert("AccessControl: account missing role");
        accessControl.restrictedFunction();

        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);

        vm.prank(user);
        accessControl.restrictedFunction();
    }

    function testGetRoleAdmin() public {
        assertEq(
            accessControl.getRoleAdmin(TEST_ROLE),
            accessControl.DEFAULT_ADMIN_ROLE(),
            "All roles should be managed by DEFAULT_ADMIN_ROLE"
        );
    }

    function testSupportsInterface() public {
        assertTrue(accessControl.supportsInterface(0x01ffc9a7), "Should support ERC165");
        assertTrue(accessControl.supportsInterface(0x7965db0b), "Should support IAccessControl");
        assertFalse(accessControl.supportsInterface(0xffffffff), "Should not support random interface");
    }

    function testOnlyAdminCanGrantRoles() public {
        vm.prank(user);
        vm.expectRevert("AccessControl: account missing role");
        accessControl.grantRole(TEST_ROLE, user);
    }

    function testOnlyAdminCanRevokeRoles() public {
        vm.prank(admin);
        accessControl.grantRole(TEST_ROLE, user);

        vm.prank(user);
        vm.expectRevert("AccessControl: account missing role");
        accessControl.revokeRole(TEST_ROLE, user);
    }
}

contract MockAccessControl is AccessControlUpgradeable {
    bytes32 public constant TEST_ROLE = keccak256("TEST_ROLE");

    function initialize(address admin) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function restrictedFunction() public onlyRole(TEST_ROLE) {
        // Do nothing
    }
}
