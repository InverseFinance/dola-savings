// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IERC20 {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface IDBR {
    function mint(address, uint) external;
}

contract DolaSavings {

    IDBR public immutable dbr;
    IERC20 public immutable dola;
    address public gov;
    address public pendingGov;
    address public operator;
    uint public constant mantissa = 10**18;
    uint public maxYearlyRewardBudget;
    uint public maxRewardPerDolaMantissa = 10**18; // 1 DBR per DOLA
    uint public yearlyRewardBudget; // starts at 0
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalSupply;
    
    mapping (address => uint) public balanceOf;
    mapping (address => uint) public stakerIndexMantissa;
    mapping (address => uint) public accruedRewards;
    
    modifier updateIndex(address user) {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(yearlyRewardBudget > 0 && totalSupply > 0) {
                uint _totalSupply = totalSupply;
                uint _yearlyRewardBudget = yearlyRewardBudget;
                uint maxBudget = maxRewardPerDolaMantissa * _totalSupply / mantissa;
                uint budget = _yearlyRewardBudget > maxBudget ? maxBudget : _yearlyRewardBudget;
                uint rewardsAccrued = deltaT * budget * mantissa / 365 days;
                rewardIndexMantissa += rewardsAccrued / _totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - stakerIndexMantissa[user];
        uint bal = balanceOf[user];
        uint stakerDelta = bal * deltaIndex;
        stakerIndexMantissa[user] = rewardIndexMantissa;
        accruedRewards[user] += stakerDelta / mantissa;
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "ONLY OPERATOR");
        _;
    }

    constructor (address _dbr, address _dola, address _gov, address _operator) {
        dbr = IDBR(_dbr);
        dola = IERC20(_dola);
        gov = _gov;
        operator = _operator;
        lastUpdate = block.timestamp;
    }

    function setOperator(address _operator) external onlyGov { operator = _operator; }
    function setPendingGov(address _gov) external onlyGov { pendingGov = _gov; }
    function acceptGov() external {
        require(msg.sender == pendingGov, "Only pendingGov");
        gov = pendingGov;
        pendingGov = address(0);
    }

    function setMaxYearlyRewardBudget(uint _max) external onlyGov updateIndex(msg.sender) {
        maxYearlyRewardBudget = _max;
        if(yearlyRewardBudget > _max) {
            yearlyRewardBudget = _max;
            emit SetYearlyRewardBudget(_max);
        }
        emit SetMaxYearlyRewardBudget(_max);
    }

    function setMaxRewardPerDolaMantissa(uint _max) external onlyGov updateIndex(msg.sender) {
        require(_max < type(uint).max / (mantissa * 10 ** 13)); //May overflow if set to max and more than 10 trillion DOLA has been deposited
        maxRewardPerDolaMantissa = _max;
        emit SetMaxRewardPerDolaMantissa(_max);
    }

    function setYearlyRewardBudget(uint _yearlyRewardBudget) external onlyOperator updateIndex(msg.sender) {
        require(_yearlyRewardBudget <= maxYearlyRewardBudget, "REWARD BUDGET ABOVE MAX");
        yearlyRewardBudget = _yearlyRewardBudget;
        emit SetYearlyRewardBudget(_yearlyRewardBudget);
    }

    function stake(uint amount, address recipient) external updateIndex(recipient) {
        require(recipient != address(0), "Zero address");
        balanceOf[recipient] += amount;
        totalSupply += amount;
        dola.transferFrom(msg.sender, address(this), amount);
        emit Stake(msg.sender, recipient, amount);
    }

    function unstake(uint amount) external updateIndex(msg.sender) {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        dola.transfer(msg.sender, amount);
        emit Unstake(msg.sender, amount);
    }

    function claimable(address user) external view returns(uint) {
        uint _totalSupply = totalSupply;
        uint _yearlyRewardBudget = yearlyRewardBudget;
        uint _rewardIndexMantissa = rewardIndexMantissa;
        uint deltaT = block.timestamp - lastUpdate;
        uint maxBudget = maxRewardPerDolaMantissa * _totalSupply / mantissa;
        uint budget = _yearlyRewardBudget > maxBudget ? maxBudget : _yearlyRewardBudget;
        uint rewardsAccrued = deltaT * budget * mantissa / 365 days;
        _rewardIndexMantissa = _totalSupply > 0 ? _rewardIndexMantissa + rewardsAccrued / _totalSupply : _rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - stakerIndexMantissa[user];
        uint bal = balanceOf[user];
        uint stakerDelta = bal * deltaIndex / mantissa;
        return (accruedRewards[user] + stakerDelta);
    }

    function claim(address to) external updateIndex(msg.sender) {
        dbr.mint(to, accruedRewards[msg.sender]);
        accruedRewards[msg.sender] = 0;
        emit Claim(msg.sender, to);
    }

    function sweep(address token, uint amount, address to) external onlyGov {
        if(token == address(dola)) {
            require(IERC20(token).balanceOf(address(this)) - totalSupply >= amount, "CANNOT SWEEP USER DOLA");
        }
        IERC20(token).transfer(to, amount);
    }

    event Stake(address indexed caller, address indexed recipient, uint amount);
    event Unstake(address indexed caller, uint amount);
    event Claim(address indexed caller, address indexed recipient);

    event SetYearlyRewardBudget(uint newYearlyRewardBudget);
    event SetMaxRewardPerDolaMantissa(uint newMax);
    event SetMaxYearlyRewardBudget(uint newMax);
}
