// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice L-02 (Low) - `setMaxWallet()` accepts zero and freezes the token.
contract L02_MaxWalletZero is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 10_000e18);
    }

    function test_L02_zero_max_wallet_blocks_every_buy_and_transfer() public {
        vm.prank(token.owner());
        token.setMaxWallet(0);

        // Wallet-to-wallet transfers are dead.
        vm.prank(alice);
        vm.expectRevert("MAX_WALLET");
        token.transfer(bob, 1e18);

        // Buys are dead too.
        _fund(pair, 1_000e18);
        vm.prank(pair);
        vm.expectRevert("MAX_WALLET");
        token.transfer(bob, 1e18);

        // Selling still works, so the pool can only be drained from here on.
        _sell(alice, 1_000e18);
        assertGt(token.balanceOf(pair), 0, "sells are unaffected");
    }
}
