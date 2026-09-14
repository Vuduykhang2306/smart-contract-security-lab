// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";
import {RejectingWallet} from "./mocks/RejectingWallet.sol";

/// @notice M-02 (Medium) - the ETH payouts in `_swapBack()` ignore their return
///         values, so fee distribution can fail without anyone noticing.
contract M02_UncheckedEthTransfer is BaseSetup {
    RejectingWallet internal marketingSafe;
    RejectingWallet internal devSafe;

    function setUp() public {
        marketingSafe = new RejectingWallet();
        devSafe = new RejectingWallet();

        _deployWith(address(marketingSafe), address(devSafe));
        _fund(alice, 50_000e18);
        _fund(address(token), 2_000e18);
    }

    function test_M02_fee_distribution_fails_silently() public {
        // The sell succeeds and looks completely normal on-chain.
        _sell(alice, 1_000e18);

        // The swap ran: the fee tokens left the contract and ETH came back.
        assertEq(token.balanceOf(pair), 2_000e18 + 950e18, "fee tokens reached the pair");

        // But neither fee wallet was paid, and nobody was told.
        assertEq(address(marketingSafe).balance, 0, "marketing received nothing");
        assertEq(address(devSafe).balance, 0, "dev received nothing");

        // The ETH is silently stranded in the token contract, with no
        // withdrawal function to recover it.
        assertEq(address(token).balance, 2 ether, "proceeds are stuck in the token");
    }
}
