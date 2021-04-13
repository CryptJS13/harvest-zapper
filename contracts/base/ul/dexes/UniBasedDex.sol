// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "../../../interface/uniswap/IUniswapV2Pair.sol";
import "../../../interface/uniswap/IUniswapV2Factory.sol";
import "../../../interface/uniswap/IUniswapV2Router02.sol";
import "../interface/ILiquidityDex.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


contract UniBasedDex is ILiquidityDex {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  receive() external payable {}

  address private uniswapRouter;
  address private uniswapFactory;

  constructor(address routerAddress, address factoryAddress) public {
    uniswapRouter = routerAddress;
    uniswapFactory = factoryAddress;
  }

  function doSwap(
    uint256 amountIn,
    uint256 minAmountOut,
    address spender,
    address target,
    address[] memory path
  ) public override {
    address buyToken = path[path.length-1];
    address sellToken = path[0];

    require(buyToken == path[path.length-1], "The last token on the path should be the buytoken");
    IERC20(sellToken).safeTransferFrom(spender, address(this), amountIn);
    IERC20(sellToken).safeIncreaseAllowance(uniswapRouter, amountIn);

    IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(amountIn, minAmountOut, path, target, block.timestamp);
  }
}
