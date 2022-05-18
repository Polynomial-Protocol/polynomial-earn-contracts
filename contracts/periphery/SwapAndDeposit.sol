// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialCoveredCall } from "../interfaces/IPolynomialCoveredCall.sol";
import { IPolynomialCoveredPut } from "../interfaces/IPolynomialCoveredPut.sol";

interface ISynthetix {
    function synthsByAddress(address synthAddress) external view returns (bytes32);

    function exchange(
        bytes32 sourceCurrencyKey,
        uint sourceAmount,
        bytes32 destinationCurrencyKey
    ) external returns (uint amountReceived);
}

contract SwapAndDeposit is Auth, ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    bytes32 private constant SUSD_KEY = bytes32("sUSD");

    /// -----------------------------------------------------------------------
    /// Immutables
    /// -----------------------------------------------------------------------

    ISynthetix public immutable SYNTHETIX;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    mapping(address => bool) public approvedExchanges;

    constructor(ISynthetix _synthetix) Auth(msg.sender, Authority(address(0x0))) {
        SYNTHETIX = _synthetix;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function swapAndDepositToCallVault(
        IPolynomialCoveredCall _vault,
        address _exchange,
        ERC20 _from,
        ERC20 _to,
        uint256 _amt,
        uint256 _minAmtRecieved,
        bytes memory _data
    ) external nonReentrant {
        require(approvedExchanges[_exchange]);

        _from.safeTransferFrom(msg.sender, address(this), _amt);
        _from.safeApprove(_exchange, _amt);

        uint256 preExchangeBal = _to.balanceOf(address(this));

        (bool isSuccess, ) = _exchange.call(_data);
        require(isSuccess);

        uint256 postExchangeBal = _to.balanceOf(address(this));

        uint256 depositAmt = postExchangeBal - preExchangeBal;

        require(depositAmt >= _minAmtRecieved);

        if (_vault.UNDERLYING() == _to) {
            _to.safeApprove(address(_vault), depositAmt);
            _vault.deposit(msg.sender, depositAmt);
        } else {
            uint256 finalAmt;
            {
                bytes32 synthKey = SYNTHETIX.synthsByAddress(address(_to));
                require(synthKey != "");
                bytes32 targetKey = _vault.SYNTH_KEY_UNDERLYING();

                finalAmt = SYNTHETIX.exchange(synthKey, depositAmt, targetKey);
            }
            _vault.UNDERLYING().safeApprove(address(_vault), finalAmt);
            _vault.deposit(msg.sender, finalAmt);
        }
    }

    function swapAndDepositToPutVault(
        IPolynomialCoveredPut _vault,
        address _exchange,
        ERC20 _from,
        ERC20 _to,
        uint256 _amt,
        uint256 _minAmtRecieved,
        bytes memory _data
    ) external nonReentrant {
        require(approvedExchanges[_exchange]);

        _from.safeTransferFrom(msg.sender, address(this), _amt);
        _from.safeApprove(_exchange, _amt);

        uint256 preExchangeBal = _to.balanceOf(address(this));

        (bool isSuccess, ) = _exchange.call(_data);
        require(isSuccess);

        uint256 postExchangeBal = _to.balanceOf(address(this));

        uint256 depositAmt = postExchangeBal - preExchangeBal;

        require(depositAmt >= _minAmtRecieved);

        if (_vault.COLLATERAL() == _to) {
            _to.safeApprove(address(_vault), depositAmt);
            _vault.deposit(msg.sender, depositAmt);
        } else {
            uint256 finalAmt;
            {
                bytes32 synthKey = SYNTHETIX.synthsByAddress(address(_to));
                require(synthKey != "");

                finalAmt = SYNTHETIX.exchange(synthKey, depositAmt, SUSD_KEY);
            }
            _vault.COLLATERAL().safeApprove(address(_vault), finalAmt);
            _vault.deposit(msg.sender, finalAmt);
        }
    }

    function swapEthAndDepositToCallVault(
        IPolynomialCoveredCall _vault,
        address _exchange,
        ERC20 _to,
        uint256 _amt,
        uint256 _minAmtRecieved,
        bytes memory _data
    ) external payable nonReentrant {
        require(approvedExchanges[_exchange]);
        require(_amt == msg.value);

        uint256 preExchangeBal = _to.balanceOf(address(this));

        (bool isSuccess, ) = _exchange.call{ value: _amt }(_data);
        require(isSuccess);

        uint256 postExchangeBal = _to.balanceOf(address(this));

        uint256 depositAmt = postExchangeBal - preExchangeBal;

        require(depositAmt >= _minAmtRecieved);

        if (_vault.UNDERLYING() == _to) {
            _to.safeApprove(address(_vault), depositAmt);
            _vault.deposit(msg.sender, depositAmt);
        } else {
            uint256 finalAmt;
            {
                bytes32 synthKey = SYNTHETIX.synthsByAddress(address(_to));
                require(synthKey != "");
                bytes32 targetKey = _vault.SYNTH_KEY_UNDERLYING();

                finalAmt = SYNTHETIX.exchange(synthKey, depositAmt, targetKey);
            }
            _vault.UNDERLYING().safeApprove(address(_vault), finalAmt);
            _vault.deposit(msg.sender, finalAmt);
        }
    }

    function swapEthAndDepositToPutVault(
        IPolynomialCoveredPut _vault,
        address _exchange,
        ERC20 _to,
        uint256 _amt,
        uint256 _minAmtRecieved,
        bytes memory _data
    ) external payable nonReentrant {
        require(approvedExchanges[_exchange]);
        require(_amt == msg.value);

        uint256 preExchangeBal = _to.balanceOf(address(this));

        (bool isSuccess, ) = _exchange.call{ value: _amt }(_data);
        require(isSuccess);

        uint256 postExchangeBal = _to.balanceOf(address(this));

        uint256 depositAmt = postExchangeBal - preExchangeBal;

        require(depositAmt >= _minAmtRecieved);

        if (_vault.COLLATERAL() == _to) {
            _to.safeApprove(address(_vault), depositAmt);
            _vault.deposit(msg.sender, depositAmt);
        } else {
            uint256 finalAmt;
            {
                bytes32 synthKey = SYNTHETIX.synthsByAddress(address(_to));
                require(synthKey != "");

                finalAmt = SYNTHETIX.exchange(synthKey, depositAmt, SUSD_KEY);
            }
            _vault.COLLATERAL().safeApprove(address(_vault), finalAmt);
            _vault.deposit(msg.sender, finalAmt);
        }
    }

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    function approveExchange(address _exchange) external requiresAuth {
        approvedExchanges[_exchange] = true;
    }

    function revokeExchange(address _exchange) external requiresAuth {
        approvedExchanges[_exchange] = false;
    }
}
