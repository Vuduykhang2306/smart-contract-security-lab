// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IDexRouter} from "../../src/interfaces/IDexRouter.sol";

interface IERC20Like {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @notice Minimal stand-in for the Uniswap V2 router.
/// @dev Reproduces the one behaviour that matters for these proofs of concept:
///      `swapExactTokensForETHSupportingFeeOnTransferTokens` pulls the input
///      tokens straight to the PAIR with `transferFrom`, which re-enters the
///      token's `_transfer`. The router pays ETH out of its own pre-funded
///      balance at a fixed rate instead of running a real constant-product curve.
contract MockDexRouter is IDexRouter {
    address public weth;
    address public pair;

    /// @notice wei paid per whole token swapped.
    uint256 public ethPerToken = 0.001 ether;

    constructor(address _weth) {
        weth = _weth;
    }

    function WETH() external view returns (address) {
        return weth;
    }

    function setPair(address _pair) external {
        pair = _pair;
    }

    function setEthPerToken(uint256 _ethPerToken) external {
        ethPerToken = _ethPerToken;
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external {
        IERC20Like(path[0]).transferFrom(msg.sender, pair, amountIn);

        uint256 ethOut = amountIn * ethPerToken / 1e18;
        (bool ok,) = to.call{value: ethOut}("");
        require(ok, "ROUTER: ETH payout failed");
    }

    receive() external payable {}
}
