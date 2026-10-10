// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MemeTax} from "../../src/MemeTax.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";
import {Puppet} from "./Puppet.sol";

/// @notice Negative control: the same four properties, run against the
///         unpatched contract.
///
/// @dev A passing fuzz run doesn't show much until you've seen the same
///      properties fail. This harness is `MemeTaxFixedEchidna` with one line
///      changed (the token it deploys), and the same actions, bounds and
///      properties. The unpatched API forces three small differences, and each
///      one is marked below.
///
///      Expected result (this is why the file is in the repo):
///
///        INV-01 supply conserved      passes  - no mint or burn either way
///        INV-02 ETH obligations backed FAILS  - H-04: `_swapBack` pays the fee
///                                               wallets out of the whole
///                                               balance, dividend pool included
///        INV-03 tax cap                FAILS  - H-03: `setTaxes` has no ceiling
///        INV-04 max-wallet floor      passes  - `setMaxWallet` is bounded by
///                                               the harness, not by the token;
///                                               L-02 is covered by the retest
///
///      INV-02 is the important one. The fuzzer isn't told anything about H-04;
///      it gets there with a normal deposit, buy, sell sequence.
///
///      Run: echidna . --contract MemeTaxEchidna --config echidna.control.yaml
contract MemeTaxEchidna {
    // Difference 1: the unpatched contract has neither of these constants.
    // They are the values the fix added, copied here so both harnesses check
    // exactly the same property.
    uint256 internal constant MAX_TAX = 10;
    uint256 internal constant MIN_MAX_WALLET_BPS = 10;

    uint256 internal constant ACTOR_COUNT = 5;
    uint256 internal constant SEED_PER_ACTOR = 15_000e18;
    uint256 internal constant SEED_LIQUIDITY = 300_000e18;

    MemeTax public immutable token;
    MockDexRouter public immutable router;

    Puppet public immutable pair;
    Puppet public immutable marketingWallet;
    Puppet public immutable devWallet;
    Puppet[ACTOR_COUNT] public actors;

    // Action counters. Echidna doesn't print a summary at the end of a run, so
    // coverage is read from `corpusDir/covered.*.txt` instead. The counters are
    // still here so the mix can be checked from a debugger or a later call.
    mapping(bytes32 => uint256) public calls;

    address internal immutable weth;

    /// @dev Payable because Echidna funds the harness by sending `balanceContract`
    ///      with the deploy transaction, and a non-payable constructor rejects it.
    constructor() payable {
        weth = address(new Puppet());

        router = new MockDexRouter(weth);
        marketingWallet = new Puppet();
        devWallet = new Puppet();
        pair = new Puppet();

        token = new MemeTax(address(router), address(marketingWallet), address(devWallet));
        token.setPair(address(pair));
        router.setPair(address(pair));

        for (uint256 i; i < ACTOR_COUNT; ++i) {
            actors[i] = new Puppet();
            token.transfer(address(actors[i]), SEED_PER_ACTOR);
        }
        token.transfer(address(pair), SEED_LIQUIDITY);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Replacement for `StdUtils.bound`, which is in forge-std and not
    ///      available here. Modulo leans toward the low end of a wide range,
    ///      but every call below uses a range narrow enough that it doesn't
    ///      matter.
    function _bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }

    function _actor(uint256 seed) internal view returns (Puppet) {
        return actors[seed % ACTOR_COUNT];
    }

    function _room(address who) internal view returns (uint256) {
        uint256 cap = token.maxWallet();
        uint256 held = token.balanceOf(who);
        return held >= cap ? 0 : cap - held;
    }

    function _count(bytes32 key) internal {
        calls[key]++;
    }

    /*//////////////////////////////////////////////////////////////
                              TRADING
    //////////////////////////////////////////////////////////////*/

    function buy(uint256 actorSeed, uint256 amount) external {
        _count("buy");
        address to = address(_actor(actorSeed));
        uint256 room = _room(to);
        uint256 liquidity = token.balanceOf(address(pair));
        if (room == 0 || liquidity == 0) return;

        amount = _bound(amount, 1, room < liquidity ? room : liquidity);
        pair.exec(address(token), abi.encodeCall(token.transfer, (to, amount)));
    }

    function sell(uint256 actorSeed, uint256 amount) external {
        _count("sell");
        Puppet from = _actor(actorSeed);
        uint256 held = token.balanceOf(address(from));
        if (held == 0) return;

        // A sell that triggers the fee swap needs the router to have enough
        // ETH, otherwise the whole transfer reverts inside the mock and the
        // fuzzer learns nothing. Router solvency isn't what we're testing.
        uint256 sitting = token.balanceOf(address(token));
        if (sitting >= token.swapThreshold()) {
            uint256 need = sitting * router.ethPerToken() / 1e18;
            if (address(router).balance < need) return;
        }

        amount = _bound(amount, 1, held);
        from.exec(address(token), abi.encodeCall(token.transfer, (address(pair), amount)));
    }

    function walletToWallet(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        _count("walletToWallet");
        Puppet from = _actor(fromSeed);
        address to = address(_actor(toSeed));
        if (address(from) == to) return;

        uint256 held = token.balanceOf(address(from));
        uint256 room = _room(to);
        if (held == 0 || room == 0) return;

        amount = _bound(amount, 1, held < room ? held : room);
        from.exec(address(token), abi.encodeCall(token.transfer, (to, amount)));
    }

    /*//////////////////////////////////////////////////////////////
                             ETH PATHS
    //////////////////////////////////////////////////////////////*/

    /// @dev This is part of setup in the Foundry harness but an action here.
    ///      The router pays for fee swaps from its own balance, so something
    ///      has to fund it.
    function fundRouter(uint256 amount) external {
        _count("fundRouter");
        uint256 available = address(this).balance;
        if (available == 0) return;

        amount = _bound(amount, 1, available < 100 ether ? available : 100 ether);
        (bool ok,) = address(router).call{value: amount}("");
        ok;
    }

    function depositDividend(uint256 actorSeed, uint256 amount) external {
        _count("depositDividend");
        uint256 available = address(this).balance;
        if (available == 0) return;

        amount = _bound(amount, 1, available < 10 ether ? available : 10 ether);
        token.depositDividend{value: amount}(address(_actor(actorSeed)));
    }

    function claimDividend(uint256 actorSeed) external {
        _count("claimDividend");
        Puppet who = _actor(actorSeed);
        if (token.pendingDividend(address(who)) == 0) return;

        who.exec(address(token), abi.encodeCall(token.claimDividend, ()));
    }

    /// @dev Difference 2: the unpatched contract has no `withdrawFees`, because
    ///      `_swapBack` pushes the ETH out. Kept as a no-op so both harnesses
    ///      have the same list of actions.
    function withdrawFees(bool) external {
        _count("withdrawFees");
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVILEGED SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev The range goes past MAX_TAX on purpose, so the fuzzer keeps trying
    ///      values above the cap.
    function setTaxes(uint256 buyTax, uint256 sellTax) external {
        _count("setTaxes");
        uint256 cap = MAX_TAX;
        buyTax = _bound(buyTax, 0, 2 * cap);
        sellTax = _bound(sellTax, 0, 2 * cap);

        try token.setTaxes(buyTax, sellTax) {} catch {}
    }

    function setMaxWallet(uint256 value) external {
        _count("setMaxWallet");
        uint256 supply = token.totalSupply();
        value = _bound(value, supply / 100, supply);

        try token.setMaxWallet(value) {} catch {}
    }

    function setSwapThreshold(uint256 value) external {
        _count("setSwapThreshold");
        value = _bound(value, 1, 50_000e18);

        try token.setSwapThreshold(value) {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                             PROPERTIES
    //////////////////////////////////////////////////////////////*/

    /// @notice INV-01 - there is no mint or burn after the constructor, so the
    ///         balances of all addresses that can hold the token must add up
    ///         to `totalSupply`.
    function echidna_supplyIsConserved() public view returns (bool) {
        return _sumBalances() == token.totalSupply();
    }

    /// @notice INV-02 - owed fees and owed dividends are both paid from
    ///         `address(token).balance`, so together they can never be more
    ///         than that balance.
    function echidna_ethObligationsAreBacked() public view returns (bool) {
        return _sumEthObligations() <= address(token).balance;
    }

    /// @notice INV-03 - the tax cap from the H-03 fix.
    function echidna_taxNeverExceedsCap() public view returns (bool) {
        uint256 cap = MAX_TAX;
        return token.buyTax() <= cap && token.sellTax() <= cap;
    }

    /// @notice INV-04 - the max wallet floor from the L-02 fix.
    function echidna_maxWalletHasFloor() public view returns (bool) {
        uint256 floor = token.totalSupply() * MIN_MAX_WALLET_BPS / 10_000;
        return token.maxWallet() >= floor;
    }

    /*//////////////////////////////////////////////////////////////
                                SUMS
    //////////////////////////////////////////////////////////////*/

    function _sumBalances() internal view returns (uint256 total) {
        total += token.balanceOf(address(this));
        total += token.balanceOf(address(token));
        total += token.balanceOf(address(pair));
        total += token.balanceOf(address(router));
        total += token.balanceOf(address(marketingWallet));
        total += token.balanceOf(address(devWallet));
        total += token.balanceOf(weth);
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            total += token.balanceOf(address(actors[i]));
        }
    }

    /// @dev Difference 3: no `feesOwed` term. The unpatched contract sends the
    ///      fee ETH out inside `_swapBack` instead of recording what it owes, so
    ///      the dividend ledger is the only thing left on the books. That's also
    ///      why the payout can end up spending the dividend money.
    function _sumEthObligations() internal view returns (uint256 total) {
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            total += token.pendingDividend(address(actors[i]));
        }
    }
}
