pragma solidity ^0.7.6;

interface ICurveZapIn {
    function ZapIn(
        address _fromTokenAddress,
        address _toTokenAddress,
        address _swapAddress,
        uint256 _incomingTokenQty,
        uint256 _minPoolTokens,
        address _allowanceTarget,
        address _swapTarget,
        bytes calldata _swapCallData
    ) external payable returns (uint256 crvTokensBought);
}
