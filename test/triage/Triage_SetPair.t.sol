// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTax} from "../../src/MemeTax.sol";
import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";

/// @notice Checking the `missing-zero-check` lint on `setPair()` (report,
///         section 5). Not a numbered finding yet.
/// @dev `_transfer` skips the max wallet check when `to == pair`, but `pair`
///      is just whatever the owner set last, and it starts as address(0).
///      While it's 0, a sell into the real pool gets checked against
///      `maxWallet` like a normal holder. The pool holds much more than
///      `maxWallet`, so every sell reverts, but buys still work.
contract Triage_SetPair is Test {
    MockDexRouter internal router;

    address internal deployer = makeAddr("deployer");
    address internal marketing = makeAddr("marketing");
    address internal dev = makeAddr("dev");
    address internal pool = makeAddr("pair");
    address internal weth = makeAddr("weth");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    /// @dev Half the supply, much more than the 20,000e18 max wallet.
    uint256 internal constant LIQUIDITY = 500_000e18;

    function setUp() public {
        router = new MockDexRouter(weth);
        router.setPair(pool);
        vm.deal(address(router), 1_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          MemeTax (original)
    //////////////////////////////////////////////////////////////*/

    function test_triage_original_sells_revert_until_setPair_is_called() public {
        MemeTax token = _deployOriginal();
        assertEq(token.pair(), address(0), "pair starts unset");

        // Buying from the pool works, and there's no tax.
        vm.prank(pool);
        token.transfer(alice, 10_000e18);
        assertEq(token.balanceOf(alice), 10_000e18, "buy is untaxed");

        // The sell gets checked against maxWallet like the pool is a holder.
        vm.prank(alice);
        vm.expectRevert("MAX_WALLET");
        token.transfer(pool, 1_000e18);

        // After the owner sets the pair, the same sell works.
        vm.prank(deployer);
        token.setPair(pool);
        vm.prank(alice);
        token.transfer(pool, 1_000e18);
        assertEq(token.balanceOf(alice), 9_000e18, "sell works after setPair");
    }

    function test_triage_original_setPair_zero_turns_sells_off() public {
        MemeTax token = _deployOriginal();
        vm.prank(deployer);
        token.setPair(pool);
        vm.prank(deployer);
        token.transfer(alice, 10_000e18);

        // Normal state: selling works.
        vm.prank(alice);
        token.transfer(pool, 1_000e18);

        // No zero check, so the owner can set the pair back to 0.
        vm.prank(deployer);
        token.setPair(address(0));

        vm.prank(alice);
        vm.expectRevert("MAX_WALLET");
        token.transfer(pool, 1_000e18);

        // Buys still work, with no tax.
        vm.prank(pool);
        token.transfer(bob, 1_000e18);
        assertEq(token.balanceOf(bob), 1_000e18, "buy still works");
    }

    /*//////////////////////////////////////////////////////////////
                             MemeTaxFixed
    //////////////////////////////////////////////////////////////*/

    function test_triage_fixed_rejects_setPair_zero() public {
        MemeTaxFixed token = _deployFixed();
        vm.prank(deployer);
        vm.expectRevert(MemeTaxFixed.ZeroAddress.selector);
        token.setPair(address(0));
    }

    function test_triage_fixed_still_blocks_sells_until_setPair_is_called() public {
        MemeTaxFixed token = _deployFixed();
        assertEq(token.pair(), address(0), "pair still starts unset");

        vm.prank(pool);
        token.transfer(alice, 10_000e18);

        vm.prank(alice);
        vm.expectRevert(MemeTaxFixed.MaxWalletExceeded.selector);
        token.transfer(pool, 1_000e18);

        // Same as the original: once the pair is set, selling works again.
        vm.prank(deployer);
        token.setPair(pool);
        vm.prank(alice);
        token.transfer(pool, 1_000e18);
        assertEq(token.balanceOf(alice), 9_000e18, "sell works after setPair");
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deploys without calling `setPair`, then adds liquidity from the
    ///      deployer. The deployer is fee-exempt, so the max wallet check
    ///      doesn't apply to it.
    function _deployOriginal() internal returns (MemeTax token) {
        vm.startPrank(deployer);
        token = new MemeTax(address(router), marketing, dev);
        token.transfer(pool, LIQUIDITY);
        vm.stopPrank();
    }

    function _deployFixed() internal returns (MemeTaxFixed token) {
        vm.startPrank(deployer);
        token = new MemeTaxFixed(address(router), marketing, dev);
        token.transfer(pool, LIQUIDITY);
        vm.stopPrank();
    }
}
