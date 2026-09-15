// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";

/// @notice Handler for the invariant campaign against `MemeTaxFixed`.
/// @dev Deliberately does NOT inherit `Test`: the fuzzer targets every public
///      function on this contract, and inheriting the full test harness would
///      hand it hundreds of cheatcode wrappers to call instead of the token.
///
///      Every action bounds its inputs so calls mostly land instead of
///      reverting. A campaign where 95% of calls revert proves nothing, so
///      `callSummary()` prints the counts and the run is only meaningful if
///      every bucket is non-zero.
contract Handler is CommonBase, StdCheats, StdUtils {
    MemeTaxFixed public immutable token;
    MockDexRouter public immutable router;
    address public immutable owner;
    address public immutable pair;
    address public immutable marketingWallet;
    address public immutable devWallet;

    address[] public actors;

    mapping(bytes32 => uint256) public calls;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    constructor(
        MemeTaxFixed _token,
        MockDexRouter _router,
        address _owner,
        address _pair,
        address _marketingWallet,
        address _devWallet,
        address[] memory _actors
    ) {
        token = _token;
        router = _router;
        owner = _owner;
        pair = _pair;
        marketingWallet = _marketingWallet;
        devWallet = _devWallet;
        for (uint256 i; i < _actors.length; ++i) {
            actors.push(_actors[i]);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _room(address who) internal view returns (uint256) {
        uint256 cap = token.maxWallet();
        uint256 held = token.balanceOf(who);
        return held >= cap ? 0 : cap - held;
    }

    /*//////////////////////////////////////////////////////////////
                              TRADING
    //////////////////////////////////////////////////////////////*/

    function buy(uint256 actorSeed, uint256 amount) external countCall("buy") {
        address to = _actor(actorSeed);
        uint256 room = _room(to);
        uint256 liquidity = token.balanceOf(pair);
        if (room == 0 || liquidity == 0) return;

        amount = bound(amount, 1, room < liquidity ? room : liquidity);
        vm.prank(pair);
        token.transfer(to, amount);
    }

    function sell(uint256 actorSeed, uint256 amount) external countCall("sell") {
        address from = _actor(actorSeed);
        uint256 held = token.balanceOf(from);
        if (held == 0) return;

        amount = bound(amount, 1, held);
        vm.prank(from);
        token.transfer(pair, amount);
    }

    function walletToWallet(uint256 fromSeed, uint256 toSeed, uint256 amount)
        external
        countCall("walletToWallet")
    {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        if (from == to) return;

        uint256 held = token.balanceOf(from);
        uint256 room = _room(to);
        if (held == 0 || room == 0) return;

        amount = bound(amount, 1, held < room ? held : room);
        vm.prank(from);
        token.transfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           ETH PATHS
    //////////////////////////////////////////////////////////////*/

    function depositDividend(uint256 actorSeed, uint256 amount) external countCall("depositDividend") {
        address to = _actor(actorSeed);
        amount = bound(amount, 1, 10 ether);

        vm.deal(owner, amount);
        vm.prank(owner);
        token.depositDividend{value: amount}(to);
    }

    function claimDividend(uint256 actorSeed) external countCall("claimDividend") {
        address who = _actor(actorSeed);
        if (token.pendingDividend(who) == 0) return;

        vm.prank(who);
        token.claimDividend();
    }

    function withdrawFees(bool marketingSide) external countCall("withdrawFees") {
        address who = marketingSide ? marketingWallet : devWallet;
        if (token.feesOwed(who) == 0) return;

        vm.prank(who);
        token.withdrawFees();
    }

    /*//////////////////////////////////////////////////////////////
                          PRIVILEGED SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Bounds run past MAX_TAX on purpose: the cap has to hold against a
    ///      fuzzer that keeps trying to breach it, not just against one unit test.
    function setTaxes(uint256 buyTax, uint256 sellTax) external countCall("setTaxes") {
        buyTax = bound(buyTax, 0, 2 * token.MAX_TAX());
        sellTax = bound(sellTax, 0, 2 * token.MAX_TAX());

        vm.prank(owner);
        try token.setTaxes(buyTax, sellTax) {} catch {}
    }

    /// @dev Kept above 1% of supply so the campaign stays productive; the floor
    ///      itself is covered by `Retest_Fixed.test_retest_L02_max_wallet_has_a_floor`.
    function setMaxWallet(uint256 value) external countCall("setMaxWallet") {
        uint256 supply = token.totalSupply();
        value = bound(value, supply / 100, supply);

        vm.prank(owner);
        try token.setMaxWallet(value) {} catch {}
    }

    function setSwapThreshold(uint256 value) external countCall("setSwapThreshold") {
        value = bound(value, 1, 50_000e18);

        vm.prank(owner);
        try token.setSwapThreshold(value) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                              SUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Every address that can hold the token. No mint or burn exists
    ///         after construction, so this must always equal `totalSupply`.
    function sumBalances() external view returns (uint256 total) {
        total += token.balanceOf(owner);
        total += token.balanceOf(address(token));
        total += token.balanceOf(pair);
        total += token.balanceOf(address(router));
        total += token.balanceOf(marketingWallet);
        total += token.balanceOf(devWallet);
        total += token.balanceOf(address(this));
        for (uint256 i; i < actors.length; ++i) {
            total += token.balanceOf(actors[i]);
        }
    }

    /// @notice Every ETH the contract has promised to somebody.
    function sumEthObligations() external view returns (uint256 total) {
        total += token.feesOwed(marketingWallet);
        total += token.feesOwed(devWallet);
        for (uint256 i; i < actors.length; ++i) {
            total += token.pendingDividend(actors[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function callSummary() external view {
        console.log("buy               ", calls["buy"]);
        console.log("sell              ", calls["sell"]);
        console.log("walletToWallet    ", calls["walletToWallet"]);
        console.log("depositDividend   ", calls["depositDividend"]);
        console.log("claimDividend     ", calls["claimDividend"]);
        console.log("withdrawFees      ", calls["withdrawFees"]);
        console.log("setTaxes          ", calls["setTaxes"]);
        console.log("setMaxWallet      ", calls["setMaxWallet"]);
        console.log("setSwapThreshold  ", calls["setSwapThreshold"]);
    }
}
