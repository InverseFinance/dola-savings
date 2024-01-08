// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IsDola {
    function asset() external view returns (address);
    function getDolaReserve() external view returns (uint);
    function getDolaReserve(uint dbrReserve) external view returns (uint);
    function getDbrReserve() external view returns (uint);
    function buyDBR(uint exactDolaIn, uint exactDbrOut, address to) external;
}

interface IERC20 {
    function approve(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
}

contract sDolaHelper {

    IsDola public immutable sDola;
    IERC20 public immutable dola;

    constructor(
        address _sDola
    ) {
        sDola = IsDola(_sDola);
        dola = IERC20(sDola.asset());
        dola.approve(_sDola, type(uint).max);
    }
    
    function getDbrOut(uint dolaIn) public view returns (uint dbrOut) {
        require(dolaIn > 0, "dolaIn must be positive");
        uint dbrReserve = sDola.getDbrReserve();
        uint dolaReserve = sDola.getDolaReserve(dbrReserve);
        uint numerator = dolaIn * dbrReserve;
        uint denominator = dolaReserve + dolaIn;
        dbrOut = numerator / denominator;
    }

    function getDolaIn(uint dbrOut) public view returns (uint dolaIn) {
        require(dbrOut > 0, "dbrOut must be positive");
        uint dbrReserve = sDola.getDbrReserve();
        uint dolaReserve = sDola.getDolaReserve(dbrReserve);
        uint numerator = dbrOut * dolaReserve;
        uint denominator = dbrReserve - dbrOut;
        dolaIn = (numerator / denominator) + 1;
    }

    function swapExactDolaForDbr(uint dolaIn, uint dbrOutMin) external returns (uint dbrOut) {
        dbrOut = getDbrOut(dolaIn);
        require(dbrOut >= dbrOutMin, "dbrOut must be greater than dbrOutMin");
        dola.transferFrom(msg.sender, address(this), dolaIn);
        sDola.buyDBR(dolaIn, dbrOut, msg.sender);
    }

    function swapDolaForExactDbr(uint dbrOut, uint dolaInMax) external returns (uint dolaIn) {
        dolaIn = getDolaIn(dbrOut);
        require(dolaIn <= dolaInMax, "dolaIn must be less than dolaInMax");
        dola.transferFrom(msg.sender, address(this), dolaIn);
        sDola.buyDBR(dolaIn, dbrOut, msg.sender);
    }

}
