// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "../../../interface/mooniswap/IMooniswap.sol";
import "../../../interface/mooniswap/IMooniFactory.sol";
import "../interface/ILiquidityDex.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


contract UniBasedDex is ILiquidityDex {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  receive() external payable {}

  address private mooniFactory;

  constructor(address routerAddress, address factoryAddress) public {
    mooniFactory = factoryAddress;
  }

  function doSwap(
    uint256 amountIn,
    uint256 minAmountOut,
    address spender,
    address target,
    address[] memory path
  ) public override {
    uint256 i;
    IERC20(path[0]).safeTransferFrom(spender, address(this), amountIn);
    uint256 initialAmount = IERC20(path[path.length-1]).balanceOf(address(this));
    for (i=0; i<path.length-1; i++) {
      address buyToken = path[i+1];
      address sellToken = path[i];
      amountIn = IERC20(sellToken).balanceOf(address(this));

      address pairAddress = IMooniFactory(mooniFactory).pools(buyToken, sellToken);
      IERC20(sellToken).safeIncreaseAllowance(pairAddress, amountIn);

      // Fill 1 for minReturn, check return at the end
      IMooniswap(pairAddress).swap(sellToken, buyToken, amountIn, 1, address(0));
    }
    uint256 amountOut = IERC20(path[path.length-1]).balanceOf(address(this)).sub(initialAmount);
    require(amountOut >= minAmountOut, "Ouput too low");
    IERC20(path[path.length-1]).safeTransfer(target, amountOut);
  }
}
