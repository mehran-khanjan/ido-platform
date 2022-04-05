// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract IDO is Ownable {
    using SafeERC20 for IERC20;

    string public idoTitle;

    event NewSelfStarter(address creator, address instance, uint256 blockCreated, uint version);

    constructor(string memory _title) {
        idoTitle = _title;
        emit NewSelfStarter(_msgSender(), address(this), block.timestamp, uint(0));
    }
}
