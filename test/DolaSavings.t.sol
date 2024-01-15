// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {DolaSavings} from "../src/DolaSavings.sol";
import {ERC20} from "./mocks/ERC20.sol";

contract DolaSavingsTest is Test {

    ERC20 public dbr;
    ERC20 public dola;
    address gov = address(0x1);
    address operator = address(0x2);
    DolaSavings public savings;

    function setUp() public {
        dbr = new ERC20();
        dola = new ERC20();
        savings = new DolaSavings(address(dbr), address(dola), gov, operator);
    }

    function test_constructor() public {
        vm.warp(1);
        assertEq(address(savings.dbr()), address(dbr));
        assertEq(address(savings.dola()), address(dola));
        assertEq(savings.gov(), gov);
        assertEq(savings.operator(), operator);
        assertEq(savings.maxYearlyRewardBudget(), 0);
        assertEq(savings.maxRewardPerDolaMantissa(), 10**18);
        assertEq(savings.yearlyRewardBudget(), 0);
        assertEq(savings.lastUpdate(), 1);
        assertEq(savings.rewardIndexMantissa(), 0);
        assertEq(savings.totalSupply(), 0);
    }

    function test_setOperator() public {
        vm.expectRevert("ONLY GOV");
        savings.setOperator(address(0x3));
        vm.prank(gov);
        savings.setOperator(address(0x3));
        assertEq(savings.operator(), address(0x3));
    }

    function test_setGov() public {
        vm.expectRevert("ONLY GOV");
        savings.setPendingGov(address(0x3));
        vm.prank(gov);
        savings.setPendingGov(address(0x3));
        assertEq(savings.pendingGov(), address(0x3));
        vm.expectRevert("Only pendingGov");
        savings.acceptGov();
        vm.prank(address(0x3));
        savings.acceptGov();
        assertEq(savings.gov(), address(0x3));
        assertEq(savings.pendingGov(), address(0));
    }

    function test_setMaxYearlyRewardBudget() public {
        vm.expectRevert("ONLY GOV");
        savings.setMaxYearlyRewardBudget(100);
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(100);
        assertEq(savings.maxYearlyRewardBudget(), 100);
        vm.prank(operator);
        savings.setYearlyRewardBudget(100);
        assertEq(savings.yearlyRewardBudget(), 100);
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(50);
        assertEq(savings.maxYearlyRewardBudget(), 50);
        assertEq(savings.yearlyRewardBudget(), 50);
    }

    function test_setYearlyRewardBudget() public {
        vm.expectRevert("ONLY OPERATOR");
        savings.setYearlyRewardBudget(100);
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(100);
        vm.prank(operator);
        savings.setYearlyRewardBudget(100);
        assertEq(savings.yearlyRewardBudget(), 100);
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(50);
        assertEq(savings.maxYearlyRewardBudget(), 50);
        assertEq(savings.yearlyRewardBudget(), 50);
        vm.startPrank(operator);
        vm.expectRevert("REWARD BUDGET ABOVE MAX");
        savings.setYearlyRewardBudget(100);
        savings.setYearlyRewardBudget(10);
        assertEq(savings.yearlyRewardBudget(), 10);
    }

    function test_stake_unstake(uint amount) public {
        dola.mint(address(this), amount);
        dola.approve(address(savings), amount);
        savings.stake(amount, address(0x1));
        assertEq(savings.balanceOf(address(0x1)), amount);
        assertEq(savings.totalSupply(), amount);
        assertEq(dola.balanceOf(address(savings)), amount);
        vm.prank(address(0x1));
        savings.unstake(amount);
        assertEq(savings.balanceOf(address(0x1)), 0);
        assertEq(savings.totalSupply(), 0);
        assertEq(dola.balanceOf(address(savings)), 0);
        assertEq(dola.balanceOf(address(0x1)), amount);
    }

    function test_claimable() public {
        vm.prank(gov);
        savings.setMaxYearlyRewardBudget(1e18);
        vm.prank(operator);
        savings.setYearlyRewardBudget(1e18);
        dola.mint(address(this), 1e18);
        dola.approve(address(savings), 1e18);
        savings.stake(1e18, address(this));
        vm.warp(365 days + 1);
        assertEq(savings.claimable(address(this)), 1e18);
        savings.claim(address(0x1));
        assertEq(dbr.balanceOf(address(0x1)), 1e18);
        assertEq(savings.claimable(address(this)), 0);
        vm.prank(gov);
        savings.setMaxRewardPerDolaMantissa(1e17);
        vm.warp(2 * 365 days + 1);
        assertEq(savings.claimable(address(this)), 1e17);
        savings.claim(address(0x2));
        assertEq(dbr.balanceOf(address(0x2)), 1e17);
        assertEq(savings.claimable(address(this)), 0);
    }

    function test_sweep() public {
        vm.expectRevert("ONLY GOV");
        savings.sweep(address(0x1), 100, address(0x2));
        vm.startPrank(gov);
        ERC20 stuckToken = new ERC20();
        stuckToken.mint(address(savings), 100);
        savings.sweep(address(stuckToken), 100, address(0x1));
        assertEq(stuckToken.balanceOf(address(0x1)), 100);
        vm.stopPrank();
        dola.mint(address(this), 100);
        dola.mint(address(savings), 100);
        dola.approve(address(savings), 100);
        savings.stake(100, address(0x1));
        vm.startPrank(gov);
        vm.expectRevert("CANNOT SWEEP USER DOLA");
        savings.sweep(address(dola), 200, address(0x2));
        savings.sweep(address(dola), 100, address(0x2));
        assertEq(dola.balanceOf(address(0x2)), 100);
        assertEq(dola.balanceOf(address(savings)), 100);                
    }

}
