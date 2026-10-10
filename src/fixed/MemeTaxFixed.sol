// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MinimalERC20} from "../base/MinimalERC20.sol";
import {IDexRouter} from "../interfaces/IDexRouter.sol";

/// @title MemeTaxFixed
/// @notice Patched version of `src/MemeTax.sol`. Each change is tagged with
///         the finding ID from `reports/2026-09_MemeTax_audit-report.md`.
///         `test/Retest_Fixed.t.sol` runs every original PoC against this
///         contract and checks that it no longer works.
contract MemeTaxFixed is MinimalERC20 {
    /// @notice [H-03] Max value for either tax, checked in the setter.
    uint256 public constant MAX_TAX = 10;
    /// @notice [L-02] Lowest allowed `maxWallet`, in basis points of supply.
    uint256 public constant MIN_MAX_WALLET_BPS = 10; // 0.10%

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
    /// @notice [M-02] Fees are recorded here and each wallet withdraws its own.
    mapping(address => uint256) public feesOwed;

    /// @notice [M-01] Lock so the fee swap can't run twice in one transfer.
    bool private _inSwap;
    /// @notice [H-01] Reentrancy lock for the two ETH withdrawals.
    uint256 private _locked = 1;

    // [I-01] Every admin change emits an event so it can be seen off-chain.
    event TaxesUpdated(uint256 buyTax, uint256 sellTax);
    event BlacklistUpdated(address indexed account, bool blacklisted);
    event FeeExclusionUpdated(address indexed account, bool excluded);
    event MaxWalletUpdated(uint256 maxWallet);
    event SwapThresholdUpdated(uint256 swapThreshold);
    event PairUpdated(address indexed pair);
    event FeesAccrued(address indexed wallet, uint256 amount);
    event FeesWithdrawn(address indexed wallet, uint256 amount);
    event DividendClaimed(address indexed account, uint256 amount);

    error NotOwner();
    error Blacklisted();
    error TaxTooHigh(uint256 requested, uint256 maximum);
    error MaxWalletTooLow(uint256 requested, uint256 minimum);
    error MaxWalletExceeded();
    error NothingToClaim();
    error EthTransferFailed();
    error Reentrancy();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    constructor(address _router, address _marketingWallet, address _devWallet)
        MinimalERC20("MemeTax", "MEME")
    {
        if (_router == address(0) || _marketingWallet == address(0) || _devWallet == address(0)) {
            revert ZeroAddress();
        }

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
        if (_pair == address(0)) revert ZeroAddress();
        pair = _pair;
        emit PairUpdated(_pair);
    }

    /// @dev [H-03] Both taxes are capped at `MAX_TAX`, so the owner can't turn
    ///      the token into a honeypot after launch.
    function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyOwner {
        if (_buyTax > MAX_TAX) revert TaxTooHigh(_buyTax, MAX_TAX);
        if (_sellTax > MAX_TAX) revert TaxTooHigh(_sellTax, MAX_TAX);
        buyTax = _buyTax;
        sellTax = _sellTax;
        emit TaxesUpdated(_buyTax, _sellTax);
    }

    /// @dev [H-02] Owner only now.
    function setBlacklist(address account, bool blacklisted) external onlyOwner {
        isBlacklisted[account] = blacklisted;
        emit BlacklistUpdated(account, blacklisted);
    }

    function setExcludedFromFee(address account, bool excluded) external onlyOwner {
        isExcludedFromFee[account] = excluded;
        emit FeeExclusionUpdated(account, excluded);
    }

    /// @dev [L-02] Can't be set low enough to freeze normal transfers.
    function setMaxWallet(uint256 _maxWallet) external onlyOwner {
        uint256 minimum = totalSupply * MIN_MAX_WALLET_BPS / 10_000;
        if (_maxWallet < minimum) revert MaxWalletTooLow(_maxWallet, minimum);
        maxWallet = _maxWallet;
        emit MaxWalletUpdated(_maxWallet);
    }

    function setSwapThreshold(uint256 _swapThreshold) external onlyOwner {
        swapThreshold = _swapThreshold;
        emit SwapThresholdUpdated(_swapThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                        DIVIDENDS AND FEES
    //////////////////////////////////////////////////////////////*/

    function depositDividend(address account) external payable onlyOwner {
        pendingDividend[account] += msg.value;
    }

    /// @dev [H-01] The balance is cleared before the call, and there is a guard.
    function claimDividend() external nonReentrant {
        uint256 amount = pendingDividend[msg.sender];
        if (amount == 0) revert NothingToClaim();

        pendingDividend[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert EthTransferFailed();

        emit DividendClaimed(msg.sender, amount);
    }

    /// @dev [M-02] Each fee wallet withdraws its own ETH. If a wallet can't
    ///      receive ETH, only its own withdrawal fails.
    function withdrawFees() external nonReentrant {
        uint256 amount = feesOwed[msg.sender];
        if (amount == 0) revert NothingToClaim();

        feesOwed[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert EthTransferFailed();

        emit FeesWithdrawn(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER
    //////////////////////////////////////////////////////////////*/

    function _transfer(address from, address to, uint256 amount) internal override {
        if (isBlacklisted[from] || isBlacklisted[to]) revert Blacklisted();

        // [M-01] Uses the explicit lock instead of relying on this contract
        // being in the fee-exclusion mapping.
        if (!_inSwap && to == pair && !isExcludedFromFee[from] && balanceOf[address(this)] >= swapThreshold) {
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

        // [L-01] Multiply before dividing.
        uint256 fee = amount * taxRate / 100;

        if (fee > 0) {
            _rawTransfer(from, address(this), fee);
        }

        uint256 net = amount - fee;

        if (to != pair && balanceOf[to] + net > maxWallet) revert MaxWalletExceeded();

        _rawTransfer(from, to, net);
    }

    function _swapBack() internal lockTheSwap {
        uint256 tokens = balanceOf[address(this)];
        if (tokens == 0) return;

        _approve(address(this), address(router), tokens);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 before = address(this).balance;
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens, 0, path, address(this), block.timestamp
        );
        uint256 received = address(this).balance - before;
        if (received == 0) return;

        uint256 marketingCut = received / 2;
        uint256 devCut = received - marketingCut;

        feesOwed[marketingWallet] += marketingCut;
        feesOwed[devWallet] += devCut;

        emit FeesAccrued(marketingWallet, marketingCut);
        emit FeesAccrued(devWallet, devCut);
    }
}
