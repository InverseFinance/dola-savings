// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IERC20 {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface IDBR {
    function mint(address, uint) external;
}

contract DolaSavings {

    IDBR public immutable dbr;
    IERC20 public immutable dola;
    address public gov;
    address public operator;
    uint public constant mantissa = 10**18;
    uint public maxYearlyRewardBudget = type(uint).max / 10000; // 10,000 years
    uint public maxRewardPerDolaMantissa = 10**18; // 1 DBR per DOLA
    uint public yearlyRewardBudget; // starts at 0
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalSupply;
    
    mapping (address => uint) public balanceOf;
    mapping (address => uint) public stakerIndexMantissa;
    mapping (address => uint) public accruedRewards;
    
    modifier updateIndex() {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(yearlyRewardBudget > 0 && totalSupply > 0) {
                uint maxBudget = maxRewardPerDolaMantissa * totalSupply / mantissa;
                uint budget = yearlyRewardBudget > maxBudget ? maxBudget : yearlyRewardBudget;
                uint rewardsAccrued = deltaT * (budget / 365 days) * mantissa;
                rewardIndexMantissa += rewardsAccrued / totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - stakerIndexMantissa[msg.sender];
        uint bal = balanceOf[msg.sender];
        uint stakerDelta = bal * deltaIndex;
        stakerIndexMantissa[msg.sender] = rewardIndexMantissa;
        accruedRewards[msg.sender] += stakerDelta / mantissa;
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

    constructor (IDBR _dbr, IERC20 _dola, address _gov, address _operator) {
        dbr = _dbr;
        dola = _dola;
        gov = _gov;
        operator = _operator;
        lastUpdate = block.timestamp;
    }

    function setOperator(address _operator) public onlyGov { operator = _operator; }
    function setGov(address _gov) public onlyGov { gov = _gov; }

    function setMaxYearlyRewardBudgetConstraints(uint _max) public onlyGov updateIndex {
        require(_max < type(uint).max / 10000); // cannot overflow and revert within 10,000 years
        maxYearlyRewardBudget = _max;
        if(yearlyRewardBudget > _max) {
            yearlyRewardBudget = _max;
        }
    }

    function setMaxRewardPerDolaMantissa(uint _max) public onlyGov updateIndex {
        maxRewardPerDolaMantissa = _max;
    }

    function setYearlyRewardBudget(uint _yearlyRewardBudget) public onlyOperator updateIndex {
        require(_yearlyRewardBudget <= maxYearlyRewardBudget, "REWARD BUDGET ABOVE MAX");
        yearlyRewardBudget = _yearlyRewardBudget;
    }

    function stake(uint amount, address recipient) public updateIndex {
        balanceOf[recipient] += amount;
        totalSupply += amount;
        dola.transferFrom(msg.sender, address(this), amount);
    }

    function unstake(uint amount) public updateIndex {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        dola.transfer(msg.sender, amount);
    }

    function claimable(address user) public view returns(uint) {
        uint deltaT = block.timestamp - lastUpdate;
        uint maxBudget = maxRewardPerDolaMantissa * totalSupply / mantissa;
        uint budget = yearlyRewardBudget > maxBudget ? maxBudget : yearlyRewardBudget;
        uint rewardsAccrued = deltaT * (budget / 365 days) * mantissa;
        uint _rewardIndexMantissa = totalSupply > 0 ? rewardIndexMantissa + (rewardsAccrued / totalSupply) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - stakerIndexMantissa[user];
        uint bal = balanceOf[user];
        uint stakerDelta = bal * deltaIndex / mantissa;
        return (accruedRewards[user] + stakerDelta);
    }

    function claim(address to) public updateIndex {
        dbr.mint(to, accruedRewards[msg.sender]);
        accruedRewards[msg.sender] = 0;
    }

}