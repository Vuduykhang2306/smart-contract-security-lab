// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";

/// @notice Handler for the invariant campaign against `MemeTaxFixed`.
/// @dev This doesn't inherit `Test` on purpose. The fuzzer calls every public
///      function on this contract, and with `Test` it would spend most of its
///      calls on cheatcode helpers instead of the token.
///
///      Each action bounds its inputs so most calls succeed. If almost every
///      call reverts, a passing run doesn't mean much, so `callSummary()`
///      prints the counts and every action should be above zero.
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

    /// @dev The bounds go past MAX_TAX on purpose, so the fuzzer keeps trying
    ///      values above the cap.
    function setTaxes(uint256 buyTax, uint256 sellTax) external countCall("setTaxes") {
        buyTax = bound(buyTax, 0, 2 * token.MAX_TAX());
        sellTax = bound(sellTax, 0, 2 * token.MAX_TAX());

        vm.prank(owner);
        try token.setTaxes(buyTax, sellTax) {} catch {}
    }

    /// @dev Kept above 1% of supply so transfers don't keep failing. The floor
    ///      itself is tested in `Retest_Fixed.test_retest_L02_max_wallet_has_a_floor`.
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

    /// @notice Sum over every address that can hold the token. There is no mint
    ///         or burn after the constructor, so this should equal `totalSupply`.
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

    /// @notice All the ETH the contract currently owes.
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
