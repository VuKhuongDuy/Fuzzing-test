// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/**
y = Token Balance Y
x = Token Balance X
x * y = k
x * y = (x + ∆x) * (y − ∆y)
∆x = Change of token balance X
∆y = Change of token balance Y
β = (∆y / y)
α = (∆x / x)

Final invariant equation without fees:
∆x = (β/(1-β)) * x
∆y = (α/(1+α)) * y

Invariant with fees
ρ = fee (between 0 & 1, aka a percentage)
γ = (1 - p) (pronounced gamma)
∆x = (β/(1-β)) * (1/γ) * x
∆y = (αγ/1+αγ) * y
*/

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("lp");
    address user = makeAddr("user");

    int256 startingY;
    int256 startingX;
    int256 public expectedDeltaX;
    int256 public expectedDeltaY;
    int256 public actualDeltaX;
    int256 public actualDeltaY;

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(_pool.getWeth());
        poolToken = ERC20Mock(_pool.getPoolToken());
    }

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWeth) public {
        if (weth.balanceOf(address(pool)) <= pool.getMinimumWethDepositAmount()) {
            return;
        }
        outputWeth = bound(outputWeth, pool.getMinimumWethDepositAmount(), weth.balanceOf(address(pool)));
        if (outputWeth == weth.balanceOf(address(pool))) {
            return;
        }

        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth,
            poolToken.balanceOf(address(pool)),
            weth.balanceOf(address(pool))
        );

        if (poolTokenAmount > type(uint64).max) {
            return;
        }

        _updateStartingDeltas(int256(outputWeth) * -1, int256(poolTokenAmount));

        if (poolToken.balanceOf(user) < poolTokenAmount) {
            poolToken.mint(
                user,
                poolTokenAmount - poolToken.balanceOf(user) + 1
            );
        }

        vm.startPrank(user);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(
            poolToken,
            weth,
			outputWeth,
            uint64(block.timestamp)
        );
		vm.stopPrank();

		_updateEndingDeltas();
    }

    function deposit(uint256 wethAmount) public {
        wethAmount = bound(wethAmount, pool.getMinimumWethDepositAmount(), type(uint64).max);

        uint256 amountPoolTokensToDepositBasedOnWeth = pool.getPoolTokensToDepositBasedOnWeth(wethAmount);
        _updateStartingDeltas(int256(wethAmount), int256(amountPoolTokensToDepositBasedOnWeth));

        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, wethAmount);
        poolToken.mint(liquidityProvider, uint256(amountPoolTokensToDepositBasedOnWeth));
        weth.approve(address(pool), wethAmount);
        poolToken.approve(address(pool), uint256(amountPoolTokensToDepositBasedOnWeth));
        pool.deposit(
            wethAmount,
            0,
            uint256(amountPoolTokensToDepositBasedOnWeth),
            uint64(block.timestamp)
        );
        vm.stopPrank();

        _updateEndingDeltas();
    }

    function _updateStartingDeltas(int256 wethAmount, int256 poolTokenAmount) internal {
        startingY = int256(poolToken.balanceOf(address(pool)));
        startingX = int256(weth.balanceOf(address(pool)));

        expectedDeltaX = wethAmount;
        expectedDeltaY = poolTokenAmount;
    }

    function _updateEndingDeltas() internal {
        uint256 endingPoolTokenBalance = poolToken.balanceOf(address(pool));
        uint256 endingWethBalance = weth.balanceOf(address(pool));

        // sell tokens == x == poolTokens
        int256 actualDeltaPoolToken = int256(endingPoolTokenBalance) - int256(startingY);
        int256 deltaWeth = int256(endingWethBalance) - int256(startingX);

        actualDeltaX = deltaWeth;
        actualDeltaY = actualDeltaPoolToken;
    }
}
