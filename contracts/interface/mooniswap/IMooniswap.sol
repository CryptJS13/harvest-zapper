pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMooniswap {
    function getTokens() external view returns (address[] memory tokens);

    function tokens(uint256 i) external view returns (IERC20);

    function deposit(
        uint256[2] calldata maxAmounts,
        uint256[2] calldata minAmounts
    )
        external
        payable
        returns (uint256 fairSupply, uint256[2] memory receivedAmounts);

    function depositFor(
        uint256[2] calldata maxAmounts,
        uint256[2] calldata minAmounts,
        address target
    )
        external
        payable
        returns (uint256 fairSupply, uint256[2] memory receivedAmounts);
}
