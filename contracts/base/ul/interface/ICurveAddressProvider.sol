// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

interface ICurveAddressProvider {
  function get_registry() external view returns (address);
}
