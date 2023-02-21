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

    uint256 private minSuper = 1e19;

    uint256 private constant scaleFactor = 1e8;
    uint256 private constant defaultSpan = 1e5;

    Pool[] public pools;
    mapping(uint256 => uint256) public poolsSold;
    mapping(uint256 => mapping(address => uint256)) public lockedTokens;
    mapping(uint256 => mapping(address => uint256)) public whiteList;

    event NewPool(
        uint256 id,
        address indexed creator,
        address token,
        address swapToken,
        uint256 cap,
        uint256 price,
        bool isWhiteList,
        bool onlyHolder,
        uint256 maxCap
    );

    event Swap(
        uint256 id,
        uint256 roundID,
        address sender,
        uint256 amount,
        uint256 amt
    );

    event Claim(
        uint256 id,
        address indexed claimer,
        uint256 amount,
        uint256 timestamp
    );
    event PoolFinished(uint256 id, uint256 timestamp);
    event PoolStarted(uint256 id, uint256 timestamp);
    event WhiteList(uint256 id, uint256 timestamp);

    constructor(uint256 _minSuper, address _superToken) {
        minSuper = _minSuper;
        superToken = _superToken;
    }

    modifier onlyCreator(uint256 id) {
        require(pools[id].creator == _msgSender(), "Should be creator");
        _;
    }

    function addWhiteListBatch(uint256 id, address[] calldata _whiteList, uint256[] calldata _caps) external onlyOwner {
        for (uint256 i = 0; i < _whiteList.length; ++i) {
            whiteList[id][_whiteList[i]] = _caps[i];
        }
        emit WhiteList(id, block.timestamp);
    }
    
    function addWhiteList(uint256 id, address _whiteList, uint256 _cap) external onlyOwner {
        whiteList[id][_whiteList] = _cap;
        emit WhiteList(id, block.timestamp);

    }

    function updateMinSuper(uint256 _minSuper) external onlyOwner {
        minSuper = _minSuper;
    }

    function updateSuperToken(address _superToken) external onlyOwner {
        superToken = _superToken;
    }

    function poolsLength() external view returns (uint256) {
        return pools.length;
    }

    function createPool(
        address token,
        address swapToken,
        uint256 cap,
        uint256 price,
        bool isWhiteList,
        bool onlyHolder,
        uint256 maxCap
    ) external onlyOwner returns (uint256) {
        require(cap <= IERC20(token).balanceOf(_msgSender()) && cap > 0, "Cap check");
        require(token != address(0), "Pool token cannot be zero address");
        require(price > uint256(0), "Price must be greater than 0");
        Pool memory newPool =
            Pool(
                cap,
                price,
                maxCap,
                _msgSender(),
                token,
                swapToken,
                isWhiteList,
                onlyHolder,
                false,
                false
            );
        pools.push(newPool);
        uint256 id = pools.length;
        IERC20(token).safeTransferFrom(_msgSender(), address(this), cap);
        emit NewPool(
            id,
            _msgSender(),
            token,
            swapToken,
            cap,
            price,
            isWhiteList,
            onlyHolder,
            maxCap
        );
        return id;
    }

    function swap(uint256 id, uint256 amount) external payable {
        require(amount != 0, "Amount should not be zero");
        require(pools[id].enabled, "Pool must be enabled");
        if (pools[id].onlyHolder) {
            require(IERC20(superToken).balanceOf(_msgSender()) >= minSuper, "Miniumum for the pool");
        }
        if (pools[id].isWhiteList) {
            require(whiteList[id][_msgSender()] > 0, "Should be white listed for the pool");
        }
        if (pools[id].swapToken == address(0)) {
            require(amount == msg.value, "Amount is not equal msg.value");
        }
        _simpleSwap(id, amount);
    }

    function _simpleSwap(uint256 id, uint256 amount) internal {
        Pool memory pool = pools[id];
        uint256 left = pool.cap - poolsSold[id];
        uint256 curLocked = lockedTokens[id][_msgSender()];
        if (left > pool.maxCap - curLocked) {
            left = pool.maxCap - curLocked;
        }
        if (pool.isWhiteList && left > whiteList[id][_msgSender()] - curLocked) {
            left = whiteList[id][_msgSender()] - curLocked;
        }
        require(left > 0, "Not enough tokens for swap");
        uint256 amt = (pool.price * amount) / scaleFactor;

        uint256 back = 0;
        if (left < amt) {
            amt = left;
            uint256 newAmount = (amt * scaleFactor) / pool.price;

            back = amount - newAmount;
            amount = newAmount;
        }
        lockedTokens[id][_msgSender()] = curLocked + amt;
        poolsSold[id] = poolsSold[id ]+ amt;
        if (pool.swapToken == address(0)) {
            (bool success, ) = payable(pool.creator).call{value: amount}("");
            require(success, "Should transfer ethers to the pool creator");
            if (back > 0) {
                (success, ) = _msgSender().call{value: back}("");
                require(success, "Should transfer left ethers back to the user");
            }
        } else {
            IERC20(pool.swapToken).safeTransfer(
                pool.creator,
                amount
            );
        }
        emit Swap(id, 0, _msgSender(), amount, amt);
    }

    function startPool(uint256 id) external onlyCreator(id) {
        require(!pools[id].enabled, "Pool is already enabled");
        require(!pools[id].finished, "Pool is already completed");
        pools[id].enabled = true;
        emit PoolStarted(id, block.timestamp);
    }

    function finishPool(uint256 id) external onlyCreator(id) {
        require(pools[id].enabled, "Pool is not enabled");
        require(!pools[id].finished, "Pool is already completed");
        pools[id].enabled = false;
        pools[id].finished = true;
        emit PoolFinished(id, block.timestamp);
    }

    function claim(uint256 id) external nonReentrant {
        require(pools[id].finished, "Cannot claim until pool is finished");
        require(lockedTokens[id][_msgSender()] > 0, "Should have tokens to claim");
        uint256 amount = lockedTokens[id][_msgSender()];
        lockedTokens[id][_msgSender()] = 0;
        IERC20(pools[id].token).safeTransfer(_msgSender(), amount);
        emit Claim(id, _msgSender(), amount, block.timestamp);
    }

    modifier atStageOrderPlacement(uint256 auctionId) {
        require(
            block.timestamp < auctionData[auctionId].auctionEndDate,
            "no longer in order placement phase"
        );
        _;
    }

    modifier atStageOrderPlacementAndCancelation(uint256 auctionId) {
        require(
            block.timestamp < auctionData[auctionId].orderCancellationEndDate,
            "no longer in order placement and cancelation phase"
        );
        _;
    }

    modifier atStageSolutionSubmission(uint256 auctionId) {
        {
            uint256 auctionEndDate = auctionData[auctionId].auctionEndDate;
            require(
                auctionEndDate != 0 &&
                    block.timestamp >= auctionEndDate &&
                    auctionData[auctionId].clearingPriceOrder == bytes32(0),
                "Auction not in solution submission phase"
            );
        }
        _;
    }

    modifier atStageFinished(uint256 auctionId) {
        require(
            auctionData[auctionId].clearingPriceOrder != bytes32(0),
            "Auction not yet finished"
        );
        _;
    }

    event NewSellOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 buyAmount,
        uint96 sellAmount
    );

    event CancellationSellOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 buyAmount,
        uint96 sellAmount
    );

    event ClaimedFromOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 buyAmount,
        uint96 sellAmount
    );

    event NewUser(uint64 indexed userId, address indexed userAddress);
    event NewAuction(
        uint256 indexed auctionId,
        IERC20 indexed _auctioningToken,
        IERC20 indexed _biddingToken,
        uint256 orderCancellationEndDate,
        uint256 auctionEndDate,
        uint64 userId,
        uint96 _auctionedSellAmount,
        uint96 _minBuyAmount,
        uint256 minimumBiddingAmountPerOrder,
        uint256 minFundingThreshold,
        address allowListContract,
        bytes allowListData
    );

    event AuctionCleared(
        uint256 indexed auctionId,
        uint96 soldAuctioningTokens,
        uint96 soldBiddingTokens,
        bytes32 clearingPriceOrder
    );
    event UserRegistration(address indexed user, uint64 userId);

    struct AuctionData {
        IERC20 auctioningToken;
        IERC20 biddingToken;
        uint256 orderCancellationEndDate;
        uint256 auctionEndDate;
        bytes32 initialAuctionOrder;
        uint256 minimumBiddingAmountPerOrder;
        uint256 interimSumBidAmount;
        bytes32 interimOrder;
        bytes32 clearingPriceOrder;
        uint96 volumeClearingPriceOrder;
        bool minFundingThresholdNotReached;
        bool isAtomicClosureAllowed;
        uint256 feeNumerator;
        uint256 minFundingThreshold;
    }

    mapping(uint256 => IterableOrderedOrderSet.Data) internal sellOrders;
    mapping(uint256 => AuctionData) public auctionData;
    mapping(uint256 => address) public auctionAccessManager;
    mapping(uint256 => bytes) public auctionAccessData;

    IdToAddressBiMap.Data private registeredUsers;

    uint64 public numUsers;
    uint256 public auctionCounter;

    constructor() public Ownable() {}

    uint256 public feeNumerator = 0;
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint64 public feeReceiverUserId = 1;

    function setFeeParameters(
        uint256 newFeeNumerator,
        address newfeeReceiverAddress
    ) public onlyOwner() {
        require(
            newFeeNumerator <= 15,
            "Fee is not allowed to be set higher than 1.5%"
        );
        // caution: for currently running auctions, the feeReceiverUserId is changing as well.
        feeReceiverUserId = getUserId(newfeeReceiverAddress);
        feeNumerator = newFeeNumerator;
    }

    function initiateAuction(
        IERC20 _auctioningToken,
        IERC20 _biddingToken,
        uint256 orderCancellationEndDate,
        uint256 auctionEndDate,
        uint96 _auctionedSellAmount,
        uint96 _minBuyAmount,
        uint256 minimumBiddingAmountPerOrder,
        uint256 minFundingThreshold,
        bool isAtomicClosureAllowed,
        address accessManagerContract,
        bytes memory accessManagerContractData
    ) public returns (uint256) {
        // withdraws sellAmount + fees
        _auctioningToken.safeTransferFrom(
            msg.sender,
            address(this),
            _auctionedSellAmount.mul(FEE_DENOMINATOR.add(feeNumerator)).div(
                FEE_DENOMINATOR
            ) //[0]
        );

        require(_auctionedSellAmount > 0, "cannot auction zero tokens");
        require(_minBuyAmount > 0, "tokens cannot be auctioned for free");
        require(
            minimumBiddingAmountPerOrder > 0,
            "minimumBiddingAmountPerOrder is not allowed to be zero"
        );

        require(
            orderCancellationEndDate <= auctionEndDate,
            "time periods are not configured correctly"
        );

        require(
            auctionEndDate > block.timestamp,
            "auction end date must be in the future"
        );

        auctionCounter = auctionCounter.add(1);
        sellOrders[auctionCounter].initializeEmptyList();
        uint64 userId = getUserId(msg.sender);

        auctionData[auctionCounter] = AuctionData(
            _auctioningToken,
            _biddingToken,
            orderCancellationEndDate,
            auctionEndDate,
            IterableOrderedOrderSet.encodeOrder(
                userId,
                _minBuyAmount,
                _auctionedSellAmount
            ),
            minimumBiddingAmountPerOrder,
            0,
            IterableOrderedOrderSet.QUEUE_START,
            bytes32(0),
            0,
            false,
            isAtomicClosureAllowed,
            feeNumerator,
            minFundingThreshold
        );
        auctionAccessManager[auctionCounter] = accessManagerContract;
        auctionAccessData[auctionCounter] = accessManagerContractData;

        emit NewAuction(
            auctionCounter,
            _auctioningToken,
            _biddingToken,
            orderCancellationEndDate,
            auctionEndDate,
            userId,
            _auctionedSellAmount,
            _minBuyAmount,
            minimumBiddingAmountPerOrder,
            minFundingThreshold,
            accessManagerContract,
            accessManagerContractData
        );
        return auctionCounter;
    }

     function placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData
    ) external atStageOrderPlacement(auctionId) returns (uint64 userId) {
        return
            _placeSellOrders(
                auctionId,
                _minBuyAmounts,
                _sellAmounts,
                _prevSellOrders,
                allowListCallData,
                msg.sender
            );
    }

    function placeSellOrdersOnBehalf(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData,
        address orderSubmitter
    ) external atStageOrderPlacement(auctionId) returns (uint64 userId) {
        return
            _placeSellOrders(
                auctionId,
                _minBuyAmounts,
                _sellAmounts,
                _prevSellOrders,
                allowListCallData,
                orderSubmitter
            );
    }

    function placeSellOrdersOnBehalf(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData,
        address orderSubmitter
    ) external atStageOrderPlacement(auctionId) returns (uint64 userId) {
        return
            _placeSellOrders(
                auctionId,
                _minBuyAmounts,
                _sellAmounts,
                _prevSellOrders,
                allowListCallData,
                orderSubmitter
            );
    }

    function _placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData,
        address orderSubmitter
    ) internal returns (uint64 userId) {
        address allowListManager = auctionAccessManager[auctionId];
        if (allowListManager != address(0)) {
            require(
                    AllowListVerifier(allowListManager).isAllowed(
                        orderSubmitter,
                        auctionId,
                        allowListCallData
                    ) == AllowListVerifierHelper.MAGICVALUE,
                    "user not allowed to place order"
                );
        }

        {
            (
                ,
                uint96 buyAmountOfInitialAuctionOrder,
                uint96 sellAmountOfInitialAuctionOrder
            ) = auctionData[auctionId].initialAuctionOrder.decodeOrder();

            for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
                require(
                    _minBuyAmounts[i].mul(buyAmountOfInitialAuctionOrder) <
                        sellAmountOfInitialAuctionOrder.mul(_sellAmounts[i]),
                    "limit price not better than mimimal offer"
                );
            }
        }

        uint256 sumOfSellAmounts = 0;
        userId = getUserId(orderSubmitter);
        uint256 minimumBiddingAmountPerOrder =
            auctionData[auctionId].minimumBiddingAmountPerOrder;
            for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
                require(
                    _minBuyAmounts[i] > 0,
                    "_minBuyAmounts must be greater than 0"
                );

                require(
                _sellAmounts[i] > minimumBiddingAmountPerOrder,
                "order too small"
            );
            }

        if (
                sellOrders[auctionId].insert(
                    IterableOrderedOrderSet.encodeOrder(
                        userId,
                        _minBuyAmounts[i],
                        _sellAmounts[i]
                    ),
                    _prevSellOrders[i]
                )
            ) {
                sumOfSellAmounts = sumOfSellAmounts.add(_sellAmounts[i]);
                emit NewSellOrder(
                    auctionId,
                    userId,
                    _minBuyAmounts[i],
                    _sellAmounts[i]
                );
            }

        auctionData[auctionId].biddingToken.safeTransferFrom(
            msg.sender,
            address(this),
            sumOfSellAmounts
        );

        function cancelSellOrders(uint256 auctionId, bytes32[] memory _sellOrders)
        public
        atStageOrderPlacementAndCancelation(auctionId)
        {
            uint64 userId = getUserId(msg.sender);
            auctionData[auctionCounter] = AuctionData(
            _auctioningToken,
            _biddingToken,
            orderCancellationEndDate,
            auctionEndDate,
            IterableOrderedOrderSet.encodeOrder(
                userId,
                _minBuyAmount,
                _auctionedSellAmount
            ),
            minimumBiddingAmountPerOrder,
            0,
            IterableOrderedOrderSet.QUEUE_START,
            bytes32(0),
            0,
            false,
            isAtomicClosureAllowed,
            feeNumerator,
            minFundingThreshold
        );
        }

        auctionAccessManager[auctionCounter] = accessManagerContract;
        auctionAccessData[auctionCounter] = accessManagerContractData;

        emit NewAuction(
            auctionCounter,
            _auctioningToken,
            _biddingToken,
            orderCancellationEndDate,
            auctionEndDate,
            userId,
            _auctionedSellAmount,
            _minBuyAmount,
            minimumBiddingAmountPerOrder,
            minFundingThreshold,
            accessManagerContract,
            accessManagerContractData
        );
        return auctionCounter;
    }

    function placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData
    ) external atStageOrderPlacement(auctionId) returns (uint64 userId) {
        return
            _placeSellOrders(
                auctionId,
                _minBuyAmounts,
                _sellAmounts,
                _prevSellOrders,
                allowListCallData,
                msg.sender
            )
    }

    function placeSellOrdersOnBehalf(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData,
        address orderSubmitter
    ) external atStageOrderPlacement(auctionId) returns (uint64 userId) {
        return
            _placeSellOrders(
                auctionId,
                _minBuyAmounts,
                _sellAmounts,
                _prevSellOrders,
                allowListCallData,
                orderSubmitter
            );
    }

    function _placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders,
        bytes calldata allowListCallData,
        address orderSubmitter
    ) internal returns (uint64 userId) {
        
        address allowListManager = auctionAccessManager[auctionId];
        if (allowListManager != address(0)) {
            require(
                    AllowListVerifier(allowListManager).isAllowed(
                        orderSubmitter,
                        auctionId,
                        allowListCallData
                    ) == AllowListVerifierHelper.MAGICVALUE,
                    "user not allowed to place order"
                );
        }
    

    {
            (
                ,
                uint96 buyAmountOfInitialAuctionOrder,
                uint96 sellAmountOfInitialAuctionOrder
            ) = auctionData[auctionId].initialAuctionOrder.decodeOrder();

            for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
                require(
                    _minBuyAmounts[i].mul(buyAmountOfInitialAuctionOrder) <
                        sellAmountOfInitialAuctionOrder.mul(_sellAmounts[i]),
                    "limit price not better than mimimal offer"
                );
            }
    }

    uint256 sumOfSellAmounts = 0;
    userId = getUserId(orderSubmitter);
    uint256 minimumBiddingAmountPerOrder =
            auctionData[auctionId].minimumBiddingAmountPerOrder;
            
    for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
        require(
                    _minBuyAmounts[i].mul(buyAmountOfInitialAuctionOrder) <
                        sellAmountOfInitialAuctionOrder.mul(_sellAmounts[i]),
                    "limit price not better than mimimal offer"
                );

        require(
                _sellAmounts[i] > minimumBiddingAmountPerOrder,
                "order too small"
            );

        if (
                sellOrders[auctionId].insert(
                    IterableOrderedOrderSet.encodeOrder(
                        userId,
                        _minBuyAmounts[i],
                        _sellAmounts[i]
                    ),
                    _prevSellOrders[i]
                )
            ) {
                sumOfSellAmounts = sumOfSellAmounts.add(_sellAmounts[i]);
                emit NewSellOrder(
                    auctionId,
                    userId,
                    _minBuyAmounts[i],
                    _sellAmounts[i]
                );
            }
    }

    auctionData[auctionId].biddingToken.safeTransferFrom(
            msg.sender,
            address(this),
            sumOfSellAmounts
        ); //[1]

    }

     function cancelSellOrders(uint256 auctionId, bytes32[] memory _sellOrders)
        public
        atStageOrderPlacementAndCancelation(auctionId)
    {
        uint64 userId = getUserId(msg.sender);
        uint256 claimableAmount = 0;
        for (uint256 i = 0; i < _sellOrders.length; i++) {
            // Note: we keep the back pointer of the deleted element so that
            // it can be used as a reference point to insert a new node.
            bool success =
                sellOrders[auctionId].removeKeepHistory(_sellOrders[i]);

                if (success) {
                (
                        uint64 userIdOfIter,
                        uint96 buyAmountOfIter,
                        uint96 sellAmountOfIter
                ) = _sellOrders[i].decodeOrder();

                require(
                    userIdOfIter == userId,
                    "Only the user can cancel his orders"
                );

                 claimableAmount = claimableAmount.add(sellAmountOfIter);

                 emit CancellationSellOrder(
                    auctionId,
                    userId,
                    buyAmountOfIter,
                    sellAmountOfIter
                );
                
                }
        }

        auctionData[auctionId].biddingToken.safeTransfer(
            msg.sender,
            claimableAmount
        ); //[2]
    }

    function precalculateSellAmountSum(
        uint256 auctionId,
        uint256 iterationSteps
    ) public atStageSolutionSubmission(auctionId) {
        (, , uint96 auctioneerSellAmount) =
            auctionData[auctionId].initialAuctionOrder.decodeOrder();
            for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
                require(
                    _minBuyAmounts[i].mul(buyAmountOfInitialAuctionOrder) <
                        sellAmountOfInitialAuctionOrder.mul(_sellAmounts[i]),
                    "limit price not better than mimimal offer"
                );
            }

        uint256 sumOfSellAmounts = 0;
        userId = getUserId(orderSubmitter);
        uint256 minimumBiddingAmountPerOrder =
            auctionData[auctionId].minimumBiddingAmountPerOrder;
        
        for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
            require(
                _minBuyAmounts[i] > 0,
                "_minBuyAmounts must be greater than 0"
            );
            
            // orders should have a minimum bid size in order to limit the gas
            // required to compute the final price of the auction.
            require(
                _sellAmounts[i] > minimumBiddingAmountPerOrder,
                "order too small"
            );

            if (
                sellOrders[auctionId].insert(
                    IterableOrderedOrderSet.encodeOrder(
                        userId,
                        _minBuyAmounts[i],
                        _sellAmounts[i]
                    ),
                    _prevSellOrders[i]
                )
            ) {
                sumOfSellAmounts = sumOfSellAmounts.add(_sellAmounts[i]);
                emit NewSellOrder(
                    auctionId,
                    userId,
                    _minBuyAmounts[i],
                    _sellAmounts[i]
                );
            }

        }

        auctionData[auctionId].biddingToken.safeTransferFrom(
            msg.sender,
            address(this),
            sumOfSellAmounts
        ); //[1]
    }

    function cancelSellOrders(uint256 auctionId, bytes32[] memory _sellOrders)
        public
        atStageOrderPlacementAndCancelation(auctionId)
    {
        uint64 userId = getUserId(msg.sender);
        uint256 claimableAmount = 0;
        for (uint256 i = 0; i < _sellOrders.length; i++) {
            // Note: we keep the back pointer of the deleted element so that
            // it can be used as a reference point to insert a new node.
            bool success =
                sellOrders[auctionId].removeKeepHistory(_sellOrders[i]);
                if (success) {
                    (
                    uint64 userIdOfIter,
                    uint96 buyAmountOfIter,
                    uint96 sellAmountOfIter
                ) = _sellOrders[i].decodeOrder();
                require(
                    userIdOfIter == userId,
                    "Only the user can cancel his orders"
                );
                claimableAmount = claimableAmount.add(sellAmountOfIter);
                emit CancellationSellOrder(
                    auctionId,
                    userId,
                    buyAmountOfIter,
                    sellAmountOfIter
                );
                }
        }

        auctionData[auctionId].biddingToken.safeTransfer(
            msg.sender,
            claimableAmount
        ); //[2]
    }

    function precalculateSellAmountSum(
        uint256 auctionId,
        uint256 iterationSteps
    ) public atStageSolutionSubmission(auctionId) {
        (, , uint96 auctioneerSellAmount) =
            auctionData[auctionId].initialAuctionOrder.decodeOrder();
        
        uint256 sumBidAmount = auctionData[auctionId].interimSumBidAmount;
        bytes32 iterOrder = auctionData[auctionId].interimOrder;
        for (uint256 i = 0; i < iterationSteps; i++) {
            iterOrder = sellOrders[auctionId].next(iterOrder);
            (, , uint96 sellAmountOfIter) = iterOrder.decodeOrder();
            sumBidAmount = sumBidAmount.add(sellAmountOfIter);
        }

        require(
            iterOrder != IterableOrderedOrderSet.QUEUE_END,
            "reached end of order list"
        );

        (, uint96 buyAmountOfIter, uint96 sellAmountOfIter) =
            iterOrder.decodeOrder();
            
        require(
            sumBidAmount.mul(buyAmountOfIter) <
                auctioneerSellAmount.mul(sellAmountOfIter),
            "too many orders summed up"
        );

        auctionData[auctionId].interimSumBidAmount = sumBidAmount;
        auctionData[auctionId].interimOrder = iterOrder;
    }

    function settleAuctionAtomically(
        uint256 auctionId,
        uint96[] memory _minBuyAmount,
        uint96[] memory _sellAmount,
        bytes32[] memory _prevSellOrder,
        bytes calldata allowListCallData
    ) public atStageSolutionSubmission(auctionId) {
        require(
            auctionData[auctionId].isAtomicClosureAllowed,
            "not allowed to settle auction atomically"
        );
        require(
            _minBuyAmount.length == 1 && _sellAmount.length == 1,
            "Only one order can be placed atomically"
        );
        uint64 userId = getUserId(msg.sender);
        require(
            auctionData[auctionId].interimOrder.smallerThan(
                IterableOrderedOrderSet.encodeOrder(
                    userId,
                    _minBuyAmount[0],
                    _sellAmount[0]
                )
            ),
            "precalculateSellAmountSum is already too advanced"
        );
        _placeSellOrders(
            auctionId,
            _minBuyAmount,
            _sellAmount,
            _prevSellOrder,
            allowListCallData,
            msg.sender
        );
        settleAuction(auctionId);
    }

    // @dev function settling the auction and calculating the price
    function settleAuction(uint256 auctionId)
        public
        atStageSolutionSubmission(auctionId)
        returns (bytes32 clearingOrder)
    {
        (
            uint64 auctioneerId,
            uint96 minAuctionedBuyAmount,
            uint96 fullAuctionedAmount
        ) = auctionData[auctionId].initialAuctionOrder.decodeOrder();

        uint256 currentBidSum = auctionData[auctionId].interimSumBidAmount;
        bytes32 currentOrder = auctionData[auctionId].interimOrder;
        uint256 buyAmountOfIter;
        uint256 sellAmountOfIter;
        uint96 fillVolumeOfAuctioneerOrder = fullAuctionedAmount;
        do {
            bytes32 nextOrder = sellOrders[auctionId].next(currentOrder);
            if (nextOrder == IterableOrderedOrderSet.QUEUE_END) {
                break;
            }
            currentOrder = nextOrder;
            (, buyAmountOfIter, sellAmountOfIter) = currentOrder.decodeOrder();
            currentBidSum = currentBidSum.add(sellAmountOfIter);
        } while (
            currentBidSum.mul(buyAmountOfIter) <
                fullAuctionedAmount.mul(sellAmountOfIter)
        );

        if (
            currentBidSum > 0 &&
            currentBidSum.mul(buyAmountOfIter) >=
            fullAuctionedAmount.mul(sellAmountOfIter)
        ) {
            uint256 uncoveredBids =
                currentBidSum.sub(
                    fullAuctionedAmount.mul(sellAmountOfIter).div(
                        buyAmountOfIter
                    )
                );
            
            if (sellAmountOfIter >= uncoveredBids) {
                uint256 sellAmountClearingOrder =
                    sellAmountOfIter.sub(uncoveredBids);
                
                auctionData[auctionId]
                    .volumeClearingPriceOrder = sellAmountClearingOrder
                    .toUint96();
                currentBidSum = currentBidSum.sub(uncoveredBids);
                clearingOrder = currentOrder;
                
            } else {
                currentBidSum = currentBidSum.sub(sellAmountOfIter);
            }
        }
    }

}
