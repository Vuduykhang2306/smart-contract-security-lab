// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeTax} from "../src/MemeTax.sol";
import {MockDexRouter} from "./mocks/MockDexRouter.sol";

/// @notice Shared deployment used by every proof of concept.
abstract contract BaseSetup is Test {
    MemeTax internal token;
    MockDexRouter internal router;

    address internal deployer = makeAddr("deployer");
    address internal marketing = makeAddr("marketing");
    address internal dev = makeAddr("dev");
    address internal pair = makeAddr("pair");
    address internal weth = makeAddr("weth");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal mallory = makeAddr("mallory");

    function _deploy() internal {
        _deployWith(marketing, dev);
    }

    function _deployWith(address _marketing, address _dev) internal {
        router = new MockDexRouter(weth);
        router.setPair(pair);
        vm.deal(address(router), 1_000 ether);

        vm.startPrank(deployer);
        token = new MemeTax(address(router), _marketing, _dev);
        token.setPair(pair);
        vm.stopPrank();
    }

    /// @dev The deployer is fee-exempt, so this funds holders without taxing them.
    function _fund(address to, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(to, amount);
    }

    /// @dev A sell is modelled as a plain transfer to the pair address.
    function _sell(address seller, uint256 amount) internal {
        vm.prank(seller);
        token.transfer(pair, amount);
    }
}
