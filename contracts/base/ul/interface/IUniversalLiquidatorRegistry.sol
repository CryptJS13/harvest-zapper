// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface IUniversalLiquidatorRegistry {

  function universalLiquidator() external view returns(address);

  function setUniversalLiquidator(address _ul) external;

  function getPath(
    address inputToken,
    address outputToken
  ) external view returns(address[] memory);

  function getDexes(
    address inputToken,
    address outputToken
  ) external view returns(bytes32[] memory);

  function setPath(
    address inputToken,
    address outputToken,
    address[] memory path,
    bytes32[] memory dexes
  ) external;
}
