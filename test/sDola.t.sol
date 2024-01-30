// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {sDola} from "../src/sDola.sol";
import {sDolaHelper} from "src/sDolaHelper.sol";
import {DolaSavings} from "../src/DolaSavings.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract sDolaTest is Test {

    ERC20 dola;
    ERC20 dbr;
    address gov = address(0x1);
    address operator = address(0x2);
    DolaSavings savings;
    sDola sdola;
    sDolaHelper helper;
    uint minShares;
    uint maxAssets;

    function setUp() public {
        dola = new ERC20();
        dbr = new ERC20();
        savings = new DolaSavings(address(dbr), address(dola), gov, operator);
        sdola = new sDola(address(dola), address(savings), gov, operator, 10**18);
        helper = new sDolaHelper(address(sdola));
        minShares = sdola.MIN_SHARES();
        maxAssets = sdola.MAX_ASSETS();
    }

    function test_constructor() public {
        assertEq(sdola.name(), "Super Dola");
        assertEq(sdola.symbol(), "sDOLA");
        assertEq(sdola.decimals(), 18);
        assertEq(sdola.gov(), gov);
        assertEq(sdola.operator(), operator);
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
            vm.expectRevert("ONLY OPERATOR");
            sdola.setTargetK(_K);
            vm.prank(operator);
            sdola.setTargetK(_K);
            assertEq(sdola.targetK(), _K);
            assertEq(sdola.prevK(), prevK);
            assertEq(sdola.lastKUpdate(), block.timestamp);
        } else {
            vm.startPrank(operator);
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

    function test_buyDBR(uint exactDolaIn) public {
        vm.warp(7 days); // for totalAssets()
        dbr.mint(address(sdola), 1e18);
        assertEq(sdola.getDbrReserve(), 1e18, "dbr reserve");
        exactDolaIn = bound(exactDolaIn, 1, maxAssets);
        uint exactDbrOut = helper.getDbrOut(exactDolaIn);
        dola.mint(address(this), exactDolaIn);
        dola.approve(address(sdola), exactDolaIn);
        uint newDbrReserve = sdola.getDbrReserve() - exactDbrOut;
        sdola.buyDBR(exactDolaIn, exactDbrOut, address(1));
        assertEq(dola.balanceOf(address(this)), 0, "dola balance");
        assertEq(savings.balanceOf(address(sdola)), exactDolaIn, "savings balance");
        assertEq(dbr.balanceOf(address(1)), exactDbrOut, "dbr balance");
        assertEq(sdola.getDbrReserve(), newDbrReserve, "dbr reserve");
        assertEq(sdola.getDolaReserve(), sdola.getK() / newDbrReserve, "dola reserve");
        assertEq(sdola.weeklyRevenue(block.timestamp / 7 days), exactDolaIn, "weekly revenue");
        assertEq(sdola.totalAssets(), 0, "total assets");
        vm.warp(14 days);
        assertEq(sdola.totalAssets(), 0, "total assets 14 days");
        vm.warp(14 days + (7 days / 4));
        assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 4, 20, "total assets 16.25 days");
        vm.warp(14 days + (7 days / 2));
        assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 2, 20, "total assets 17.5 days");
        vm.warp(21 days);
        assertEq(sdola.totalAssets(), exactDolaIn, "total assets 21 days");
        vm.warp(21 days + 1);
        assertEq(sdola.totalAssets(), exactDolaIn, "total assets 22 days");
        vm.warp(28 days);
        assertEq(sdola.totalAssets(), exactDolaIn, "total assets 28 days");
    }

    function test_buyDBR(uint exactDolaIn, uint exactDbrOut) public {
        vm.warp(7 days); // for totalAssets()
        dbr.mint(address(sdola), 1e18);
        assertEq(sdola.getDbrReserve(), 1e18, "dbr reserve");
        exactDolaIn = bound(exactDolaIn, 1, maxAssets);
        exactDbrOut = bound(exactDbrOut, 0, 1e18); 
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
            assertEq(sdola.totalAssets(), 0, "total assets 14 days");
            vm.warp(14 days + (7 days / 4));
            if(exactDolaIn > maxAssets) exactDolaIn = maxAssets;
            assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 4, 20, "total assets 16.25 days");
            vm.warp(14 days + (7 days / 2));
            assertApproxEqAbs(sdola.totalAssets(), exactDolaIn / 2, 20, "total assets 17.5 days");
            vm.warp(21 days);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets 21 days");
            vm.warp(21 days + 1);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets 22 days");
            vm.warp(28 days);
            assertEq(sdola.totalAssets(), exactDolaIn, "total assets 28 days");
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
        amount = bound(amount, sdola.convertToAssets(minShares), maxAssets);
        assertEq(sdola.totalAssets(), 0);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.deposit(amount, address(this));
        assertEq(sdola.totalAssets(), amount);
    }

    function test_deposit(uint amount) public {
        vm.warp(7 days); // for totalAssets()
        amount = bound(amount, sdola.convertToAssets(minShares), maxAssets);
        uint shares = sdola.convertToShares(amount);
        dola.mint(address(this), amount);
        dola.approve(address(sdola), amount);
        sdola.deposit(amount, address(this));
        assertEq(sdola.totalAssets(), amount, "Assets not equal amount");
        assertEq(savings.balanceOf(address(sdola)), amount, "sDola savings balance not equal amount");
        assertEq(sdola.balanceOf(address(this)), shares, "Owned balance not equal shares");
        assertEq(dola.balanceOf(address(savings)), amount, "Savings balance not equal amount");
    }

    function test_mint(uint shares) public {
        vm.warp(7 days); // for totalAssets()
        shares = bound(shares, minShares, sdola.convertToShares(maxAssets));
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
        amount = bound(amount, minShares+1, maxAssets);
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
        amount = amount - sdola.convertToAssets(minShares); // min shares
        sdola.withdraw(amount, address(this), address(this));
        uint minBalance = sdola.convertToAssets(minShares);
        assertEq(sdola.totalAssets(), minBalance);
        assertEq(savings.balanceOf(address(sdola)), minBalance);
        assertEq(sdola.balanceOf(address(this)), minBalance);
        assertEq(dola.balanceOf(address(savings)), minBalance);
        assertEq(dola.balanceOf(address(this)), amount);
    }

    function test_redeem(uint shares) public {
        vm.warp(7 days); // for totalAssets()
        shares = bound(shares, minShares+1, sdola.convertToShares(maxAssets));
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
        shares = sdola.convertToShares(amount) - minShares;
        sdola.redeem(shares, address(this), address(this));
        uint minBalance = sdola.convertToAssets(minShares);
        assertEq(sdola.totalAssets(), minBalance);
        assertEq(savings.balanceOf(address(sdola)), minBalance);
        assertEq(sdola.balanceOf(address(this)), minBalance);
        assertEq(dola.balanceOf(address(savings)), minBalance);
        assertEq(dola.balanceOf(address(this)), amount - minBalance);
    }

}
