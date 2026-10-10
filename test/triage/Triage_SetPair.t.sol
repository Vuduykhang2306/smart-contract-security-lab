// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTax} from "../../src/MemeTax.sol";
import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";

/// @notice Triage of the `missing-zero-check` lint on `setPair()` (report,
///         section 5). Not a numbered finding yet.
/// @dev The max-wallet check in `_transfer` skips transfers to `pair`, and
///      `pair` is whatever the owner last set. It starts as address(0). While
///      it is unset, or set to zero, a sell into the real pool is checked
///      against `maxWallet` as if the pool were an ordinary holder. The pool
///      holds far more than `maxWallet`, so every sell reverts while buys keep
///      working.
contract Triage_SetPair is Test {
    MockDexRouter internal router;

    address internal deployer = makeAddr("deployer");
    address internal marketing = makeAddr("marketing");
    address internal dev = makeAddr("dev");
    address internal pool = makeAddr("pair");
    address internal weth = makeAddr("weth");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    /// @dev Half the supply, far above the 20,000e18 max wallet.
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

        // A buy from the pool goes through, and nothing is taxed.
        vm.prank(pool);
        token.transfer(alice, 10_000e18);
        assertEq(token.balanceOf(alice), 10_000e18, "buy is untaxed");

        // The sell is checked against maxWallet as if the pool were a holder.
        vm.prank(alice);
        vm.expectRevert("MAX_WALLET");
        token.transfer(pool, 1_000e18);

        // Once the owner sets the pair, the same sell goes through.
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

        // There is no zero check, so the owner can clear the pair.
        vm.prank(deployer);
        token.setPair(address(0));

        vm.prank(alice);
        vm.expectRevert("MAX_WALLET");
        token.transfer(pool, 1_000e18);

        // Buys still go through, untaxed.
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

        // Same recovery as the original: setting the pair unblocks the sell.
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
    ///      fee-exempt deployer, which skips the max-wallet check.
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
