// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice A single account an Echidna campaign can act through.
/// @dev Echidna has no cheatcodes, so there is no `vm.prank`. To get a call
///      whose `msg.sender` is somebody other than the harness, the harness has
///      to own a contract and forward through it. `receive()` is what lets the
///      account be paid by `claimDividend` and `withdrawFees`.
contract Puppet {
    function exec(address target, bytes memory data) external returns (bool ok) {
        (ok,) = target.call(data);
    }

    receive() external payable {}
}
