// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MinimalERC20} from "./base/MinimalERC20.sol";
import {IDexRouter} from "./interfaces/IDexRouter.sol";

/// @title MemeTax
/// @notice AUDIT TARGET. A tax token in the shape that meme-coin launches
///         actually ship: buy/sell tax routed through a DEX, a max-wallet cap,
///         a blacklist, an ETH dividend pool, and a fee swap triggered from
///         inside `_transfer`.
///
/// @dev THIS CONTRACT IS DELIBERATELY VULNERABLE. Do not deploy it.
///      Findings are documented in `reports/2026-09_MemeTax_audit-report.md`
///      and each one has a runnable proof of concept in `test/`.
///      The remediated version is `src/fixed/MemeTaxFixed.sol`.
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

    /// @dev [H-03] No upper bound. The owner can raise the sell tax to 100%
    ///      at any point after launch, which turns the token into a honeypot.
    function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    /// @dev [H-02] Missing `onlyOwner`. Any address can freeze any holder.
    function setBlacklist(address account, bool blacklisted) external {
        isBlacklisted[account] = blacklisted;
    }

    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
    }

    /// @dev [L-02] Accepts zero, which freezes every non-excluded transfer.
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

    /// @dev [H-01] Checks-Effects-Interactions violation: the ETH is sent
    ///      before the balance is zeroed, so a contract recipient can re-enter
    ///      and claim its share repeatedly until the pool is empty.
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

        // [M-01] There is no `inSwap` lock here. Re-entry is prevented only as a
        // side effect of `isExcludedFromFee[address(this)]` being true, because
        // the router pulls the tokens out of this contract on the way to the pair.
        // That is an implicit invariant nothing enforces.
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

        // [L-01] Division before multiplication: any amount below 100 wei is
        // taxed at zero.
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

        // [M-02] Both return values are discarded. If either wallet cannot
        // accept ETH the distribution fails silently and the transfer succeeds.
        marketingWallet.call{value: half}("");
        devWallet.call{value: address(this).balance}("");
    }
}
