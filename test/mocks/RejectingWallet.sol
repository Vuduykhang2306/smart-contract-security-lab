// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice A fee wallet that cannot receive ETH: no `receive`, no `fallback`.
/// @dev Models the realistic case of a Gnosis Safe / multisig or a contract
///      wallet whose fallback costs more than the 2300 gas stipend, or simply
///      a wallet that was replaced by a contract after deployment.
contract RejectingWallet {
    uint256 public touched;

    function ping() external {
        touched++;
    }
}
