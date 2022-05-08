// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../base/Sweepable.sol";

contract SuperStarter is Ownable, ReentrancyGuard, Sweepable {
    using SafeERC20 for IERC20;

    struct Pool {
        uint256 cap;
        uint256 price;
        uint256 maxCap;
        address creator;
        address token;
        address swapToken;
        bool isWhiteList;
        bool onlyHolder;
        bool enabled;
        bool finished;
    }

    address public superToken;
}
