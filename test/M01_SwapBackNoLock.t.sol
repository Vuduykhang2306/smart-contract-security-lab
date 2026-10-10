// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice M-01 (Medium) - `_swapBack()` has no reentrancy lock.
/// @dev Right now re-entry is only stopped because
///      `isExcludedFromFee[address(token)]` is true. That mapping is a normal
///      admin setting, and nothing in the contract says it is also acting as
///      a reentrancy guard.
contract M01_SwapBackNoLock is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 50_000e18);
        // Collected fees waiting to be swapped.
        _fund(address(token), 2_000e18);
    }

    function test_M01_sell_works_while_the_implicit_guard_holds() public {
        assertTrue(token.isExcludedFromFee(address(token)), "token is fee-exempt on deploy");

        _sell(alice, 1_000e18);

        assertEq(token.balanceOf(address(token)), 50e18, "only the new 5% fee remains");
        assertGt(dev.balance, 0, "fees were distributed");
    }

    function test_M01_un_excluding_the_token_contract_bricks_every_sell() public {
        // An admin call that doesn't look related to the swap at all.
        vm.prank(token.owner());
        token.setExcludedFromFee(address(token), false);

        // The router moves the fee tokens to the pair, which re-enters
        // `_transfer`, which triggers `_swapBack()` again, and so on until the
        // call stack is exhausted. Every sell now reverts.
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(pair, 1_000e18);

        // Alice's balance didn't move, so she can't get out.
        assertEq(token.balanceOf(alice), 50_000e18, "alice could not sell");
    }
}
