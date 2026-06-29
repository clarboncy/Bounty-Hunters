// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/LiquidityPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory name, string memory sym, uint256 supply) ERC20(name, sym) {
        _mint(msg.sender, supply);
    }
}

contract LiquidityPoolTest is Test {
    LiquidityPool public pool;
    TestToken public tokenA;
    TestToken public tokenB;
    address public alice;
    address public bob;

    function setUp() public {
        tokenA = new TestToken("TokenA", "TKA", 1_000_000 ether);
        tokenB = new TestToken("TokenB", "TKB", 1_000_000 ether);
        pool = new LiquidityPool(address(tokenA), address(tokenB));

        alice = makeAddr("alice");
        bob = makeAddr("bob");

        tokenA.transfer(alice, 100_000 ether);
        tokenB.transfer(alice, 100_000 ether);
        tokenA.transfer(bob, 100_000 ether);
        tokenB.transfer(bob, 100_000 ether);

        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.approve(address(pool), type(uint256).max);
        tokenB.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_FirstDepositLocksMinimumLiquidity() public {
        vm.prank(alice);
        uint256 lp = pool.addLiquidity(10_000 ether, 10_000 ether);
        assertEq(lp, 10_000 ether - 1000);
        assertEq(pool.balanceOf(alice), 10_000 ether - 1000);
        assertEq(pool.balanceOf(address(0)), 1000);
        assertEq(pool.totalSupply(), 10_000 ether);
    }

    function test_Revert_FirstDepositTooSmall() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient first liquidity");
        pool.addLiquidity(1, 1);
    }

    function test_SecondDepositProportional() public {
        vm.prank(alice);
        pool.addLiquidity(10_000 ether, 10_000 ether);

        vm.prank(bob);
        uint256 lp = pool.addLiquidity(5_000 ether, 5_000 ether);
        assertEq(lp, 5_000 ether);
    }

    function test_RemoveLiquidityUsesReserves() public {
        vm.prank(alice);
        uint256 lp = pool.addLiquidity(10_000 ether, 10_000 ether);

        tokenA.transfer(address(pool), 1_000 ether);
        tokenB.transfer(address(pool), 1_000 ether);

        vm.prank(alice);
        (uint256 amountA, uint256 amountB) = pool.removeLiquidity(lp);
        assertEq(amountA, 10_000 ether - 1000);
        assertEq(amountB, 10_000 ether - 1000);
    }

    function test_SyncUpdatesReserves() public {
        vm.prank(alice);
        pool.addLiquidity(10_000 ether, 10_000 ether);

        tokenA.transfer(address(pool), 500 ether);
        tokenB.transfer(address(pool), 500 ether);

        assertEq(pool.reserveA(), 10_000 ether);
        assertEq(pool.reserveB(), 10_000 ether);

        pool.sync();

        assertEq(pool.reserveA(), 10_500 ether);
        assertEq(pool.reserveB(), 10_500 ether);
    }

    function test_Revert_RemoveZeroLiquidity() public {
        vm.prank(alice);
        vm.expectRevert("Must burn > 0");
        pool.removeLiquidity(0);
    }

    function test_Revert_InsufficientLP() public {
        vm.prank(alice);
        vm.expectRevert("Insufficient LP tokens");
        pool.removeLiquidity(1);
    }

    function test_FirstDepositorCantManipulatePrice() public {
        vm.prank(alice);
        uint256 lp = pool.addLiquidity(1000 ether, 1000 ether);
        assertEq(lp, 1000 ether - 1000);

        tokenA.transfer(address(pool), 99_000 ether);
        tokenB.transfer(address(pool), 99_000 ether);

        vm.prank(bob);
        uint256 bobLp = pool.addLiquidity(100_000 ether, 100_000 ether);
        assertEq(bobLp, 100_000 ether);

        uint256 attackerShare = pool.balanceOf(alice) * 1e18 / pool.totalSupply();
        assertLt(attackerShare, 0.01e18);
    }

    function test_RemoveLiquidityFullWithdraw() public {
        vm.prank(alice);
        uint256 lp = pool.addLiquidity(10_000 ether, 10_000 ether);

        uint256 aliceBalBefore = tokenA.balanceOf(alice);

        vm.prank(alice);
        pool.removeLiquidity(lp);

        uint256 returned = tokenA.balanceOf(alice) - aliceBalBefore;
        assertEq(returned, 10_000 ether - 1000);
    }
}
