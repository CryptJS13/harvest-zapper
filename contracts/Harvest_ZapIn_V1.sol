/**
 *Submitted for verification at Etherscan.io on 2021-01-23
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
///@notice This contract adds liquidity to Harvest vaults with ETH or ERC tokens
// SPDX-License-Identifier: GPLv2

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interface/curve/ICurveRegistry.sol";
import "./interface/curve/ICurveZapIn.sol";
import "./interface/uniswap/IUniZapInV3.sol";
import "./interface/harvest/IVault.sol";


contract Harvest_ZapIn_V1 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool public stopped = false;
    uint256 public goodwill;

    ICurveRegistry public curveReg;
    ICurveZapIn public curveZap;
    IUniZapInV3 public uniZap;
    IUniZapInV3 public sushiZap;

    constructor(
        ICurveRegistry _curveReg,
        ICurveZapIn _curveZap,
        IUniZapInV3 _uniZap,
        IUniZapInV3 _sushiZap
    ) public {
        curveReg = _curveReg;
        curveZap = _curveZap;
        uniZap = _uniZap;
        sushiZap = _sushiZap;
    }

    // circuit breaker modifiers
    modifier stopInEmergency {
        if (stopped) {
            revert("Temporarily Paused");
        } else {
            _;
        }
    }

    /**
    @notice This function adds liquidity to a Harvest vault with ETH or ERC20 tokens
    @param toWhomToIssue account that will recieve fTokens
    @param fromToken The token used for entry (address(0) if ether)
    @param amountIn The amount of fromToken to invest
    @param vault Harvest vault address for the pool
    @param minToTokens The minimum acceptable quantity of tokens if a swap occurs. Reverts otherwise
    @param swapTarget Excecution target for the first swap
    @param swapData DEX quote data
     */
    function ZapInTokenVault(
        address toWhomToIssue,
        address fromToken,
        uint256 amountIn,
        address vault,
        uint256 minToTokens,
        address swapTarget,
        bytes calldata swapData
    ) external payable stopInEmergency {
        uint256 toInvest = _pullTokens(fromToken, amountIn, true);

        address vaultUnderlying = IVault(vault).underlying();

        uint256 toTokenAmt;
        if (fromToken == vaultUnderlying) {
            toTokenAmt = toInvest;
        } else {
            toTokenAmt = _fillQuote(
                fromToken,
                vaultUnderlying,
                toInvest,
                swapTarget,
                swapData
            );
            require(toTokenAmt >= minToTokens, "Err: High Slippage");
        }

        _vaultDeposit(toWhomToIssue, vaultUnderlying, toTokenAmt, vault);
    }

    /**
    @notice This function adds liquidity to a Curve Harvest vault with ETH or ERC20 tokens
    @param toWhomToIssue account that will recieve fTokens
    @param fromToken The token used for entry (address(0) if ether)
    @param toTokenAddress The intermediate token to swap to (address(0) if ether)
    @param amountIn The amount of fromToken to invest
    @param vault Harvest vault address for the pool
    @param minCrvTokens The minimum acceptable quantity of LP tokens. Reverts otherwise
    @param swapTarget Excecution target for the first swap
    @param swapData DEX quote data
     */
    function ZapInCurveVault(
        address toWhomToIssue,
        address fromToken,
        address toTokenAddress,
        uint256 amountIn,
        address vault,
        uint256 minCrvTokens,
        address swapTarget,
        bytes calldata swapData
    ) external payable stopInEmergency {
        uint256 toInvest = _pullTokens(fromToken, amountIn, false);

        address curveTokenAddr = IVault(vault).underlying();
        address curveDepositAddr = curveReg.getDepositAddress(curveReg.getSwapAddress(curveTokenAddr));
        uint256 curveLP;

        if (fromToken != address(0)) {
            IERC20(fromToken).safeApprove(address(curveZap), toInvest);
            curveLP = curveZap.ZapIn(
                fromToken,
                toTokenAddress,
                curveDepositAddr,
                toInvest,
                minCrvTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        } else {
            curveLP = curveZap.ZapIn{value:toInvest}(
                fromToken,
                toTokenAddress,
                curveDepositAddr,
                toInvest,
                minCrvTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        }

        // deposit to vault
        _vaultDeposit(toWhomToIssue, curveTokenAddr, curveLP, vault);
    }

    /**
    @notice This function adds liquidity to a Uniswap Harvest vault with ETH or ERC20 tokens
    @param toWhomToIssue account that will recieve fTokens
    @param fromToken The token used for entry (address(0) if ether)
    @param amountIn The amount of fromToken to invest
    @param vault Harvest vault address for the pool
    @param minUniTokens The minimum acceptable quantity of LP tokens. Reverts otherwise
    @param swapTarget Excecution target for the first swap
    @param swapData DEX quote data
     */
    function ZapInUniVault(
        address toWhomToIssue,
        address fromToken,
        uint256 amountIn,
        address vault,
        uint256 minUniTokens,
        address swapTarget,
        bytes calldata swapData
    ) external payable stopInEmergency {
        uint256 toInvest = _pullTokens(fromToken, amountIn, false);

        address uniPair = IVault(vault).underlying();
        uint256 uniLP;
        if (fromToken == address(0)) {
            uniLP = uniZap.ZapIn{value:toInvest}(
                fromToken,
                uniPair,
                toInvest,
                minUniTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        } else {
            IERC20(fromToken).safeApprove(address(uniZap), toInvest);
            uniLP = uniZap.ZapIn(
                fromToken,
                uniPair,
                toInvest,
                minUniTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        }

        _vaultDeposit(toWhomToIssue, uniPair, uniLP, vault);
    }

    /**
    @notice This function adds liquidity to a Sushiswap Harvest vault with ETH or ERC20 tokens
    @param toWhomToIssue account that will recieve fTokens
    @param fromToken The token used for entry (address(0) if ether)
    @param amountIn The amount of fromToken to invest
    @param vault Harvest vault address for the pool
    @param minSushiTokens The minimum acceptable quantity of LP tokens. Reverts otherwise
    @param swapTarget Excecution target for the first swap
    @param swapData DEX quote data
     */
    function ZapInSushiVault(
        address toWhomToIssue,
        address fromToken,
        uint256 amountIn,
        address vault,
        uint256 minSushiTokens,
        address swapTarget,
        bytes calldata swapData
    ) external payable stopInEmergency {
        // get incoming tokens
        uint256 toInvest = _pullTokens(fromToken, amountIn, false);

        // get sushi lp tokens
        address sushiPair = IVault(vault).underlying();
        uint256 sushiLP;
        if (fromToken == address(0)) {
            sushiLP = sushiZap.ZapIn{value:toInvest}(
                fromToken,
                sushiPair,
                toInvest,
                minSushiTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        } else {
            IERC20(fromToken).safeApprove(address(sushiZap), toInvest);
            sushiLP = sushiZap.ZapIn(
                fromToken,
                sushiPair,
                toInvest,
                minSushiTokens,
                swapTarget,
                swapTarget,
                swapData
            );
        }

        // deposit to vault
        _vaultDeposit(toWhomToIssue, sushiPair, sushiLP, vault);
    }

    function _pullTokens(
        address token,
        uint256 amount,
        bool enableGoodwill
    ) internal returns (uint256 value) {
        if (token == address(0)) {
            require(msg.value > 0, "No eth sent");
            value = msg.value;
        } else {
            require(amount > 0, "Invalid token amount");
            require(msg.value == 0, "Eth sent with token");
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            value = amount;
        }

        if (enableGoodwill && goodwill > 0) {
            uint256 goodwillPortion = (value.mul(goodwill)).div(10000);
            value = value.sub(goodwillPortion);
        }

        return value;
    }

    function _vaultDeposit(
        address toWhomToIssue,
        address underlyingToken,
        uint256 underlyingAmt,
        address vault
    ) internal {
        IERC20(underlyingToken).safeApprove(vault, underlyingAmt);
        IVault(vault).depositFor(underlyingAmt, toWhomToIssue);
    }

    function _fillQuote(
        address _fromTokenAddress,
        address toToken,
        uint256 _amount,
        address swapTarget,
        bytes memory swapCallData
    ) internal returns (uint256 amtBought) {
        uint256 valueToSend;
        if (_fromTokenAddress == address(0)) {
            valueToSend = _amount;
        } else {
            IERC20 fromToken = IERC20(_fromTokenAddress);
            fromToken.safeApprove(address(swapTarget), 0);
            fromToken.safeApprove(address(swapTarget), _amount);
        }

        uint256 iniBal = IERC20(toToken).balanceOf(address(this));
        (bool success, ) = swapTarget.call{value:valueToSend}(swapCallData);
        require(success, "Error Swapping Tokens 1");
        uint256 finalBal = IERC20(toToken).balanceOf(address(this));

        amtBought = finalBal.sub(iniBal);
    }

    function updateCurveRegistry(ICurveRegistry _curveReg) external onlyOwner {
        curveReg = _curveReg;
    }

    function updateCurveZap(ICurveZapIn _curveZap) external onlyOwner {
        curveZap = _curveZap;
    }

    function updateUniZap(IUniZapInV3 _uniZap) external onlyOwner {
        uniZap = _uniZap;
    }

    function updateSushiZap(IUniZapInV3 _sushiZap) external onlyOwner {
        sushiZap = _sushiZap;
    }

    function set_new_goodwill(uint256 _new_goodwill) external onlyOwner {
        require(
            _new_goodwill >= 0 && _new_goodwill <= 100,
            "GoodWill Value not allowed"
        );
        goodwill = _new_goodwill;
    }

    function toggleContractActive() external onlyOwner {
        stopped = !stopped;
    }

    function withdrawTokens(IERC20[] calldata _tokenAddresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            _tokenAddresses[i].safeTransfer(
                owner(),
                _tokenAddresses[i].balanceOf(address(this))
            );
        }
    }

    function withdrawETH() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        address payable _to = payable(owner());
        _to.transfer(contractBalance);
    }
}
