// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTaxFixed} from "../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "./mocks/MockDexRouter.sol";
import {RejectingWallet} from "./mocks/RejectingWallet.sol";
import {ReentrantClaimer} from "./attackers/ReentrantClaimer.sol";

/// @notice Retest suite. Every proof of concept from the report is replayed
///         against `MemeTaxFixed` and asserted to fail.
contract Retest_Fixed is Test {
    MemeTaxFixed internal token;
    MockDexRouter internal router;

    address internal deployer = makeAddr("deployer");
    address internal marketing = makeAddr("marketing");
    address internal dev = makeAddr("dev");
    address internal pair = makeAddr("pair");
    address internal weth = makeAddr("weth");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal mallory = makeAddr("mallory");

    function setUp() public {
        _deployWith(marketing, dev);
    }

    function _deployWith(address _marketing, address _dev) internal {
        router = new MockDexRouter(weth);
        router.setPair(pair);
        vm.deal(address(router), 1_000 ether);

        vm.startPrank(deployer);
        token = new MemeTaxFixed(address(router), _marketing, _dev);
        token.setPair(pair);
        vm.stopPrank();
    }

    function _fund(address to, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(to, amount);
    }

    function _sell(address seller, uint256 amount) internal {
        vm.prank(seller);
        token.transfer(pair, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              H-01
    //////////////////////////////////////////////////////////////*/

    function test_retest_H01_reentrancy_no_longer_drains_the_pool() public {
        ReentrantClaimer attacker = new ReentrantClaimer(address(token));

        vm.deal(deployer, 10 ether);
        vm.startPrank(deployer);
        token.depositDividend{value: 1 ether}(address(attacker));
        token.depositDividend{value: 9 ether}(alice);
        vm.stopPrank();

        attacker.attack();

        assertEq(address(attacker).balance, 1 ether, "attacker gets exactly its share");
        assertEq(attacker.reentries(), 0, "no re-entry was possible");
        assertEq(address(token).balance, 9 ether, "alice's 9 ETH is untouched");

        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, 9 ether, "alice can still claim in full");
    }

    /*//////////////////////////////////////////////////////////////
                              H-02
    //////////////////////////////////////////////////////////////*/

    function test_retest_H02_blacklist_is_owner_only() public {
        vm.prank(mallory);
        vm.expectRevert(MemeTaxFixed.NotOwner.selector);
        token.setBlacklist(alice, true);

        assertFalse(token.isBlacklisted(alice), "alice was never blacklisted");
    }

    /*//////////////////////////////////////////////////////////////
                              H-03
    //////////////////////////////////////////////////////////////*/

    function test_retest_H03_tax_is_capped() public {
        vm.prank(token.owner());
        vm.expectRevert(abi.encodeWithSelector(MemeTaxFixed.TaxTooHigh.selector, 100, 10));
        token.setTaxes(0, 100);

        // The legitimate range still works.
        vm.prank(token.owner());
        token.setTaxes(3, 10);
        assertEq(token.sellTax(), 10, "10% is still allowed");
    }

    /*//////////////////////////////////////////////////////////////
                              M-01
    //////////////////////////////////////////////////////////////*/

    function test_retest_M01_swap_lock_survives_un_excluding_the_token() public {
        _fund(alice, 50_000e18);
        _fund(address(token), 2_000e18);

        vm.prank(token.owner());
        token.setExcludedFromFee(address(token), false);

        // The same admin action that bricked the vulnerable contract is harmless.
        _sell(alice, 1_000e18);

        assertEq(token.balanceOf(alice), 49_000e18, "the sell went through");
        assertGt(token.feesOwed(dev), 0, "fees were still accounted");
    }

    /*//////////////////////////////////////////////////////////////
                              M-02
    //////////////////////////////////////////////////////////////*/

    function test_retest_M02_fees_are_accrued_not_pushed() public {
        RejectingWallet marketingSafe = new RejectingWallet();
        RejectingWallet devSafe = new RejectingWallet();
        _deployWith(address(marketingSafe), address(devSafe));

        _fund(alice, 50_000e18);
        _fund(address(token), 2_000e18);

        _sell(alice, 1_000e18);

        // Nothing is silently lost: the full 2 ETH of proceeds is attributed.
        assertEq(token.feesOwed(address(marketingSafe)), 1 ether, "marketing share recorded");
        assertEq(token.feesOwed(address(devSafe)), 1 ether, "dev share recorded");
        assertEq(address(token).balance, 2 ether, "backed one-for-one by the balance");
    }

    function test_retest_M02_working_wallet_can_withdraw() public {
        _fund(alice, 50_000e18);
        _fund(address(token), 2_000e18);

        _sell(alice, 1_000e18);

        uint256 owed = token.feesOwed(dev);
        assertGt(owed, 0, "dev is owed fees");

        vm.prank(dev);
        token.withdrawFees();

        assertEq(dev.balance, owed, "dev pulled its fees");
        assertEq(token.feesOwed(dev), 0, "balance cleared");
    }

    /*//////////////////////////////////////////////////////////////
                              L-01
    //////////////////////////////////////////////////////////////*/

    function test_retest_L01_small_transfers_are_taxed_correctly() public {
        _fund(alice, 10_000e18);

        // 5% of 99 is 4.95, which truncates to 4 - not to zero.
        _sell(alice, 99);
        assertEq(token.balanceOf(address(token)), 4, "99 wei now pays a fee");
        assertEq(token.balanceOf(pair), 95, "95 wei reached the pair");
    }

    function test_retest_L01_ordinary_amounts_are_no_longer_undercharged() public {
        _fund(alice, 10_000e18);

        // 5% of 199 is 9.95 -> 9. The vulnerable contract charged 5.
        _sell(alice, 199);
        assertEq(token.balanceOf(address(token)), 9, "correct fee");
    }

    /*//////////////////////////////////////////////////////////////
                              L-02
    //////////////////////////////////////////////////////////////*/

    function test_retest_L02_max_wallet_has_a_floor() public {
        uint256 minimum = token.totalSupply() * token.MIN_MAX_WALLET_BPS() / 10_000;

        vm.prank(token.owner());
        vm.expectRevert(abi.encodeWithSelector(MemeTaxFixed.MaxWalletTooLow.selector, 0, minimum));
        token.setMaxWallet(0);

        vm.prank(token.owner());
        token.setMaxWallet(minimum);
        assertEq(token.maxWallet(), minimum, "the floor itself is accepted");
    }
}
