/**
 *Submitted for verification at Etherscan.io on 2021-03-21
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
///@notice This contract adds liquidity to Curve pools in one transaction with ETH or ERC tokens.

pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interface/curve/ICurveRegistry.sol";
import "./interface/curve/ICurveSwap.sol";
import "./interface/curve/ICurveEthSwap.sol";
import "./interface/yERC20.sol";
import "./interface/IWETH.sol";
import "./base/ZapInBaseV1.sol";


contract Curve_ZapIn_General_V3_1_1 is ZapInBaseV1 {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

    ICurveRegistry public curveReg;

    constructor(
        ICurveRegistry _curveRegistry,
        uint16 _goodwill,
        uint16 _affiliateSplit
    ) public ZapBaseV1(_goodwill, _affiliateSplit) {
        curveReg = _curveRegistry;
        goodwill = _goodwill;
        affiliateSplit = _affiliateSplit;
    }

    event zapIn(address sender, address pool, uint256 tokensRec);

    /**
    @notice This function adds liquidity to a Curve pool with ETH or ERC20 tokens
    @param _fromTokenAddress The token used for entry (address(0) if ether)
    @param _toTokenAddress The intermediate ERC20 token to swap to
    @param _swapAddress Curve swap address for the pool
    @param _incomingTokenQty The amount of fromToken to invest
    @param _minPoolTokens The minimum acceptable quantity of Curve LP to receive. Reverts otherwise
    @param _swapTarget Excecution target for the first swap
    @param _swapCallData DEX quote data
    @param affiliate Affiliate address
    @return crvTokensBought - Quantity of Curve LP tokens received
     */
    function ZapIn(
        address _fromTokenAddress,
        address _toTokenAddress,
        address _swapAddress,
        uint256 _incomingTokenQty,
        uint256 _minPoolTokens,
        address _swapTarget,
        bytes calldata _swapCallData,
        address affiliate
    ) external payable stopInEmergency returns (uint256 crvTokensBought) {
        uint256 toInvest = _pullTokens(
            _fromTokenAddress,
            _incomingTokenQty,
            affiliate
        );
        if (_fromTokenAddress == address(0)) {
            _fromTokenAddress = ETHAddress;
        }

        // perform zapIn
        crvTokensBought = _performZapIn(
            _fromTokenAddress,
            _toTokenAddress,
            _swapAddress,
            toInvest,
            _swapTarget,
            _swapCallData
        );

        require(
            crvTokensBought > _minPoolTokens,
            "Received less than minPoolTokens"
        );

        address poolTokenAddress = curveReg.getTokenAddress(_swapAddress);

        emit zapIn(msg.sender, poolTokenAddress, crvTokensBought);

        IERC20(poolTokenAddress).transfer(msg.sender, crvTokensBought);
    }

    function _performZapIn(
        address _fromTokenAddress,
        address _toTokenAddress,
        address _swapAddress,
        uint256 toInvest,
        address _swapTarget,
        bytes memory _swapCallData
    ) internal returns (uint256 crvTokensBought) {
        (bool isUnderlying, uint8 underlyingIndex) = curveReg.isUnderlyingToken(
            _swapAddress,
            _fromTokenAddress
        );

        if (isUnderlying) {
            crvTokensBought = _enterCurve(
                _swapAddress,
                toInvest,
                underlyingIndex
            );
        } else {
            //swap tokens using 0x swap
            uint256 tokensBought = _fillQuote(
                _fromTokenAddress,
                _toTokenAddress,
                toInvest,
                _swapTarget,
                _swapCallData
            );
            if (_toTokenAddress == address(0)) _toTokenAddress = ETHAddress;

            //get underlying token index
            (isUnderlying, underlyingIndex) = curveReg.isUnderlyingToken(
                _swapAddress,
                _toTokenAddress
            );

            if (isUnderlying) {
                crvTokensBought = _enterCurve(
                    _swapAddress,
                    tokensBought,
                    underlyingIndex
                );
            } else {
                (uint256 tokens, uint8 metaIndex) = _enterMetaPool(
                    _swapAddress,
                    _toTokenAddress,
                    tokensBought
                );

                crvTokensBought = _enterCurve(_swapAddress, tokens, metaIndex);
            }
        }
    }

    function _pullTokens(
        address token,
        uint256 amount,
        address affiliate
    ) internal returns (uint256) {
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

            if (affiliates[affiliate]) {
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

    /**
    @notice This function gets adds the liquidity for meta pools and returns the token index and swap tokens
    @param _swapAddress Curve swap address for the pool
    @param _toTokenAddress The ERC20 token to which from token to be convert
    @param  swapTokens amount of toTokens to invest
    @return tokensBought - quantity of curve LP acquired
    @return index - index of LP token in _swapAddress whose pool tokens were acquired
     */
    function _enterMetaPool(
        address _swapAddress,
        address _toTokenAddress,
        uint256 swapTokens
    ) internal returns (uint256 tokensBought, uint8 index) {
        address[4] memory poolTokens = curveReg.getPoolTokens(_swapAddress);
        for (uint8 i = 0; i < 4; i++) {
            address intermediateSwapAddress = curveReg.getSwapAddress(
                poolTokens[i]
            );
            if (intermediateSwapAddress != address(0)) {
                (, index) = curveReg.isUnderlyingToken(
                    intermediateSwapAddress,
                    _toTokenAddress
                );

                tokensBought = _enterCurve(
                    intermediateSwapAddress,
                    swapTokens,
                    index
                );

                return (tokensBought, i);
            }
        }
    }

    function _fillQuote(
        address _fromTokenAddress,
        address _toTokenAddress,
        uint256 _amount,
        address _swapTarget,
        bytes memory _swapCallData
    ) internal returns (uint256 amountBought) {
        uint256 valueToSend;

        if (_fromTokenAddress == _toTokenAddress) {
            return _amount;
        }
        if (_fromTokenAddress == ETHAddress) {
            valueToSend = _amount;
        } else {
            IERC20 fromToken = IERC20(_fromTokenAddress);

            require(
                fromToken.balanceOf(address(this)) >= _amount,
                "Insufficient Balance"
            );

            _approveToken(address(fromToken), _swapTarget);
        }

        uint256 initialBalance = _toTokenAddress == address(0)
            ? address(this).balance
            : IERC20(_toTokenAddress).balanceOf(address(this));

        (bool success, ) = _swapTarget.call{value: valueToSend}(_swapCallData);
        require(success, "Error Swapping Tokens");

        amountBought = _toTokenAddress == address(0)
            ? (address(this).balance).sub(initialBalance)
            : IERC20(_toTokenAddress).balanceOf(address(this)).sub(
                initialBalance
            );

        require(amountBought > 0, "Swapped To Invalid Intermediate");
    }

    /**
    @notice This function adds liquidity to a curve pool
    @param _swapAddress Curve swap address for the pool
    @param amount The quantity of tokens being added as liquidity
    @param index The token index for the add_liquidity call
    @return crvTokensBought - the quantity of curve LP tokens received
    */
    function _enterCurve(
        address _swapAddress,
        uint256 amount,
        uint8 index
    ) internal returns (uint256 crvTokensBought) {
        address tokenAddress = curveReg.getTokenAddress(_swapAddress);
        address depositAddress = curveReg.getDepositAddress(_swapAddress);
        uint256 initialBalance = IERC20(tokenAddress).balanceOf(address(this));
        address entryToken = curveReg.getPoolTokens(_swapAddress)[index];
        if (entryToken != ETHAddress) {
            IERC20(entryToken).safeIncreaseAllowance(
                address(depositAddress),
                amount
            );
        }

        uint256 numTokens = curveReg.getNumTokens(_swapAddress);
        bool addUnderlying = curveReg.shouldAddUnderlying(_swapAddress);

        if (numTokens == 4) {
            uint256[4] memory amounts;
            amounts[index] = amount;
            if (addUnderlying) {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0, true);
            } else {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0);
            }
        } else if (numTokens == 3) {
            uint256[3] memory amounts;
            amounts[index] = amount;
            if (addUnderlying) {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0, true);
            } else {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0);
            }
        } else {
            uint256[2] memory amounts;
            amounts[index] = amount;
            if (curveReg.isEthPool(depositAddress)) {
                ICurveEthSwap(depositAddress).add_liquidity{value: amount}(
                    amounts,
                    0
                );
            } else if (addUnderlying) {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0, true);
            } else {
                ICurveSwap(depositAddress).add_liquidity(amounts, 0);
            }
        }
        crvTokensBought = (IERC20(tokenAddress).balanceOf(address(this))).sub(
            initialBalance
        );
    }

    function updateCurveRegistry(ICurveRegistry newCurveRegistry)
        external
        onlyOwner
    {
        require(newCurveRegistry != curveReg, "Already using this Registry");
        curveReg = newCurveRegistry;
    }
}
