// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @notice One account the Echidna campaign can act through.
/// @dev Echidna has no cheatcodes, so there is no `vm.prank`. To make a call
///      with a different `msg.sender`, the harness owns a contract like this
///      and sends the call through it. `receive()` lets the account get paid
///      by `claimDividend` and `withdrawFees`.
contract Puppet {
    function exec(address target, bytes memory data) external returns (bool ok) {
        (ok,) = target.call(data);
    }

    receive() external payable {}
}
