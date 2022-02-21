// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialCoveredPut } from "./interfaces/IPolynomialCoveredPut.sol";

import { IOptionMarket } from "./interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketPricer } from "./interfaces/lyra/IOptionMarketPricer.sol";
import { IOptionMarketViewer } from "./interfaces/lyra/IOptionMarketViewer.sol";

contract PolynomialCoveredPut is IPolynomialCoveredPut, Auth {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice Number of weeks in a year (in 8 decimals)
    uint256 private constant WEEKS_PER_YEAR = 52142857143;

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice Collateral Asset
    ERC20 public immutable COLLATERAL;

    /// @notice Lyra Option Market
    IOptionMarket public immutable LYRA_MARKET;

    /// @notice Lyra Option Market Viewer
    IOptionMarketViewer public immutable MARKET_VIEWER;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Human Readable Name of the Vault
    string public name;

    /// @notice Address of the keeper
    address public keeper;

    /// @notice Fee Receipient
    address public feeReceipient;

    /// @notice Current round
    uint256 public currentRound;

    /// @notice Current Listing ID
    uint256 public currentListingId;

    /// @notice Current Listing ID's Expiry
    uint256 public currentExpiry;

    /// @notice Total premium collected in the round
    uint256 public premiumCollected;

    /// @notice Total amount of collateral for the current round
    uint256 public totalFunds;

    /// @notice Funds used so far in the current round
    uint256 public usedFunds;

    /// @notice Total shares issued so far
    uint256 public totalShares;

    /// @notice Vault capacity
    uint256 public vaultCapacity;

    /// @notice User deposit limit
    uint256 public userDepositLimit;

    /// @notice Total pending deposit amounts (in COLLATERAL)
    uint256 public pendingDeposits;

    /// @notice Pending withdraws (in SHARES)
    uint256 public pendingWithdraws;

    /// @notice IV Slippage limit per trade
    uint256 public ivLimit;

    /// @notice Performance Fee
    uint256 public performanceFee;

    /// @notice Management Fee
    uint256 public managementFee;

    /// @notice Mapping of User Info
    mapping (address => UserInfo) public userInfos;

    /// @notice Mapping of round versus perfomance index
    mapping (uint256 => uint256) public performanceIndices;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyKeeper {
        require(msg.sender == keeper, "NOT_KEEPER");
        _;
    }

    constructor(
        string memory _name,
        ERC20 _collateral,
        IOptionMarket _lyraMarket,
        IOptionMarketViewer _marketViewer
    ) Auth(msg.sender, Authority(address(0x0))) {
        name = _name;
        COLLATERAL = _collateral;
        LYRA_MARKET = _lyraMarket;
        MARKET_VIEWER = _marketViewer;

        performanceIndices[0] = 1e18;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function depositForRoundZero(uint256 _amt) external override {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(currentRound == 0, "ROUND_ZERO_OVER");

        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);
        require(COLLATERAL.balanceOf(address(this)) <= vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[msg.sender];
        userInfo.totalShares += _amt;
    }

    function deposit(uint256 _amt) external override {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(currentRound > 0, "ROUND_ZERO_NOT_OVER");
        require(_amt <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");

        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);

        pendingDeposits += _amt;
        require(totalFunds + pendingDeposits < vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[msg.sender];
        if (userInfo.depositRound > 0 && userInfo.depositRound <= currentRound) {
            userInfo.totalShares = userInfo.pendingDeposit.fdiv(performanceIndices[userInfo.depositRound], 1e18);
            userInfo.pendingDeposit = _amt;
        } else {
            userInfo.pendingDeposit += _amt;
        }
        userInfo.depositRound = currentRound + 1;
    }

    function requestWithdraw(uint256 _shares) external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.totalShares >= _shares, "INSUFFICIENT_SHARES");
        require(userInfo.withdrawnShares == 0, "INCOMPLETE_PENDING_WITHDRAW");

        if (currentRound == 0) {
            COLLATERAL.safeTransfer(msg.sender, _shares);
            userInfo.totalShares -= _shares;
        } else {
            userInfo.withdrawRound = currentRound + 1;
            userInfo.withdrawnShares += _shares;
            pendingWithdraws += _shares;
        }
    }

    function cancelWithdraw(uint256 _shares) external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.withdrawnShares > _shares, "NO_WITHDRAW_REQUESTS");

        userInfo.withdrawnShares -= _shares;
        pendingWithdraws -= _shares;
    }

    function completeWithdraw() external override {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(currentRound > userInfo.withdrawRound + 1, "ROUND_NOT_OVER");

        uint256 pendingWithdrawAmount = userInfo.withdrawnShares.fmul(performanceIndices[userInfo.withdrawRound], 1e18);
        COLLATERAL.safeTransfer(msg.sender, pendingWithdrawAmount);

        pendingWithdraws -= userInfo.withdrawnShares;
        userInfo.totalShares -= userInfo.withdrawnShares;
        userInfo.withdrawnShares = 0;
        userInfo.withdrawRound = 0;
    }

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    function setCap(uint256 _newCap) external requiresAuth {
        require(_newCap > 0, "CAP_CANNOT_BE_ZERO");
        vaultCapacity = _newCap;
    }

    function setUserDepositLimit(uint256 _depositLimit) external requiresAuth {
        require(_depositLimit > 0, "LIMIT_CANNOT_BE_ZERO");
        userDepositLimit = _depositLimit;
    }

    function setIvLimit(uint256 _ivLimit) external requiresAuth {
        require(_ivLimit > 0, "SLIPPAGE_CANNOT_BE_ZERO");
        ivLimit = _ivLimit;
    }

    function setFees(uint256 _perfomanceFee, uint256 _managementFee) external requiresAuth {
        require(_perfomanceFee <= 1e7, "PERF_FEE_TOO_HIGH");
        require(_managementFee <= 5e6, "MANAGE_FEE_TOO_HIGH");

        performanceFee = _perfomanceFee;
        managementFee = _managementFee;
    }

    function setFeeReceipient(address _feeReceipient) external requiresAuth {
        feeReceipient = _feeReceipient;
    }

    function startNewRound(uint256 _listingId) external requiresAuth {
        /// Check if listing ID is valid & last round's expiry is over
        (,,,,,,, uint256 boardId) = LYRA_MARKET.optionListings(_listingId);
        (, uint256 expiry,,) = LYRA_MARKET.optionBoards(boardId);
        require(expiry >= block.timestamp, "INVALID_LISTING_ID");
        require(block.timestamp > currentExpiry, "ROUND_NOT_OVER");
        /// Close position if round != 0 & Calculate funds & new index value
        if (currentRound > 0) {
            uint256 preSettleBal = COLLATERAL.balanceOf(address(this));
            LYRA_MARKET.settleOptions(currentListingId, IOptionMarket.TradeType.SHORT_PUT);
            uint256 postSettleBal = COLLATERAL.balanceOf(address(this));
            uint256 collateralWithdrawn = postSettleBal - preSettleBal;
            uint256 totalFees;

            if (collateralWithdrawn == totalFunds) {
                uint256 currentRoundManagementFees = collateralWithdrawn.fmul(managementFee, WEEKS_PER_YEAR);
                uint256 currentRoundPerfomanceFee = premiumCollected.fmul(performanceFee, WEEKS_PER_YEAR);
                totalFees = currentRoundManagementFees + currentRoundPerfomanceFee;
                COLLATERAL.safeTransfer(feeReceipient, totalFees);
            }
            uint256 collectedFunds = collateralWithdrawn + premiumCollected - totalFees;
            uint256 newIndex = collectedFunds / totalShares;
            performanceIndices[currentRound] = newIndex;

            uint256 fundsPendingWithdraws = pendingWithdraws.fmul(newIndex, 1e18);
            totalFunds = collectedFunds + pendingDeposits - fundsPendingWithdraws;

            pendingDeposits = 0;
            pendingWithdraws = 0;
            usedFunds = 0;
            premiumCollected = 0;
        } else {
            totalFunds = COLLATERAL.balanceOf(address(this));
        }
        /// Set listing ID and start round
        currentRound++;
        currentListingId = _listingId;
        currentExpiry = expiry;
    }

    function sellOptions(uint256 _amt) external onlyKeeper {
        _amt = _amt == type(uint256).max ? totalFunds - usedFunds : _amt;
        require(_amt + usedFunds <= totalFunds, "INSUFFICIENT_FUNDS");

        IOptionMarket.TradeType tradeType = IOptionMarket.TradeType.SHORT_PUT;
        (,,,,,,, uint256 boardId) = LYRA_MARKET.optionListings(currentListingId);
        (,, uint256 iv,) = LYRA_MARKET.optionBoards(boardId);
        IOptionMarketViewer.TradePremiumView memory tradePremium = MARKET_VIEWER.getPremiumForOpen(
            currentListingId, tradeType, _amt
        );
        require(iv - tradePremium.newIv < ivLimit, "IV_LIMIT_HIT");

        COLLATERAL.safeApprove(address(LYRA_MARKET), _amt);
        uint256 totalCost = LYRA_MARKET.openPosition(currentListingId, tradeType, _amt);
        premiumCollected += totalCost;
    }
}