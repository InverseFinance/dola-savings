// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

contract sDolaMock {

    uint public getDbrReserve = 1e18;
    uint public exactDolaIn;
    uint public exactDbrOut;
    address public to;
    address public asset;

    constructor(address _asset) {
        asset = _asset;
    }
    function getDolaReserve() public returns(uint){
        return 1e18;
    }

    function getDolaReserve(uint unused) external returns(uint){
        return getDolaReserve();
    }

    function buyDBR(uint _exactDolaIn, uint _exactDbrOut, address _to) external {
        exactDolaIn = _exactDolaIn;
        exactDbrOut = _exactDbrOut;
        to = _to;
    }
}
