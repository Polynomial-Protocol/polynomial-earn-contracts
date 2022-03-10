// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

interface IPolynomialCoveredCall {

    struct UserInfo {
        uint256 depositRound;
        uint256 pendingDeposit;
        uint256 withdrawRound;
        uint256 withdrawnShares;
        uint256 totalShares;
    }

    function UNDERLYING() external view returns (ERC20);

    function SYNTH_KEY_UNDERLYING() external view returns (bytes32);

    function deposit(uint256 _amt) external;

    function deposit(address _user, uint256 _amt) external;

    function requestWithdraw(uint256 _shares) external;

    function completeWithdraw() external;

    function cancelWithdraw(uint256 _shares) external;
}