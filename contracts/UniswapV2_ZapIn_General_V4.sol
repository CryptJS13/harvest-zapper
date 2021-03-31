/**
 *Submitted for verification at Etherscan.io on 2021-02-16
*/

// ███████╗░█████╗░██████╗░██████╗░███████╗██████╗░░░░███████╗██╗
// ╚════██║██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔══██╗░░░██╔════╝██║
// ░░███╔═╝███████║██████╔╝██████╔╝█████╗░░██████╔╝░░░█████╗░░██║
// ██╔══╝░░██╔══██║██╔═══╝░██╔═══╝░██╔══╝░░██╔══██╗░░░██╔══╝░░██║
// ███████╗██║░░██║██║░░░░░██║░░░░░███████╗██║░░██║██╗██║░░░░░██║
// ╚══════╝╚═╝░░╚═╝╚═╝░░░░░╚═╝░░░░░╚══════╝╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝
// Copyright (C) 2020 zapper

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//

///@author Zapper
///@notice This contract adds liquidity to Uniswap V2 pools using ETH or any ERC20 Token.
// SPDX-License-Identifier: GPLv2

pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interface/IWETH.sol";
import "./interface/uniswap/IUniswapV2Pair.sol";
import "./interface/uniswap/IUniswapV2Factory.sol";
import "./interface/uniswap/IUniswapV2Router02.sol";
import "./libraries/Babylonian.sol";

contract UniswapV2_ZapIn_General_V4 is ReentrancyGuard, Ownable {
  using SafeMath for uint256;
  using Address for address;
  using SafeERC20 for IERC20;

  bool public stopped = false;
  uint16 public goodwill;

  // if true, goodwill is not deducted
  mapping(address => bool) public feeWhitelist;

  // % share of goodwill (0-100 %)
  uint16 affiliateSplit;
  // restrict affiliates
  mapping(address => bool) public affiliates;
  // affiliate => token => amount
  mapping(address => mapping(address => uint256)) public affiliateBalance;
  // token => amount
  mapping(address => uint256) public totalAffiliateBalance;

  address
      private constant ETHAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  IUniswapV2Factory
      private constant UniSwapV2FactoryAddress = IUniswapV2Factory(
      0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f
  );

  IUniswapV2Router02 private constant uniswapRouter = IUniswapV2Router02(
      0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  );

  address
      private constant wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  uint256
      private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;

  constructor(uint16 _goodwill, uint16 _affiliateSplit) public {
      goodwill = _goodwill;
      affiliateSplit = _affiliateSplit;
  }

  // circuit breaker modifiers
  modifier stopInEmergency {
      if (stopped) {
          revert("Temporarily Paused");
      } else {
          _;
      }
  }

  event zapIn(address sender, address pool, uint256 tokensRec);

  /**
  @notice This function is used to invest in given Uniswap V2 pair through ETH/ERC20 Tokens
  @param _FromTokenContractAddress The ERC20 token used for investment (address(0x00) if ether)
  @param _pairAddress The Uniswap pair address
  @param _amount The amount of fromToken to invest
  @param _minPoolTokens Reverts if less tokens received than this
  @param _swapTarget Excecution target for the first swap
  @param swapData DEX quote data
  @param affiliate Affiliate address
  @param transferResidual Set false to save gas by donating the residual remaining after a Zap
  @return Amount of LP bought
   */
  function ZapIn(
      address _FromTokenContractAddress,
      address _pairAddress,
      uint256 _amount,
      uint256 _minPoolTokens,
      address _swapTarget,
      bytes calldata swapData,
      address affiliate,
      bool transferResidual
  ) external payable nonReentrant stopInEmergency returns (uint256) {
      uint256 toInvest = _pullTokens(
          _FromTokenContractAddress,
          _amount,
          affiliate
      );

      uint256 LPBought = _performZapIn(
          _FromTokenContractAddress,
          _pairAddress,
          toInvest,
          _swapTarget,
          swapData,
          transferResidual
      );
      require(LPBought >= _minPoolTokens, "ERR: High Slippage");

      emit zapIn(msg.sender, _pairAddress, LPBought);

      IERC20(_pairAddress).safeTransfer(msg.sender, LPBought);
      return LPBought;
  }

  function _getPairTokens(address _pairAddress)
      internal
      view
      returns (address token0, address token1)
  {
      IUniswapV2Pair uniPair = IUniswapV2Pair(_pairAddress);
      token0 = uniPair.token0();
      token1 = uniPair.token1();
  }

  function _pullTokens(
      address token,
      uint256 amount,
      address affiliate
  ) internal returns (uint256 value) {
      uint256 totalGoodwillPortion;

      if (token == address(0)) {
          require(msg.value > 0, "No eth sent");

          // subtract goodwill
          totalGoodwillPortion = _subtractGoodwill(
              ETHAddress,
              msg.value,
              affiliate
          );

          return msg.value.sub(totalGoodwillPortion);
      }
      require(amount > 0, "Invalid token amount");
      require(msg.value == 0, "Eth sent with token");

      //transfer token
      IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

      // subtract goodwill
      totalGoodwillPortion = _subtractGoodwill(token, amount, affiliate);

      return amount.sub(totalGoodwillPortion);
  }

  function _subtractGoodwill(
      address token,
      uint256 amount,
      address affiliate
  ) internal returns (uint256 totalGoodwillPortion) {
      bool whitelisted = feeWhitelist[msg.sender];
      if (!whitelisted && goodwill > 0) {
          totalGoodwillPortion = SafeMath.div(
              SafeMath.mul(amount, goodwill),
              10000
          );

          if (affiliates[affiliate] && affiliateSplit > 0) {
              uint256 affiliatePortion = totalGoodwillPortion
                  .mul(affiliateSplit)
                  .div(100);
              affiliateBalance[affiliate][token] = affiliateBalance[affiliate][token]
                  .add(affiliatePortion);
              totalAffiliateBalance[token] = totalAffiliateBalance[token].add(
                  affiliatePortion
              );
          }
      }
  }

  function _performZapIn(
      address _FromTokenContractAddress,
      address _pairAddress,
      uint256 _amount,
      address _swapTarget,
      bytes memory swapData,
      bool transferResidual
  ) internal returns (uint256) {
      uint256 intermediateAmt;
      address intermediateToken;
      (address _ToUniswapToken0, address _ToUniswapToken1) = _getPairTokens(
          _pairAddress
      );

      if (
          _FromTokenContractAddress != _ToUniswapToken0 &&
          _FromTokenContractAddress != _ToUniswapToken1
      ) {
          // swap to intermediate
          (intermediateAmt, intermediateToken) = _fillQuote(
              _FromTokenContractAddress,
              _pairAddress,
              _amount,
              _swapTarget,
              swapData
          );
      } else {
          intermediateToken = _FromTokenContractAddress;
          intermediateAmt = _amount;
      }
      // divide intermediate into appropriate amount to add liquidity
      (uint256 token0Bought, uint256 token1Bought) = _swapIntermediate(
          intermediateToken,
          _ToUniswapToken0,
          _ToUniswapToken1,
          intermediateAmt
      );

      return
          _uniDeposit(
              _ToUniswapToken0,
              _ToUniswapToken1,
              token0Bought,
              token1Bought,
              transferResidual
          );
  }

  function _uniDeposit(
      address _ToUnipoolToken0,
      address _ToUnipoolToken1,
      uint256 token0Bought,
      uint256 token1Bought,
      bool transferResidual
  ) internal returns (uint256) {
      IERC20(_ToUnipoolToken0).safeApprove(address(uniswapRouter), 0);
      IERC20(_ToUnipoolToken1).safeApprove(address(uniswapRouter), 0);

      IERC20(_ToUnipoolToken0).safeApprove(
          address(uniswapRouter),
          token0Bought
      );
      IERC20(_ToUnipoolToken1).safeApprove(
          address(uniswapRouter),
          token1Bought
      );

      (uint256 amountA, uint256 amountB, uint256 LP) = uniswapRouter
          .addLiquidity(
          _ToUnipoolToken0,
          _ToUnipoolToken1,
          token0Bought,
          token1Bought,
          1,
          1,
          address(this),
          deadline
      );

      if (transferResidual) {
          //Returning Residue in token0, if any.
          if (token0Bought.sub(amountA) > 0) {
              IERC20(_ToUnipoolToken0).safeTransfer(
                  msg.sender,
                  token0Bought.sub(amountA)
              );
          }

          //Returning Residue in token1, if any
          if (token1Bought.sub(amountB) > 0) {
              IERC20(_ToUnipoolToken1).safeTransfer(
                  msg.sender,
                  token1Bought.sub(amountB)
              );
          }
      }

      return LP;
  }

  function _fillQuote(
      address _fromTokenAddress,
      address _pairAddress,
      uint256 _amount,
      address _swapTarget,
      bytes memory swapCallData
  ) internal returns (uint256 amountBought, address intermediateToken) {
      uint256 valueToSend;
      if (_fromTokenAddress == address(0)) {
          valueToSend = _amount;
      } else {
          IERC20 fromToken = IERC20(_fromTokenAddress);
          fromToken.safeApprove(address(_swapTarget), 0);
          fromToken.safeApprove(address(_swapTarget), _amount);
      }

      (address _token0, address _token1) = _getPairTokens(_pairAddress);
      IERC20 token0 = IERC20(_token0);
      IERC20 token1 = IERC20(_token1);
      uint256 initialBalance0 = token0.balanceOf(address(this));
      uint256 initialBalance1 = token1.balanceOf(address(this));

      (bool success, ) = _swapTarget.call{value: valueToSend}(swapCallData);
      require(success, "Error Swapping Tokens 1");

      uint256 finalBalance0 = token0.balanceOf(address(this)).sub(
          initialBalance0
      );
      uint256 finalBalance1 = token1.balanceOf(address(this)).sub(
          initialBalance1
      );

      if (finalBalance0 > finalBalance1) {
          amountBought = finalBalance0;
          intermediateToken = _token0;
      } else {
          amountBought = finalBalance1;
          intermediateToken = _token1;
      }

      require(amountBought > 0, "Swapped to Invalid Intermediate");
  }

  function _swapIntermediate(
      address _toContractAddress,
      address _ToUnipoolToken0,
      address _ToUnipoolToken1,
      uint256 _amount
  ) internal returns (uint256 token0Bought, uint256 token1Bought) {
      IUniswapV2Pair pair = IUniswapV2Pair(
          UniSwapV2FactoryAddress.getPair(_ToUnipoolToken0, _ToUnipoolToken1)
      );
      (uint256 res0, uint256 res1, ) = pair.getReserves();
      if (_toContractAddress == _ToUnipoolToken0) {
          uint256 amountToSwap = calculateSwapInAmount(res0, _amount);
          //if no reserve or a new pair is created
          if (amountToSwap <= 0) amountToSwap = _amount.div(2);
          token1Bought = _token2Token(
              _toContractAddress,
              _ToUnipoolToken1,
              amountToSwap
          );
          token0Bought = _amount.sub(amountToSwap);
      } else {
          uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
          //if no reserve or a new pair is created
          if (amountToSwap <= 0) amountToSwap = _amount.div(2);
          token0Bought = _token2Token(
              _toContractAddress,
              _ToUnipoolToken0,
              amountToSwap
          );
          token1Bought = _amount.sub(amountToSwap);
      }
  }

  function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
      internal
      pure
      returns (uint256)
  {
      return
          Babylonian
              .sqrt(
              reserveIn.mul(userIn.mul(3988000) + reserveIn.mul(3988009))
          )
              .sub(reserveIn.mul(1997)) / 1994;
  }

  /**
  @notice This function is used to swap ERC20 <> ERC20
  @param _FromTokenContractAddress The token address to swap from.
  @param _ToTokenContractAddress The token address to swap to.
  @param tokens2Trade The amount of tokens to swap
  @return tokenBought The quantity of tokens bought
  */
  function _token2Token(
      address _FromTokenContractAddress,
      address _ToTokenContractAddress,
      uint256 tokens2Trade
  ) internal returns (uint256 tokenBought) {
      if (_FromTokenContractAddress == _ToTokenContractAddress) {
          return tokens2Trade;
      }
      IERC20(_FromTokenContractAddress).safeApprove(
          address(uniswapRouter),
          0
      );
      IERC20(_FromTokenContractAddress).safeApprove(
          address(uniswapRouter),
          tokens2Trade
      );

      address pair = UniSwapV2FactoryAddress.getPair(
          _FromTokenContractAddress,
          _ToTokenContractAddress
      );
      require(pair != address(0), "No Swap Available");
      address[] memory path = new address[](2);
      path[0] = _FromTokenContractAddress;
      path[1] = _ToTokenContractAddress;

      tokenBought = uniswapRouter.swapExactTokensForTokens(
          tokens2Trade,
          1,
          path,
          address(this),
          deadline
      )[path.length - 1];

      require(tokenBought > 0, "Error Swapping Tokens 2");
  }

  // - to Pause the contract
  function toggleContractActive() public onlyOwner {
      stopped = !stopped;
  }

  function set_new_goodwill(uint16 _new_goodwill) public onlyOwner {
      require(
          _new_goodwill >= 0 && _new_goodwill <= 100,
          "GoodWill Value not allowed"
      );
      goodwill = _new_goodwill;
  }

  function set_feeWhitelist(address zapAddress, bool status)
      external
      onlyOwner
  {
      feeWhitelist[zapAddress] = status;
  }

  function set_new_affiliateSplit(uint16 _new_affiliateSplit)
      external
      onlyOwner
  {
      require(
          _new_affiliateSplit <= 100,
          "Affiliate Split Value not allowed"
      );
      affiliateSplit = _new_affiliateSplit;
  }

  function set_affiliate(address _affiliate, bool _status)
      external
      onlyOwner
  {
      affiliates[_affiliate] = _status;
  }

  ///@notice Withdraw goodwill share, retaining affilliate share
  function withdrawTokens(address[] calldata tokens) external onlyOwner {
      for (uint256 i = 0; i < tokens.length; i++) {
          uint256 qty;

          if (tokens[i] == ETHAddress) {
              qty = address(this).balance.sub(
                  totalAffiliateBalance[tokens[i]]
              );
              Address.sendValue(payable(owner()), qty);
          } else {
              qty = IERC20(tokens[i]).balanceOf(address(this)).sub(
                  totalAffiliateBalance[tokens[i]]
              );
              IERC20(tokens[i]).safeTransfer(owner(), qty);
          }
      }
  }

  ///@notice Withdraw affilliate share, retaining goodwill share
  function affilliateWithdraw(address[] calldata tokens) external {
      uint256 tokenBal;
      for (uint256 i = 0; i < tokens.length; i++) {
          tokenBal = affiliateBalance[msg.sender][tokens[i]];
          affiliateBalance[msg.sender][tokens[i]] = 0;
          totalAffiliateBalance[tokens[i]] = totalAffiliateBalance[tokens[i]]
              .sub(tokenBal);

          if (tokens[i] == ETHAddress) {
              Address.sendValue(msg.sender, tokenBal);
          } else {
              IERC20(tokens[i]).safeTransfer(msg.sender, tokenBal);
          }
      }
  }
}
