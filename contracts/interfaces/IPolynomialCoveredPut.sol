// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IPolynomialCoveredPut {

    struct UserInfo {
        uint256 depositRound;
        uint256 pendingDeposit;
        uint256 withdrawRound;
        uint256 withdrawnShares;
        uint256 totalShares;
    }

    function deposit(uint256 _amt) external;

    function deposit(address _user, uint256 _amt) external;

    function requestWithdraw(uint256 _shares) external;

    function completeWithdraw() external;

    function cancelWithdraw(uint256 _shares) external;
}
