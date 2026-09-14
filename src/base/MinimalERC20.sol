// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MinimalERC20
/// @notice Compact ERC-20 base used so the audit target is self-contained and
///         reviewable in isolation.
/// @dev OUT OF SCOPE for the audit in `reports/`. It is deliberately boring:
///      no hooks, no permit, no upgradeability. Every finding in the report
///      lives in the derived contract, not here.
abstract contract MinimalERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ERC20: insufficient allowance");
            unchecked {
                allowance[from][msg.sender] = allowed - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    /// @dev Overridden by the token to insert tax / limit / swap logic.
    function _transfer(address from, address to, uint256 value) internal virtual {
        _rawTransfer(from, to, value);
    }

    function _rawTransfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "ERC20: balance too low");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner_, address spender, uint256 value) internal {
        allowance[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }
}
