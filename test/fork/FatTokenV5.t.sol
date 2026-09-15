// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FatTokenV5} from "../../reviews/2026-09_FatTokenV5/FatTokenV5.sol";

interface IRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256, uint256, uint256);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/// @notice Proofs of concept for the FatTokenV5 template review.
///
/// @dev The template is the audit subject, not one deployment of it. Findings
///      that need an owner are proved on a fresh instance configured the way
///      the launchpad lets a deployer configure it; findings that live in the
///      code regardless of configuration are proved against the real
///      BabyGOAT bytecode on a mainnet fork.
///
///      Run with:
///        ETH_RPC_URL=https://ethereum-rpc.publicnode.com forge test --match-path "test/fork/*" -vv
abstract contract FatTokenBase is Test {
    IRouter internal constant ROUTER = IRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant BABYGOAT = 0x26d86F942D514B470Ba5dF311027a870110F6699;

    address internal deployer = makeAddr("deployer");
    address internal fundWallet = makeAddr("fundWallet");
    address internal victim = makeAddr("victim");
    address internal holder = makeAddr("holder");

    function _fork() internal {
        string memory url = vm.envOr("ETH_RPC_URL", string("https://ethereum-rpc.publicnode.com"));
        vm.createSelectFork(url);
    }

    /// @param kb blocks after launch during which every buyer is blacklisted
    function _deploy(uint256 kb, bool killBlock, bool rewardList, bool changeTax, bool offTrade)
        internal
        returns (FatTokenV5 token)
    {
        string[] memory s = new string[](2);
        s[0] = "Template Demo";
        s[1] = "DEMO";

        address[] memory a = new address[](4);
        a[0] = WETH; // currency, overwritten when currencyIsEth
        a[1] = address(ROUTER);
        a[2] = deployer; // receives total supply
        a[3] = fundWallet; // fee wallet, must be an EOA

        uint256[] memory n = new uint256[](13);
        n[0] = 18; // decimals
        n[1] = 1_000_000_000 ether; // totalSupply
        n[2] = 0; // buy fund fee
        n[3] = 0; // buy burn fee
        n[4] = 0; // buy LP fee
        n[5] = 500; // sell fund fee, 5%
        n[6] = 0; // sell burn fee
        n[7] = 0; // sell LP fee
        n[8] = kb; // kill-block window
        n[9] = type(uint256).max; // maxBuyAmount
        n[10] = 0; // unused
        n[11] = type(uint256).max; // maxWalletAmount
        n[12] = 0; // airdropNumbs

        bool[] memory b = new bool[](9);
        b[0] = true; // currencyIsEth
        b[1] = offTrade; // enableOffTrade
        b[2] = killBlock; // enableKillBlock
        b[3] = rewardList; // enableRewardList
        b[4] = false; // enableSwapLimit
        b[5] = false; // enableWalletLimit
        b[6] = changeTax; // enableChangeTax
        b[7] = false; // enableTransferFee
        b[8] = false; // antiSYNC

        vm.prank(deployer, deployer);
        token = new FatTokenV5(s, a, n, b);
    }

    function _addLiquidity(FatTokenV5 token, uint256 tokens, uint256 eth) internal {
        vm.deal(deployer, eth);
        vm.startPrank(deployer, deployer);
        token.approve(address(ROUTER), type(uint256).max);
        ROUTER.addLiquidityETH{value: eth}(address(token), tokens, 0, 0, deployer, block.timestamp);
        vm.stopPrank();
    }

    function _buy(FatTokenV5 token, address who, uint256 ethIn) internal {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = address(token);
        vm.deal(who, ethIn);
        vm.prank(who, who);
        ROUTER.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethIn}(0, path, who, block.timestamp);
    }

    function _sell(FatTokenV5 token, address who, uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = WETH;
        vm.startPrank(who, who);
        token.approve(address(ROUTER), type(uint256).max);
        ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, who, block.timestamp);
        vm.stopPrank();
    }

    /// @dev Approval is done first and on its own, so `vm.expectRevert` lands on
    ///      the swap rather than on the approve.
    function _sellReverts(FatTokenV5 token, address who, uint256 amount) internal {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = WETH;
        vm.prank(who, who);
        token.approve(address(ROUTER), type(uint256).max);

        vm.startPrank(who, who);
        vm.expectRevert();
        ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, who, block.timestamp);
        vm.stopPrank();
    }
}

/// @notice T-01 (High) - the kill block turns every early buyer into a
///         permanent non-seller, and `setkb()` has no ceiling, so the owner can
///         extend the window indefinitely after launch.
contract T01_KillBlockHoneypot is FatTokenBase {
    FatTokenV5 internal token;

    function setUp() public {
        _fork();
        token = _deploy({kb: 3, killBlock: true, rewardList: true, changeTax: false, offTrade: true});
        _addLiquidity(token, 500_000_000 ether, 50 ether);
        vm.prank(deployer);
        token.launch();
    }

    function test_T01_buyer_inside_the_window_can_never_sell() public {
        _buy(token, victim, 1 ether);

        uint256 bought = token.balanceOf(victim);
        assertGt(bought, 0, "the buy itself succeeds");
        assertEq(token.isReward(victim), 1, "and silently blacklists the buyer");

        // The blacklist is checked on `from`, so the position is frozen.
        _sellReverts(token, victim, bought);

        // Still frozen long after the window has closed. `_rewardList` has no
        // expiry and only the owner can clear it.
        vm.roll(block.number + 100_000);
        _sellReverts(token, victim, bought);
    }

    function test_T01_owner_can_reopen_the_trap_at_any_time() public {
        // Window closes normally.
        vm.roll(block.number + 10);
        _buy(token, holder, 1 ether);
        assertEq(token.isReward(holder), 0, "buyer after the window is clean");

        // `setkb` has no upper bound and no restriction on being called after
        // launch, so the owner reopens the window for the next ~30 years.
        vm.prank(deployer);
        token.setkb(100_000_000);

        _buy(token, victim, 1 ether);
        assertEq(token.isReward(victim), 1, "the trap is open again");

        _sellReverts(token, victim, token.balanceOf(victim));
    }
}

/// @notice T-02 (High) - `multi_bclist()` freezes any holder on demand.
contract T02_ArbitraryFreeze is FatTokenBase {
    FatTokenV5 internal token;

    function setUp() public {
        _fork();
        token = _deploy({kb: 0, killBlock: false, rewardList: true, changeTax: false, offTrade: false});
        _addLiquidity(token, 500_000_000 ether, 50 ether);
    }

    function test_T02_owner_freezes_an_arbitrary_holder() public {
        _buy(token, holder, 1 ether);
        uint256 bought = token.balanceOf(holder);
        assertGt(bought, 0, "holder owns tokens");

        address[] memory targets = new address[](1);
        targets[0] = holder;
        vm.prank(deployer);
        token.multi_bclist(targets, true);

        _sellReverts(token, holder, bought);

        // Not even a plain wallet-to-wallet transfer works any more.
        vm.startPrank(holder);
        vm.expectRevert();
        token.transfer(victim, 1 ether);
        vm.stopPrank();
    }
}

/// @notice T-03 (Medium) - `completeCustoms()` lets the owner move the sell tax
///         to just under 25% at any moment while `enableChangeTax` is set.
contract T03_TaxRaise is FatTokenBase {
    FatTokenV5 internal token;

    function setUp() public {
        _fork();
        token = _deploy({kb: 0, killBlock: false, rewardList: false, changeTax: true, offTrade: false});
        _addLiquidity(token, 500_000_000 ether, 50 ether);
    }

    function test_T03_sell_tax_can_jump_to_24_99_percent_after_launch() public {
        assertEq(token._sellFundFee(), 500, "launched at 5%");

        _buy(token, holder, 1 ether);

        uint256[] memory customs = new uint256[](6);
        customs[0] = 0; // buy LP
        customs[1] = 0; // buy burn
        customs[2] = 0; // buy fund
        customs[3] = 0; // sell LP
        customs[4] = 0; // sell burn
        customs[5] = 2499; // sell fund, 24.99%
        vm.prank(deployer);
        token.completeCustoms(customs);

        assertEq(token._sellFundFee(), 2499, "raised to 24.99% in one transaction");

        uint256 before = holder.balance;
        _sell(token, holder, token.balanceOf(holder));
        assertGt(holder.balance, before, "the sell goes through, just at a quarter off");
    }
}

/// @notice T-05 (Low) - `setEnableTransferFee()` never writes the public flag,
///         so `enableTransferFee()` reports the wrong thing after any call.
contract T05_FlagDesync is FatTokenBase {
    FatTokenV5 internal token;

    function setUp() public {
        _fork();
        token = _deploy({kb: 0, killBlock: false, rewardList: false, changeTax: false, offTrade: false});
    }

    function test_T05_public_flag_contradicts_the_fee_it_controls() public {
        assertEq(token.enableTransferFee(), false, "starts false");
        assertEq(token.transferFee(), 0, "and no fee");

        vm.prank(deployer);
        token.setEnableTransferFee(true);

        // The fee is live.
        assertEq(token.transferFee(), 500, "wallet-to-wallet transfers now taxed 5%");
        // The flag anyone would read to find that out is not.
        assertEq(token.enableTransferFee(), false, "but the public flag still says false");
    }
}

/// @notice T-06 (Low) - the airdrop loop subtracts `airdropNumbs` from `amount`
///         after the fact, so any trade smaller than that underflows and
///         reverts. Proved against the live BabyGOAT bytecode, where the loop
///         is active and can never be switched off: `setAirDropEnable` is
///         `onlyOwner` and ownership is renounced.
contract T06_AirdropUnderflow is FatTokenBase {
    FatTokenV5 internal token;
    address internal pair;

    function setUp() public {
        _fork();
        token = FatTokenV5(payable(BABYGOAT));
        pair = token._mainPair();
    }

    function test_T06_configuration_is_frozen() public view {
        assertEq(token.owner(), 0x000000000000000000000000000000000000dEaD, "ownership renounced");
        assertTrue(token.airdropEnable(), "airdrop still on");
        assertEq(token.airdropNumbs(), 3, "and still sends 3 dust transfers per trade");
    }

    function test_T06_trades_below_airdropNumbs_revert_forever() public {
        deal(address(token), holder, 1_000 ether);

        // 2 wei is less than the 3 wei the airdrop loop skims first.
        vm.startPrank(holder, holder);
        vm.expectRevert();
        token.transfer(pair, 2);
        vm.stopPrank();

        // 3 wei is exactly enough: amount - 3 == 0 and the transfer goes through.
        vm.prank(holder, holder);
        token.transfer(pair, 3);
    }
}
