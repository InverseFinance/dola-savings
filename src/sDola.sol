// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "lib/solmate/src/mixins/ERC4626.sol";

interface IDolaSavings {
    function balanceOf(address user) external view returns (uint);
    function stake(uint amount, address recipient) external;
    function unstake(uint amount) external;
    function claim(address to) external;
    function claimable(address user) external view returns (uint);
    function dbr() external view returns (address);
}

contract sDola is ERC4626 {
    
    uint constant MIN_BALANCE = 10**16; // 1 cent
    IDolaSavings public immutable savings;
    ERC20 public immutable dbr;
    address public gov;
    uint public prevK;
    uint public targetK;
    uint public lastKUpdate;
    mapping (uint => uint) public weeklyRevenue;

    constructor(
        address _dola,
        address _savings,
        address _gov,
        uint _K
    ) ERC4626(ERC20(_dola), "Super Dola", "sDOLA") {
        require(_K > 0, "_K must be positive");
        savings = IDolaSavings(_savings);
        dbr = ERC20(IDolaSavings(_savings).dbr());
        gov = _gov;
        targetK = _K;
        asset.approve(_savings, type(uint).max);
    }

    modifier onlyGov() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    function afterDeposit(uint256 assets, uint256) internal override {
        savings.stake(assets, address(this));
    }

    function beforeWithdraw(uint256 assets, uint256) internal override {
        require(totalAssets() >= assets + MIN_BALANCE, "Insufficient assets");
        savings.unstake(assets);
    }

    function totalAssets() public view override returns (uint) {
        uint week = block.timestamp / 7 days;
        uint timeElapsed = block.timestamp % 7 days;
        uint remainingLastRevenue = weeklyRevenue[week - 1] * (7 days - timeElapsed) / 7 days;
        return savings.balanceOf(address(this)) - remainingLastRevenue - weeklyRevenue[week];
    }

    function getK() public view returns (uint) {
        uint duration = 7 days;
        uint timeElapsed = block.timestamp - lastKUpdate;
        if(timeElapsed > duration) {
            return targetK;
        } else {
            uint targetWeight = timeElapsed;
            uint prevWeight = duration - timeElapsed;
            return (prevK * prevWeight + targetK * targetWeight) / duration;
        }
    }

    function getDolaReserve() public view returns (uint) {
        return getK() / getDbrReserve();
    }

    function getDolaReserve(uint dbrReserve) public view returns (uint) {
        return getK() / dbrReserve;
    }

    function getDbrReserve() public view returns (uint) {
        return dbr.balanceOf(address(this)) + savings.claimable(address(this));
    }

    function setTargetK(uint _K) external onlyGov {
        require(_K > getDbrReserve(), "K must be larger than dbr reserve");
        prevK = getK();
        targetK = _K;
        lastKUpdate = block.timestamp;
    }

    function buyDBR(uint exactDolaIn, uint exactDbrOut, address to) external {
        savings.claim(address(this));
        uint k = getK();
        uint dbrBalance = dbr.balanceOf(address(this));
        uint dbrReserve = dbrBalance - exactDbrOut;
        uint dolaReserve = k / dbrBalance + exactDolaIn;
        require(dolaReserve * dbrReserve >= k, "Invariant");
        asset.transferFrom(msg.sender, address(this), exactDolaIn);
        savings.stake(exactDolaIn, address(this));
        weeklyRevenue[block.timestamp / 7 days] += exactDolaIn;
        dbr.transfer(to, exactDbrOut);
        emit Buy(msg.sender, to, exactDolaIn, exactDbrOut);
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function reapprove() external {
        asset.approve(address(savings), type(uint).max);
    }

    event Buy(address indexed caller, address indexed to, uint exactDolaIn, uint exactDbrOut);

}
