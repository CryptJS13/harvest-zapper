pragma solidity ^0.7.6;

interface IUniZapInV3 {
    function ZapIn(
        address _FromTokenContractAddress,
        address _pairAddress,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _allowanceTarget,
        address _swapTarget,
        bytes calldata swapData
    ) external payable returns (uint256);
}
