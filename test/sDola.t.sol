// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {sDola} from "../src/sDola.sol";
import {DolaSavings} from "../src/DolaSavings.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract sDolaTest is Test {

    ERC20 dola;
    ERC20 dbr;
    address gov = address(0x1);
    address operator = address(0x2);
    DolaSavings savings;
    sDola sdola;

    function setUp() public {
        dola = new ERC20();
        dbr = new ERC20();
        savings = new DolaSavings(address(dbr), address(dola), gov, operator);
        sdola = new sDola(address(dola), address(savings), gov, 10**18);
    }

    function test_constructor() public {
        assertEq(sdola.name(), "Super Dola");
        assertEq(sdola.symbol(), "sDOLA");
        assertEq(sdola.decimals(), 18);
        assertEq(sdola.gov(), gov);
        assertEq(address(sdola.savings()), address(savings));
        assertEq(address(sdola.asset()), address(dola));
        assertEq(address(sdola.dbr()), address(dbr));
        assertEq(sdola.prevK(), 0);
        assertEq(sdola.targetK(), 10**18);
        // warp for getK()
        vm.warp(7 days);
        assertEq(sdola.getK(), 10**18);
        assertEq(sdola.lastKUpdate(), 0);
        assertEq(dola.allowance(address(sdola), address(savings)), type(uint).max);
    }

    function test_setTargetK(uint _K) public {
        if(_K > sdola.getDbrReserve()) {
            uint prevK = sdola.getK();
            vm.expectRevert("ONLY GOV");
            sdola.setTargetK(_K);
            vm.prank(gov);
            sdola.setTargetK(_K);
            assertEq(sdola.targetK(), _K);
            assertEq(sdola.prevK(), prevK);
            assertEq(sdola.lastKUpdate(), block.timestamp);
        } else {
            vm.startPrank(gov);
            vm.expectRevert("K must be larger than dbr reserve");
            sdola.setTargetK(_K);
        }
    }

    function test_setGov() public {
        vm.expectRevert("ONLY GOV");
        sdola.setPendingGov(address(0x3));
        vm.prank(gov);
        sdola.setPendingGov(address(0x3));
        assertEq(sdola.pendingGov(), address(0x3));
        vm.expectRevert("ONLY PENDINGGOV");
        sdola.acceptGov();
        vm.prank(address(0x3));
        sdola.acceptGov();
        assertEq(sdola.gov(), address(0x3));
        assertEq(sdola.pendingGov(), address(0));
    }

    function test_reapprove() public {
        vm.prank(address(sdola));
        dola.approve(address(savings), 0);
        assertEq(dola.allowance(address(sdola), address(savings)), 0);
        sdola.reapprove();
        assertEq(dola.allowance(address(sdola), address(savings)), type(uint).max);
    }

    function test_buyDBR(uint exactDolaIn, uint exactDbrOut) public {
        vm.warp(7 days); // for totalAssets()
        dbr.mint(address(sdola), 1e18);
        assertEq(sdola.getDbrReserve(), 1e18, "dbr reserve");
        exactDbrOut = bound(exactDbrOut, 1, sdola.getDbrReserve());
        exactDolaIn = bound(exactDolaIn, 0, (type(uint).max - sdola.getDolaReserve()) / sdola.getDbrReserve() - exactDbrOut);
        dola.mint(address(this), exactDolaIn);
        dola.approve(address(sdola), exactDolaIn);
        uint K = sdola.getK();
        uint newDbrReserve = sdola.getDbrReserve() - exactDbrOut;
        uint newDolaReserve = sdola.getDolaReserve() + exactDolaIn;
        uint newK = newDolaReserve * newDbrReserve;
        if(newK < K) {
            vm.expectRevert("Invariant");
            sdola.buyDBR(exactDolaIn, exactDbrOut, address(1));
        } else {
            sdola.buyDBR(exactDolaIn, exactDbrOut, address(1));
            assertEq(dola.balanceOf(address(this)), 0, "dola balance");
            assertEq(savings.balanceOf(address(sdola)), exactDolaIn, "savings balance");
            assertEq(dbr.balanceOf(address(1)), exactDbrOut, "dbr balance");
            assertEq(sdola.getDbrReserve(), newDbrReserve, "dbr reserve");
            assertEq(sdola.getDolaReserve(), sdola.getK() / newDbrReserve, "dola reserve");
            assertEq(sdola.weeklyRevenue(block.timestamp / 7 days), exactDolaIn, "weekly revenue");
            assertEq(sdola.totalAssets(), 0, "total assets");
            vm.warp(14 days);
            assertEq(sdola.totalAssets(), 0, "total assets");
            vm.warp(14 days + (7 days / 4));
            assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 4, 1, "total assets");
            vm.warp(14 days + (7 days / 2));
            assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 2, 1, "total assets");
            vm.warp(21 days);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets");
            vm.warp(21 days + 1);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets");
            vm.warp(28 days);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets");
        }
    }

    function test_getDbrReserve() public {
        vm.warp(7 days);
        assertEq(sdola.getDbrReserve(), 0);
        dbr.mint(address(sdola), 1e18);
        assertEq(sdola.getDbrReserve(), 1e18);
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(1e18);
        vm.prank(operator);
        savings.setYearlyRewardBudget(1e18);
        dola.mint(address(this), 1e18);
        dola.approve(address(sdola), 1e18);
        sdola.deposit(1e18, address(this));
        vm.warp(365 days + 7 days);
        assertEq(sdola.getDbrReserve(), 2 * 1e18);
    }

    function test_getDolaReserve(uint dbrReserve) public {
        dbrReserve = bound(dbrReserve, 1, type(uint).max);
        vm.warp(7 days);
        dbr.mint(address(sdola), dbrReserve);
        assertEq(sdola.getDbrReserve(), dbrReserve);
        assertEq(sdola.getDolaReserve(), sdola.getK() / dbrReserve);
    }

    function test_getK() public {
        vm.warp(7 days);
        assertEq(sdola.getK(), 1e18);
        vm.prank(gov);
        sdola.setTargetK(3 * 1e18);
        assertEq(sdola.getK(), 1e18);
        vm.warp(10.5 days);
        assertEq(sdola.getK(), 2 * 1e18);
        vm.warp(14 days);
        assertEq(sdola.getK(), 3 * 1e18);
        vm.warp(21 days);
        assertEq(sdola.getK(), 3 * 1e18);
    }

    function test_totalAssets(uint amount) public {
        vm.warp(7 days); // for totalAssets()
        amount = bound(amount, 1, type(uint).max);
        assertEq(sdola.totalAssets(), 0);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.deposit(amount, address(this));
        assertEq(sdola.totalAssets(), amount);
    }

    function test_deposit(uint amount) public {
        vm.warp(7 days); // for totalAssets()
        amount = bound(amount, 1, type(uint).max);
        uint shares = sdola.convertToShares(amount);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.deposit(amount, address(this));
        assertEq(sdola.totalAssets(), amount);
        assertEq(savings.balanceOf(address(sdola)), amount);
        assertEq(sdola.balanceOf(address(this)), shares);
        assertEq(dola.balanceOf(address(savings)), amount);
    }

    function test_mint(uint shares) public {
        vm.warp(7 days); // for totalAssets()
        shares = bound(shares, 1, type(uint).max);
        uint amount = sdola.convertToAssets(shares);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.mint(shares, address(this));
        assertEq(sdola.totalAssets(), amount);
        assertEq(savings.balanceOf(address(sdola)), amount);
        assertEq(sdola.balanceOf(address(this)), shares);
        assertEq(dola.balanceOf(address(savings)), amount);
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function test_withdraw(uint amount) public {
        vm.warp(7 days); // for totalAssets()
        uint MIN_BALANCE = 1e16; // 1 cent
        amount = bound(amount, MIN_BALANCE + 1, sqrt(type(uint).max));
        uint shares = sdola.convertToShares(amount);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.deposit(amount, address(this));
        assertEq(sdola.totalAssets(), amount);
        assertEq(savings.balanceOf(address(sdola)), amount);
        assertEq(sdola.balanceOf(address(this)), shares);
        assertEq(dola.balanceOf(address(savings)), amount);
        vm.expectRevert("Insufficient assets");
        sdola.withdraw(amount, address(this), address(this));
        amount = amount - MIN_BALANCE; // min balance
        sdola.withdraw(amount, address(this), address(this));
        assertEq(sdola.totalAssets(), MIN_BALANCE);
        assertEq(savings.balanceOf(address(sdola)), MIN_BALANCE);
        assertEq(sdola.balanceOf(address(this)), MIN_BALANCE);
        assertEq(dola.balanceOf(address(savings)), MIN_BALANCE);
        assertEq(dola.balanceOf(address(this)), amount);
    }

    function test_redeem(uint shares) public {
        vm.warp(7 days); // for totalAssets()
        uint MIN_BALANCE = 1e16; // 1 cent
        shares = bound(shares, MIN_BALANCE + 1, sdola.convertToShares(sqrt(type(uint).max)));
        uint amount = sdola.convertToAssets(shares);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.mint(shares, address(this));
        assertEq(sdola.totalAssets(), amount);
        assertEq(savings.balanceOf(address(sdola)), amount);
        assertEq(sdola.balanceOf(address(this)), shares);
        assertEq(dola.balanceOf(address(savings)), amount);
        vm.expectRevert("Insufficient assets");
        sdola.redeem(shares, address(this), address(this));
        amount = amount - MIN_BALANCE; // min balance
        shares = sdola.convertToShares(amount);
        sdola.redeem(shares, address(this), address(this));
        assertEq(sdola.totalAssets(), MIN_BALANCE);
        assertEq(savings.balanceOf(address(sdola)), MIN_BALANCE);
        assertEq(sdola.balanceOf(address(this)), MIN_BALANCE);
        assertEq(dola.balanceOf(address(savings)), MIN_BALANCE);
        assertEq(dola.balanceOf(address(this)), amount);
    }

}
