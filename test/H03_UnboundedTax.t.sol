// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice H-03 (High) - `setTaxes()` has no upper bound.
contract H03_UnboundedTax is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 10_000e18);
    }

    function test_H03_owner_can_set_100_percent_sell_tax_after_launch() public {
        // Launch conditions look normal: 5% each way.
        assertEq(token.buyTax(), 5);
        assertEq(token.sellTax(), 5);

        // Nothing stops the owner from changing that in a single transaction.
        vm.prank(token.owner());
        token.setTaxes(0, 100);
        assertEq(token.sellTax(), 100, "sell tax is now 100%");

        uint256 pairBefore = token.balanceOf(pair);
        _sell(alice, 1_000e18);

        // Alice's sell delivers nothing to the pool: the token is a honeypot.
        assertEq(token.balanceOf(pair) - pairBefore, 0, "seller received nothing");
        assertEq(token.balanceOf(alice), 9_000e18, "alice still lost the tokens");
    }
}
