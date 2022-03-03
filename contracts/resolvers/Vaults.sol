// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";

interface IVault {
    struct UserInfo {
        uint256 depositRound;
        uint256 pendingDeposit;
        uint256 withdrawRound;
        uint256 withdrawnShares;
        uint256 totalShares;
    }

    function currentRound() external view returns (uint256);

    function userInfos(address _user) external view returns (UserInfo memory);

    function performanceIndices(uint256 _round) external view returns (uint256);
}

contract Vaults {
    using FixedPointMathLib for uint256;

    function getAllBalances(
        address _user,
        IVault[] memory _vaults,
        ERC20[] memory _tokens
    ) public view returns (uint256[] memory _vaultBalances, uint256[] memory _vaultShares, uint256[] memory _balances) {
        _balances = getTokenBalances(_user, _tokens);
        (_vaultBalances, _vaultShares) = getUserBalances(_user, _vaults);
    }

    function getUserBalance(address _user, IVault _vault) public view returns (uint256 _balance, uint256 _shares) {
        IVault.UserInfo memory _userInfo = _vault.userInfos(_user);
        uint256 _currentRound = _vault.currentRound();
        _shares = _userInfo.totalShares;

        if (_userInfo.pendingDeposit > 0 && _userInfo.depositRound < _currentRound) {
            uint256 _index = _vault.performanceIndices(_userInfo.depositRound);
            _shares += _userInfo.pendingDeposit.fdiv(_index, 1e18);
            _userInfo.pendingDeposit = 0;
        }

        uint256 _currentIndex = _vault.performanceIndices(_currentRound - 1);
        _balance = _shares.fmul(_currentIndex, 1e18) + _userInfo.pendingDeposit;
    }

    function getUserBalances(address _user, IVault[] memory _vaults) public view returns (uint256[] memory _balances, uint256[] memory _shares) {
        _balances = new uint256[](_vaults.length);
        _shares = new uint256[](_vaults.length);

        for (uint256 i = 0; i < _vaults.length; i++) {
            (_balances[i], _shares[i]) = getUserBalance(_user, _vaults[i]);
        }
    }

    function getTokenBalances(address _user, ERC20[] memory _tokens) public view returns (uint256[] memory _balances) {
        _balances = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            _balances[i] = _tokens[i].balanceOf(_user);
        }
    }

    function getPerformance(uint256 _rounds, IVault _vault) public view returns (uint256[] memory _indices) {
        uint256 _currentRound = _vault.currentRound();
        _rounds = _rounds > _currentRound ? _currentRound : _rounds;

        _indices = new uint256[](_rounds);

        for (uint256 i = 0; i < _rounds; i++) {
            _indices[i] = _vault.performanceIndices(i);
        }
    }
}
