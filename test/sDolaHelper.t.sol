// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {sDolaMock} from "./mocks/sDolaMock.sol";
import {sDolaHelper} from "../src/sDolaHelper.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract sDolaHelperTest is Test {
    
    ERC20 public dola;
    sDolaMock public sDola;
    sDolaHelper public helper;

    function setUp() public {
        dola = new ERC20();
        sDola = new sDolaMock(address(dola));
        helper = new sDolaHelper(address(sDola));
    }

    function test_constructor() public {
        assertEq(address(helper.sDola()), address(sDola));
        assertEq(address(helper.dola()), address(dola));
        assertEq(dola.allowance(address(helper), address(sDola)), type(uint).max);
    }

    function test_getDbrOut() public {
        uint dbrOut = helper.getDbrOut(1e18);
        assertEq(dbrOut, 5e17);
    }

    function test_getDolaIn() public {
        uint dolaIn = helper.getDolaIn(5e17);
        assertEq(dolaIn, 1e18+1);
    }

    function test_swapExactDolaForDbr() public {
        dola.mint(address(this), 1e18);
        dola.approve(address(helper), 1e18);
        helper.swapExactDolaForDbr(1e18, 5e17);
        assertEq(dola.balanceOf(address(this)), 0);
        assertEq(dola.balanceOf(address(helper)), 1e18);
        assertEq(sDola.exactDolaIn(), 1e18);
        assertEq(sDola.exactDbrOut(), 5e17);
        assertEq(sDola.to(), address(this));
    }

    function test_swapDolaForExactDbr() public {
        dola.mint(address(this), 1e18+1);
        dola.approve(address(helper), 1e18+1);
        helper.swapDolaForExactDbr(5e17, 1e18+1);
        assertEq(dola.balanceOf(address(this)), 0);
        assertEq(dola.balanceOf(address(helper)), 1e18+1);
        assertEq(sDola.exactDolaIn(), 1e18+1);
        assertEq(sDola.exactDbrOut(), 5e17);
        assertEq(sDola.to(), address(this));
    }
}