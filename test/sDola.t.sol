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
        sdola.setGov(address(0x3));
        vm.prank(gov);
        sdola.setGov(address(0x3));
        assertEq(sdola.gov(), address(0x3));
    }

    function test_reapprove() public {
        vm.prank(address(sdola));
        dola.approve(address(savings), 0);
        assertEq(dola.allowance(address(sdola), address(savings)), 0);
        sdola.reapprove();
        assertEq(dola.allowance(address(sdola), address(savings)), type(uint).max);
    }

    function test_buyDBR(uint exactDolaIn, uint exactDbrOut) public {
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
        }
    }

}