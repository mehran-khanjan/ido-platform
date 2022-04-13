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

    modifier onlyPreLaunch(uint256 _id) {
        if(_isManual(_id)){
            require(!pools[_id].enabled, "Pool is already enabled");
            require(!pools[_id].finished, "Pool is already completed");
        }else{
            require(block.timestamp < pools[_id].startTime, "Pool start time has passed");
        }
        _;
    }

    function _isOnlyHolder(uint256 _id) internal view returns(bool){
        return ( pools[_id].onlyHolderToken != address(0) &&  pools[_id].minHolderBalance > uint256(0));
    }

    function _isManual(uint256 _id) internal view returns(bool){
        return ( pools[_id].startTime == 0 && pools[_id].timespan == 0);
    }

    function setMinHolderAmount(uint256 _id, uint256 _minHolderBalance) external onlyOwner onlyPreLaunch(_id) {
        pools[_id].minHolderBalance = _minHolderBalance;
    }

    function setHolderToken(uint256 _id, address _holderToken) external onlyOwner onlyPreLaunch(_id) {
        pools[_id].onlyHolderToken = _holderToken;
    }

    function setStartTime(uint256 _id, uint256 _startTime) external onlyOwner onlyPreLaunch(_id) {
        if(_startTime > 0){
            require(_startTime > block.timestamp, "Start time must be in future");
        }
        pools[_id].startTime = _startTime;
    }

    function setTimespan(uint256 _id, uint256 _timespan) external onlyOwner onlyPreLaunch(_id) {
        if(_timespan > 0){
            require((pools[_id].startTime + _timespan) > block.timestamp, "pool must end in the future, set start time");
        }
        require(pools[_id].startTime > 0, "Start time must be set first");
        uint256 computedTimespan = (pools[_id].startTime > 0 && _timespan < minSpan) ? minSpan : _timespan;
        pools[_id].timespan = computedTimespan;
    }

}
