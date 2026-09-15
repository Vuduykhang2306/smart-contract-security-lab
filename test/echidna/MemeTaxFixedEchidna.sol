// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";
import {Puppet} from "./Puppet.sol";

/// @notice The Foundry invariants of `test/invariant/` re-stated for Echidna.
///
/// @dev Same four properties, same action set, different engine. Foundry's
///      fuzzer builds a call sequence from a handler; Echidna builds one from
///      this contract's own external functions and keeps a corpus of the
///      sequences that reached new code, so the two explore the state space in
///      different orders. Running both is the point of the exercise: agreement
///      raises confidence, disagreement is itself a result worth writing down.
///
///      Two things differ from the Foundry harness out of necessity, not choice:
///
///      1. No cheatcodes. This contract deploys the token, so it *is* the owner
///         and it holds the supply. Every other participant is a `Puppet`.
///      2. No `vm.deal`. ETH comes from this contract's starting balance, set
///         by `balanceContract` in `echidna.yaml`, and `fundRouter()` is an
///         ordinary fuzzed action rather than setup.
///
///      Run: echidna . --contract MemeTaxFixedEchidna --config echidna.yaml
contract MemeTaxFixedEchidna {
    uint256 internal constant ACTOR_COUNT = 5;
    uint256 internal constant SEED_PER_ACTOR = 15_000e18;
    uint256 internal constant SEED_LIQUIDITY = 300_000e18;

    MemeTaxFixed public immutable token;
    MockDexRouter public immutable router;

    Puppet public immutable pair;
    Puppet public immutable marketingWallet;
    Puppet public immutable devWallet;
    Puppet[ACTOR_COUNT] public actors;

    // Action counters. Echidna prints nothing at the end of a run, so coverage
    // is read off `corpusDir/covered.*.txt` instead; these are here so a reader
    // can also check the mix from a debugger or a follow-up call.
    mapping(bytes32 => uint256) public calls;

    address internal immutable weth;

    /// @dev Payable because Echidna funds the harness by sending `balanceContract`
    ///      with the deployment transaction; a non-payable constructor rejects it.
    constructor() payable {
        weth = address(new Puppet());

        router = new MockDexRouter(weth);
        marketingWallet = new Puppet();
        devWallet = new Puppet();
        pair = new Puppet();

        token = new MemeTaxFixed(address(router), address(marketingWallet), address(devWallet));
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

    /// @dev Stand-in for `StdUtils.bound`, which lives in forge-std and is not
    ///      available here. Modulo skews the distribution towards the low end
    ///      of a wide range; every call site below uses a range narrow enough
    ///      that it does not matter.
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

        // A sell that trips the fee swap needs the router to be able to pay for
        // it, or the whole transfer reverts inside the mock and the sequence
        // teaches the fuzzer nothing. Router solvency is not what is under test.
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

    /// @dev Setup in the Foundry harness, an action here. The router pays for
    ///      fee swaps out of its own balance, so somebody has to fill it.
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

    function withdrawFees(bool marketingSide) external {
        _count("withdrawFees");
        Puppet who = marketingSide ? marketingWallet : devWallet;
        if (token.feesOwed(address(who)) == 0) return;

        who.exec(address(token), abi.encodeCall(token.withdrawFees, ()));
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVILEGED SETTERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Range runs past MAX_TAX on purpose. The cap has to hold against a
    ///      fuzzer that keeps trying to breach it, not just against one unit test.
    function setTaxes(uint256 buyTax, uint256 sellTax) external {
        _count("setTaxes");
        uint256 cap = token.MAX_TAX();
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

    /// @notice INV-01 - no mint or burn path exists after construction, so the
    ///         balances of every address that can hold the token must add up to
    ///         `totalSupply` no matter what sequence ran.
    function echidna_supplyIsConserved() public view returns (bool) {
        return _sumBalances() == token.totalSupply();
    }

    /// @notice INV-02 - fee credits and dividend credits are both paid from
    ///         `address(token).balance`. Their sum must never exceed it, or the
    ///         contract has promised ETH it does not hold.
    function echidna_ethObligationsAreBacked() public view returns (bool) {
        return _sumEthObligations() <= address(token).balance;
    }

    /// @notice INV-03 - the cap that closes H-03.
    function echidna_taxNeverExceedsCap() public view returns (bool) {
        uint256 cap = token.MAX_TAX();
        return token.buyTax() <= cap && token.sellTax() <= cap;
    }

    /// @notice INV-04 - the floor that closes L-02.
    function echidna_maxWalletHasFloor() public view returns (bool) {
        uint256 floor = token.totalSupply() * token.MIN_MAX_WALLET_BPS() / 10_000;
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

    function _sumEthObligations() internal view returns (uint256 total) {
        total += token.feesOwed(address(marketingWallet));
        total += token.feesOwed(address(devWallet));
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            total += token.pendingDividend(address(actors[i]));
        }
    }
}
