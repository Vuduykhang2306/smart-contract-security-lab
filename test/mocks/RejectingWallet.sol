// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice A fee wallet that can't receive ETH (no `receive`, no `fallback`).
/// @dev Stands in for real cases: a multisig or contract wallet whose fallback
///      needs more gas than it gets, or an address that later became a
///      contract.
contract RejectingWallet {
    uint256 public touched;

    function ping() external {
        touched++;
    }
}
