// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTaxFixed} from "../../src/fixed/MemeTaxFixed.sol";
import {MockDexRouter} from "../mocks/MockDexRouter.sol";
import {Handler} from "./Handler.sol";

/// @notice Invariant campaign against the patched contract.
///
/// @dev Each unit test in `test/` checks one attack I thought of. These four
///      properties have to hold for call sequences I didn't think of. INV-02
///      matters most: `feesOwed` and `pendingDividend` are paid from the same
///      ETH balance, so if the two together can ever go above that balance,
///      one person's claim gets paid with someone else's money.
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

        // Some liquidity in the pair so buys have tokens to take.
        vm.prank(deployer);
        token.transfer(pair, 300_000e18);

        handler = new Handler(token, router, deployer, pair, marketing, dev, actors);
        targetContract(address(handler));
    }

    /// @notice INV-01 - there is no mint or burn after the constructor, so the
    ///         balances of all addresses that can hold the token must add up
    ///         to `totalSupply`.
    function invariant_supplyIsConserved() public view {
        assertEq(handler.sumBalances(), token.totalSupply(), "INV-01 supply not conserved");
    }

    /// @notice INV-02 - owed fees and owed dividends are both paid from
    ///         `address(token).balance`, so together they can never be more
    ///         than that balance.
    function invariant_ethObligationsAreBacked() public view {
        assertLe(handler.sumEthObligations(), address(token).balance, "INV-02 ETH obligations exceed balance");
    }

    /// @notice INV-03 - the H-03 tax cap has to hold even when the fuzzer keeps
    ///         calling `setTaxes` with values above it.
    function invariant_taxNeverExceedsCap() public view {
        assertLe(token.buyTax(), token.MAX_TAX(), "INV-03 buy tax above cap");
        assertLe(token.sellTax(), token.MAX_TAX(), "INV-03 sell tax above cap");
    }

    /// @notice INV-04 - the max wallet floor from the L-02 fix.
    function invariant_maxWalletHasFloor() public view {
        uint256 floor = token.totalSupply() * token.MIN_MAX_WALLET_BPS() / 10_000;
        assertGe(token.maxWallet(), floor, "INV-04 max wallet below floor");
    }

    /// @notice Not a real invariant. It prints how many times each action ran,
    ///         so you can check that the campaign hit every path and didn't
    ///         just pass because most calls reverted.
    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
