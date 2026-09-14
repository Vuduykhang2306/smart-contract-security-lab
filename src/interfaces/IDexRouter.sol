// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice Subset of the Uniswap V2 router used by the token's fee swap.
interface IDexRouter {
    function WETH() external view returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
