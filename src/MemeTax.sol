// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MinimalERC20} from "./base/MinimalERC20.sol";
import {IDexRouter} from "./interfaces/IDexRouter.sol";

/// @title MemeTax
/// @notice Audit target. I wrote it to look like the tax tokens that
///         meme-coin launches use: buy/sell tax swapped on a DEX, a max
///         wallet, a blacklist, an ETH dividend pool, and a fee swap that
///         runs inside `_transfer`.
///
/// @dev This contract has bugs on purpose. Do not deploy it.
///      The findings are in `reports/2026-09_MemeTax_audit-report.md`, and
///      every one except I-01 has a PoC in `test/`.
///      The patched version is `src/fixed/MemeTaxFixed.sol`.
contract MemeTax is MinimalERC20 {
    address public owner;
    address public marketingWallet;
    address public devWallet;

    IDexRouter public router;
    address public pair;

    uint256 public buyTax = 5;
    uint256 public sellTax = 5;

    uint256 public maxWallet;
    uint256 public swapThreshold;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => uint256) public pendingDividend;

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    constructor(address _router, address _marketingWallet, address _devWallet)
        MinimalERC20("MemeTax", "MEME")
    {
        owner = msg.sender;
        router = IDexRouter(_router);
        marketingWallet = _marketingWallet;
        devWallet = _devWallet;

        isExcludedFromFee[msg.sender] = true;
        isExcludedFromFee[address(this)] = true;

        _mint(msg.sender, 1_000_000e18);
        maxWallet = 20_000e18;
        swapThreshold = 1_000e18;
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            ADMIN
    //////////////////////////////////////////////////////////////*/

    function setPair(address _pair) external onlyOwner {
        pair = _pair;
    }

    /// @dev [H-03] No upper bound, so the owner can set the sell tax to 100%
    ///      any time after launch and turn the token into a honeypot.
    function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    /// @dev [H-02] No `onlyOwner` here, so anyone can freeze any holder.
    function setBlacklist(address account, bool blacklisted) external {
        isBlacklisted[account] = blacklisted;
    }

    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    /// @dev [L-02] Zero is accepted, and zero freezes every non-excluded transfer.
    function setMaxWallet(uint256 _maxWallet) external onlyOwner {
        maxWallet = _maxWallet;
    }

    function setSwapThreshold(uint256 _swapThreshold) external onlyOwner {
        swapThreshold = _swapThreshold;
    }

    /*//////////////////////////////////////////////////////////////
                            DIVIDENDS
    //////////////////////////////////////////////////////////////*/

    function depositDividend(address account) external payable onlyOwner {
        pendingDividend[account] += msg.value;
    }

    /// @dev [H-01] Breaks Checks-Effects-Interactions: ETH is sent before the
    ///      balance is set to 0, so a contract can re-enter and claim again
    ///      and again until the pool is empty.
    function claimDividend() external {
        uint256 amount = pendingDividend[msg.sender];
        require(amount > 0, "NOTHING_TO_CLAIM");

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "ETH_TRANSFER_FAILED");

        pendingDividend[msg.sender] = 0;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, uint256 amount) internal override {
        require(!isBlacklisted[from] && !isBlacklisted[to], "BLACKLISTED");

        // [M-01] No `inSwap` lock. The only thing stopping a second swap is that
        // `isExcludedFromFee[address(this)]` is true, because the router pulls
        // the tokens from this contract on the way to the pair. Nothing in the
        // code enforces that.
        if (to == pair && !isExcludedFromFee[from] && balanceOf[address(this)] >= swapThreshold) {
            _swapBack();
        }

        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            _rawTransfer(from, to, amount);
            return;
        }

        uint256 taxRate;
        if (from == pair) {
            taxRate = buyTax;
        } else if (to == pair) {
            taxRate = sellTax;
        }

        // [L-01] Divides before multiplying, so any amount under 100 wei pays
        // no tax.
        uint256 fee = amount / 100 * taxRate;

        if (fee > 0) {
            _rawTransfer(from, address(this), fee);
        }

        uint256 net = amount - fee;

        if (to != pair) {
            require(balanceOf[to] + net <= maxWallet, "MAX_WALLET");
        }

        _rawTransfer(from, to, net);
    }

    function _swapBack() internal {
        uint256 tokens = balanceOf[address(this)];
        if (tokens == 0) return;

        _approve(address(this), address(router), tokens);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens, 0, path, address(this), block.timestamp
        );

        uint256 half = address(this).balance / 2;

        // [M-02] Both return values are ignored. If a wallet can't accept ETH,
        // the payout fails quietly and the transfer still goes through.
        marketingWallet.call{value: half}("");
        devWallet.call{value: address(this).balance}("");
    }
}
