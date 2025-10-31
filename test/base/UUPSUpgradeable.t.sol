// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/base/UUPSUpgradeable.sol";
import "../../src/base/AccessControlUpgradeable.sol";

contract UUPSUpgradeableTest is Test {
    ERC1967Proxy public proxy;
    MockUUPS public implementation;
    MockUUPS public proxyContract;
    MockUUPSV2 public implementationV2;
    address public admin = address(1);

    function setUp() public {
        // Deploy implementation
        implementation = new MockUUPS();

        // Deploy proxy pointing to implementation
        bytes memory initData = abi.encodeWithSelector(MockUUPS.initialize.selector, admin);
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Wrap proxy in contract interface
        proxyContract = MockUUPS(address(proxy));
    }

    function testInitialImplementation() public {
        assertEq(proxyContract.version(), 1, "Initial version should be 1");
        assertTrue(proxyContract.hasRole(proxyContract.DEFAULT_ADMIN_ROLE(), admin), "Admin should have role");
    }

    function testUpgradeTo() public {
        // Deploy new implementation
        implementationV2 = new MockUUPSV2();

        // Upgrade
        vm.prank(admin);
        proxyContract.upgradeTo(address(implementationV2));

        // Verify upgrade
        assertEq(proxyContract.version(), 2, "Version should be upgraded to 2");
    }

    function testUpgradeToAndCall() public {
        // Deploy new implementation
        implementationV2 = new MockUUPSV2();

        // Upgrade with call
        bytes memory data = abi.encodeWithSelector(MockUUPSV2.setValue.selector, 42);
        vm.prank(admin);
        proxyContract.upgradeToAndCall(address(implementationV2), data);

        // Verify upgrade and call
        assertEq(proxyContract.version(), 2, "Version should be upgraded to 2");
        assertEq(MockUUPSV2(address(proxyContract)).value(), 42, "Value should be set");
    }

    function testCannotUpgradeWithoutRole() public {
        implementationV2 = new MockUUPSV2();

        vm.prank(address(2));
        vm.expectRevert("AccessControl: account missing role");
        proxyContract.upgradeTo(address(implementationV2));
    }

    function testCannotUpgradeToNonContract() public {
        vm.prank(admin);
        vm.expectRevert("ERC1967: new implementation is not a contract");
        proxyContract.upgradeTo(address(999));
    }

    function testProxyUpgradeFlow() public {
        // Test the complete upgrade flow through proxy
        implementationV2 = new MockUUPSV2();

        // Verify initial state
        assertEq(proxyContract.version(), 1, "Should start with version 1");

        // Perform upgrade
        vm.prank(admin);
        proxyContract.upgradeTo(address(implementationV2));

        // Verify upgrade succeeded
        assertEq(proxyContract.version(), 2, "Should upgrade to version 2");
    }
}

// Minimal ERC1967Proxy for testing
contract ERC1967Proxy {
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation, bytes memory data) {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, implementation)
        }
        if (data.length > 0) {
            (bool success, ) = implementation.delegatecall(data);
            require(success, "Initialization failed");
        }
    }

    fallback() external payable {
        address implementation;
        assembly {
            implementation := sload(_IMPLEMENTATION_SLOT)
        }
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

contract MockUUPS is UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
    }

    function version() public pure virtual returns (uint256) {
        return 1;
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}
}

contract MockUUPSV2 is MockUUPS {
    uint256 public value;

    function version() public pure override returns (uint256) {
        return 2;
    }

    function setValue(uint256 _value) public {
        value = _value;
    }
}
