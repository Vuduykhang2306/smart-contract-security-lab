// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";

/// @notice H-04 (High) - `_swapBack()` pays out `address(this).balance`
///         instead of what the swap returned, so the dividend pool goes to the
///         fee wallets too.
///
/// @dev I missed this one in the manual pass. It came up when I wrote INV-02
///      for the invariant suite. Once "every ETH the contract has promised must
///      be backed by its balance" was written down, the next question was which
///      paths move that balance, and `_swapBack` moves all of it.
contract H04_SwapBackSweepsDividendPool is BaseSetup {
    function setUp() public {
        _deploy();
        _fund(alice, 50_000e18);
        // Fees already collected and waiting to be swapped.
        _fund(address(token), 2_000e18);
    }

    function test_H04_fee_swap_sweeps_the_dividend_pool() public {
        // The project deposits 10 ETH of dividends for bob.
        vm.deal(deployer, 10 ether);
        vm.prank(deployer);
        token.depositDividend{value: 10 ether}(bob);

        assertEq(token.pendingDividend(bob), 10 ether, "bob is owed 10 ETH");
        assertEq(address(token).balance, 10 ether, "and the contract holds it");

        // A normal sell by another holder. No attacker and no special setup.
        _sell(alice, 1_000e18);

        // The swap returned 2 ETH for the 2,000 fee tokens. The fee wallets
        // received 12 ETH: the 2 they earned plus bob's entire 10.
        assertEq(marketing.balance, 6 ether, "marketing took half of everything");
        assertEq(dev.balance, 6 ether, "dev took the rest");
        assertEq(address(token).balance, 0, "the contract is empty");

        // Bob's entry didn't change, but there is no ETH behind it anymore.
        assertEq(token.pendingDividend(bob), 10 ether, "bob is still recorded as owed 10 ETH");

        vm.prank(bob);
        vm.expectRevert("ETH_TRANSFER_FAILED");
        token.claimDividend();
    }

    /// @dev Same property as INV-02, checked directly: what the contract owes
    ///      has to be covered by its balance. Here it isn't.
    function test_H04_eth_obligations_exceed_balance() public {
        vm.deal(deployer, 10 ether);
        vm.prank(deployer);
        token.depositDividend{value: 10 ether}(bob);

        _sell(alice, 1_000e18);

        uint256 obligations = token.pendingDividend(bob);
        assertGt(obligations, address(token).balance, "INV-02 is violated on the unfixed contract");
    }
}
