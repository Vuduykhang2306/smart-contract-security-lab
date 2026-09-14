// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice H-02 (High) - `setBlacklist()` has no access control.
contract H02_BlacklistAccessControl is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 10_000e18);
    }

    function test_H02_any_address_can_freeze_any_holder() public {
        assertNotEq(mallory, token.owner(), "mallory is not the owner");

        // Mallory is an ordinary address with no role of any kind.
        vm.prank(mallory);
        token.setBlacklist(alice, true);

        assertTrue(token.isBlacklisted(alice), "alice was blacklisted by a stranger");

        // Alice can no longer move or sell her tokens.
        vm.prank(alice);
        vm.expectRevert("BLACKLISTED");
        token.transfer(bob, 1e18);

        vm.prank(alice);
        vm.expectRevert("BLACKLISTED");
        token.transfer(pair, 1e18);
    }

    function test_H02_attacker_can_also_unblacklist_itself() public {
        vm.prank(token.owner());
        token.setBlacklist(mallory, true);

        vm.prank(mallory);
        token.setBlacklist(mallory, false);

        assertFalse(token.isBlacklisted(mallory), "owner's blacklist entry was reverted by the target");
    }
}
