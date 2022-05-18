// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialCoveredCall } from "../interfaces/IPolynomialCoveredCall.sol";

interface IWeth {
    function deposit() external payable;
}

interface EtherWrapper {
    function mint(uint256 _amt) external;
}

contract SwapAndDeposit is Auth, ReentrancyGuard {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------
    using SafeTransferLib for ERC20;

    IPolynomialCoveredCall public immutable SETH_COVERED_CALL;

    IWeth public immutable WETH;

    EtherWrapper public immutable WRAPPER;

    constructor(
        IPolynomialCoveredCall _vault,
        IWeth _weth,
        EtherWrapper _wrapper
    ) Auth(msg.sender, Authority(address(0x0))) {
        SETH_COVERED_CALL = _vault;
        WETH = _weth;
        WRAPPER = _wrapper;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function mintAndDeposit() external payable {
        WETH.deposit{ value: msg.value }();
        ERC20(address(WETH)).safeApprove(address(WRAPPER), msg.value);
        
        uint256 preMintBal = SETH_COVERED_CALL.UNDERLYING().balanceOf(address(this));
        WRAPPER.mint(msg.value);
        uint256 postMintBal = SETH_COVERED_CALL.UNDERLYING().balanceOf(address(this));

        uint256 depositAmt = postMintBal - preMintBal;
        SETH_COVERED_CALL.UNDERLYING().safeApprove(address(SETH_COVERED_CALL), depositAmt);
        SETH_COVERED_CALL.deposit(msg.sender, depositAmt);
    }
}