// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";
import {Handler} from "./Handler.sol";

/// @notice Invariant campaign against the remediated contract.
///
/// @dev The unit tests in `test/` each prove one attack I thought of. These
///      four properties are the ones that have to survive attack sequences I
///      did not think of. INV-02 is the one worth the campaign: `feesOwed` and
///      `pendingDividend` are paid out of the same ETH balance, so if the two
///      ledgers can ever sum past the balance, one claimant drains another's
///      money and the first person to call `withdrawFees` wins.
contract MemeTaxFixedInvariants is Test {
    MemeTaxFixed internal token;
    MockDexRouter internal router;
    Handler internal handler;

    address internal deployer = makeAddr("deployer");
    address internal pair = makeAddr("pair");
    address internal weth = makeAddr("weth");
    address internal marketing = makeAddr("marketing");
    address internal dev = makeAddr("dev");

    address[] internal actors;

    function setUp() public {
        router = new MockDexRouter(weth);
        router.setPair(pair);
        vm.deal(address(router), 100_000 ether);

        vm.startPrank(deployer);
        token = new MemeTaxFixed(address(router), marketing, dev);
        token.setPair(pair);
        vm.stopPrank();

        for (uint256 i; i < 5; ++i) {
            address actor = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(actor);
            vm.prank(deployer);
            token.transfer(actor, 15_000e18);
        }

        // Liquidity sitting in the pair so buys have something to draw on.
        vm.prank(deployer);
        token.transfer(pair, 300_000e18);

        handler = new Handler(token, router, deployer, pair, marketing, dev, actors);
        targetContract(address(handler));
    }

    /// @notice INV-01 - no mint or burn path exists after construction, so the
    ///         balances of every address that can hold the token must add up to
    ///         `totalSupply` no matter what sequence ran.
    function invariant_supplyIsConserved() public view {
        assertEq(handler.sumBalances(), token.totalSupply(), "INV-01 supply not conserved");
    }

    /// @notice INV-02 - fee credits and dividend credits are both paid from
    ///         `address(token).balance`. Their sum must never exceed it, or the
    ///         contract has promised ETH it does not hold.
    function invariant_ethObligationsAreBacked() public view {
        assertLe(handler.sumEthObligations(), address(token).balance, "INV-02 ETH obligations exceed balance");
    }

    /// @notice INV-03 - the cap that closes H-03 has to hold against a fuzzer
    ///         that keeps calling `setTaxes` with values past it.
    function invariant_taxNeverExceedsCap() public view {
        assertLe(token.buyTax(), token.MAX_TAX(), "INV-03 buy tax above cap");
        assertLe(token.sellTax(), token.MAX_TAX(), "INV-03 sell tax above cap");
    }

    /// @notice INV-04 - the floor that closes L-02.
    function invariant_maxWalletHasFloor() public view {
        uint256 floor = token.totalSupply() * token.MIN_MAX_WALLET_BPS() / 10_000;
        assertGe(token.maxWallet(), floor, "INV-04 max wallet below floor");
    }

    /// @notice Not an invariant. Prints the action mix so a reader can confirm
    ///         the campaign actually exercised every path instead of reverting
    ///         its way to a green tick.
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
