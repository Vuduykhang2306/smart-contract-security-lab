// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice L-01 (Low) - `amount / 100 * taxRate` divides before it multiplies.
contract L01_FeeRounding is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 10_000e18);
    }

    function test_L01_transfers_below_100_wei_are_untaxed() public {
        uint256 pairBefore = token.balanceOf(pair);

        _sell(alice, 99);

        assertEq(token.balanceOf(pair) - pairBefore, 99, "the full 99 wei reached the pair");
        assertEq(token.balanceOf(address(token)), 0, "no fee was collected");
    }

    function test_L01_one_wei_more_is_taxed_normally() public {
        uint256 pairBefore = token.balanceOf(pair);

        _sell(alice, 100);

        // 5% of 100 is 5, so only 95 should arrive.
        assertEq(token.balanceOf(pair) - pairBefore, 95, "5 wei was taxed");
        assertEq(token.balanceOf(address(token)), 5, "fee was collected");
    }

    function test_L01_rounding_also_truncates_ordinary_amounts() public {
        uint256 pairBefore = token.balanceOf(pair);

        // 199 wei should be taxed 9.95 -> 9. The buggy formula charges 5.
        _sell(alice, 199);

        assertEq(token.balanceOf(address(token)), 5, "buggy formula undercharges");
        assertEq(token.balanceOf(pair) - pairBefore, 194, "seller keeps the difference");
    }
}
