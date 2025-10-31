// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/base/Initializable.sol";

contract InitializableTest is Test {
    MockInitializable public initializable;

    function setUp() public {
        initializable = new MockInitializable();
    }

    function testInitialize() public {
        initializable.initialize();
        assertTrue(initializable.initialized(), "Should be initialized");
    }

    function testCannotInitializeTwice() public {
        initializable.initialize();
        vm.expectRevert("Initializable: contract is already initialized");
        initializable.initialize();
    }

    function testDisableInitializers() public {
        MockInitializableWithConstructor mock = new MockInitializableWithConstructor();
        vm.expectRevert("Initializable: contract is already initialized");
        mock.initialize();
    }
}

contract MockInitializable is Initializable {
    bool public initialized;

    function initialize() public initializer {
        initialized = true;
    }
}

contract MockInitializableWithConstructor is Initializable {
    bool public initialized;

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        initialized = true;
    }
}
