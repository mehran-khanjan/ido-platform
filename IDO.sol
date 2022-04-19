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

    function setTitle(string memory _title) external onlyOwner{
        idoTitle = _title;
    }

    function addWhiteList(uint256 id, address[] calldata _whiteList, uint256[] calldata _caps) external onlyOwner onlyPreLaunch(id) {
        require(_whiteList.length == _caps.length, "whitelist array length mismatch");
        for (uint256 i = 0; i < _whiteList.length; ++i) {
            whiteList[id][_whiteList[i]] = _caps[i];
        }
        emit WhiteList(id);
    }

    function poolsLength() external view returns (uint256) {
        return pools.length;
    }

    function createPool(
        uint256 cap,
        uint256 price,
        uint256 maxContribution,
        IERC20 token,
        bool isWhiteList,
        address onlyHolderToken,
        uint256 minHolderBalance,
        uint256 startTime,
        uint256 timespan

    ) external onlyOwner returns (uint256) {
        require(cap <= token.balanceOf(_msgSender()) && cap > 0, "Cap check");
        require(address(token) != address(0), "Pool token cannot be zero address");
        require(price > uint256(0), "Price must be greater than 0");
        if(startTime > 0){
            require(startTime > block.timestamp, "Start time must be in future");
        }
        uint256 computedTimespan = (startTime > 0 && timespan < minSpan) ? minSpan : timespan;
        Pool memory newPool =
        Pool(
            cap,
            price,
            maxContribution,
            token,
            isWhiteList,
            onlyHolderToken,
            minHolderBalance,
            startTime,
            computedTimespan,
            false,
            false
        );
        pools.push(newPool);
        token.transferFrom(_msgSender(), address(this), cap);
        emit NewPool(_msgSender(), address(this), pools.length);
        return pools.length;
    }

    function swap(uint256 id, uint256 amount) external payable {
        require(amount != 0, "Amount should not be zero");
        if(_isManual(id)){
            require(pools[id].enabled, "Pool must be enabled");
        }else{
            require(pools[id].startTime < block.timestamp && block.timestamp < pools[id].startTime + pools[id].timespan, "TIME: Pool not open");
        }
        if (_isOnlyHolder(id)) {
            require(IERC20(pools[id].onlyHolderToken).balanceOf(_msgSender()) >= pools[id].minHolderBalance, "Miniumum balance not met");
        }
        if (pools[id].isWhiteList) {
            require(whiteList[id][_msgSender()] > 0, "Should be white listed for the pool");
        }
        require(amount == msg.value, "Amount is not equal msg.value");

        Pool memory pool = pools[id];
        uint256 left = pool.cap - poolsSold[id];

        //console.log("left1", left);
        uint256 curLocked = lockedTokens[id][_msgSender()];
        if (left > pool.maxContribution - curLocked) {
            left = pool.maxContribution - curLocked;
        }
        //console.log("left2", left);
        if (pools[id].isWhiteList && left >= whiteList[id][_msgSender()] - curLocked) {
            left = whiteList[id][_msgSender()] - curLocked;
        }
        //console.log("left3", left);
        //console.log("curLocked", curLocked, "allo", whiteList[id][_msgSender()]);

        uint256 amt = (pool.price * amount) / scaleFactor;

        //console.log("amt", amt);
        require(left > 0, "Not enough tokens for swap");
        uint256 back = 0;
        if (left < amt) {
            //console.log("left", left);
            //console.log("amt_", amt);
            amt = left;
            uint256 newAmount = (amt * scaleFactor) / pool.price;
            back = amount - newAmount;
            amount = newAmount;
        }
        lockedTokens[id][_msgSender()] = curLocked + amt;
        poolsSold[id] = poolsSold[id] + amt;

        (bool success, ) = owner().call{value: amount}("");
        require(success, "Should transfer ethers to the pool creator");
        if (back > 0) {
            (success, ) = _msgSender().call{value: back}("");
            require(success, "Should transfer left ethers back to the user");
        }

        emit Swap(id, 0, _msgSender(), amount, amt);
    }
}
