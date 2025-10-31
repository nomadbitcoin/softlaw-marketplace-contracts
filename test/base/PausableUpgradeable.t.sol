// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../src/base/PausableUpgradeable.sol";

contract PausableUpgradeableTest is Test {
    MockPausable public pausable;

    function setUp() public {
        pausable = new MockPausable();
        pausable.initialize();
    }

    function testInitiallyNotPaused() public {
        assertFalse(pausable.paused(), "Should not be paused initially");
    }

    function testPause() public {
        pausable.pause();
        assertTrue(pausable.paused(), "Should be paused");
    }

    function testUnpause() public {
        pausable.pause();
        pausable.unpause();
        assertFalse(pausable.paused(), "Should be unpaused");
    }

    function testWhenNotPausedModifier() public {
        pausable.normalFunction();
        pausable.pause();
        vm.expectRevert("Pausable: paused");
        pausable.normalFunction();
    }

    function testWhenPausedModifier() public {
        vm.expectRevert("Pausable: not paused");
        pausable.pausedOnlyFunction();
        pausable.pause();
        pausable.pausedOnlyFunction();
    }

    function testCannotPauseTwice() public {
        pausable.pause();
        vm.expectRevert("Pausable: paused");
        pausable.pause();
    }

    function testCannotUnpauseWhenNotPaused() public {
        vm.expectRevert("Pausable: not paused");
        pausable.unpause();
    }
}

contract MockPausable is PausableUpgradeable {
    function initialize() public initializer {
        __Pausable_init();
    }

    function pause() public {
        _pause();
    }

    function unpause() public {
        _unpause();
    }

    function normalFunction() public whenNotPaused {
        // Do nothing
    }

    function pausedOnlyFunction() public whenPaused {
        // Do nothing
    }
}
