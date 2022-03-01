// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialCoveredPut } from "./interfaces/IPolynomialCoveredPut.sol";

import { IOptionMarket } from "./interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketPricer } from "./interfaces/lyra/IOptionMarketPricer.sol";
import { IOptionMarketViewer } from "./interfaces/lyra/IOptionMarketViewer.sol";

import { Pausable } from "./utils/Pausable.sol";

contract PolynomialCoveredPut is IPolynomialCoveredPut, ReentrancyGuard, Auth, Pausable {
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

    /// @notice Current Listing Strike Price
    uint256 public currentStrike;

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
    /// Events
    /// -----------------------------------------------------------------------

    event StartNewRound(uint256 indexed round, uint256 indexed listingId, uint256 newIndex, uint256 expiry, uint256 strikePrice);

    event SellOptions(uint256 indexed round, uint256 optionsSold, uint256 totalCost);

    event CompleteWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares, uint256 funds);

    event Deposit(address indexed user, uint256 indexed depositRound, uint256 amt);

    event RequestWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares);

    event CancelWithdraw(address indexed user, uint256 indexed withdrawnRound, uint256 shares);

    event SetCap(address indexed auth, uint256 oldCap, uint256 newCap);

    event SetUserDepositLimit(address indexed auth, uint256 oldDepositLimit, uint256 newDepositLimit);

    event SetIvLimit(address indexed auth, uint256 oldLimit, uint256 newLimit);

    event SetFees(address indexed auth, uint256 oldManageFee, uint256 oldPerfFee, uint256 newManageFee, uint256 newPerfFee);

    event SetFeeReceipient(address indexed auth, address oldReceipient, address newReceipient);

    event SetKeeper(address indexed auth, address oldKeeper, address newKeeper);

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

    function deposit(uint256 _amt) external override nonReentrant whenNotPaused {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(_amt <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");

        if (currentRound == 0) {
            _depositForRoundZero(msg.sender, _amt);
        } else {
            _deposit(msg.sender, _amt);
        }

        emit Deposit(msg.sender, currentRound, _amt);
    }

    function deposit(address _user, uint256 _amt) external override nonReentrant whenNotPaused {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");
        require(_amt <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");

        if (currentRound == 0) {
            _depositForRoundZero(_user, _amt);
        } else {
            _deposit(_user, _amt);
        }

        emit Deposit(_user, currentRound, _amt);
    }

    function requestWithdraw(uint256 _shares) external override nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.totalShares >= _shares, "INSUFFICIENT_SHARES");

        if (currentRound == 0) {
            COLLATERAL.safeTransfer(msg.sender, _shares);
            totalShares -= _shares;
        } else {
            if (userInfo.withdrawRound < currentRound) {
                require(userInfo.withdrawnShares == 0, "INCOMPLETE_PENDING_WITHDRAW");
            }
            userInfo.withdrawRound = currentRound;
            userInfo.withdrawnShares += _shares;
            pendingWithdraws += _shares;
        }
        userInfo.totalShares -= _shares;

        emit RequestWithdraw(msg.sender, currentRound, _shares);
    }

    function cancelWithdraw(uint256 _shares) external override nonReentrant whenNotPaused {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.withdrawnShares >= _shares, "NO_WITHDRAW_REQUESTS");
        require(userInfo.withdrawRound == currentRound, "CANNOT_CANCEL_AFTER_ROUND");

        userInfo.withdrawnShares -= _shares;
        pendingWithdraws -= _shares;
        userInfo.totalShares += _shares;

        emit CancelWithdraw(msg.sender, currentRound, _shares);
    }

    function completeWithdraw() external override nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(currentRound > userInfo.withdrawRound, "ROUND_NOT_OVER");

        uint256 pendingWithdrawAmount = userInfo.withdrawnShares.fmul(performanceIndices[userInfo.withdrawRound], 1e18);
        COLLATERAL.safeTransfer(msg.sender, pendingWithdrawAmount);

        emit CompleteWithdraw(msg.sender, userInfo.withdrawRound, userInfo.withdrawnShares, pendingWithdrawAmount);

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
        emit SetCap(msg.sender, vaultCapacity, _newCap);
        vaultCapacity = _newCap;
    }

    function setUserDepositLimit(uint256 _depositLimit) external requiresAuth {
        require(_depositLimit > 0, "LIMIT_CANNOT_BE_ZERO");
        emit SetUserDepositLimit(msg.sender, userDepositLimit, _depositLimit);
        userDepositLimit = _depositLimit;
    }

    function setIvLimit(uint256 _ivLimit) external requiresAuth {
        require(_ivLimit > 0, "SLIPPAGE_CANNOT_BE_ZERO");
        emit SetIvLimit(msg.sender, ivLimit, _ivLimit);
        ivLimit = _ivLimit;
    }

    function setFees(uint256 _perfomanceFee, uint256 _managementFee) external requiresAuth {
        require(_perfomanceFee <= 1e7, "PERF_FEE_TOO_HIGH");
        require(_managementFee <= 5e6, "MANAGE_FEE_TOO_HIGH");

        emit SetFees(msg.sender, managementFee, performanceFee, _managementFee, _perfomanceFee);

        performanceFee = _perfomanceFee;
        managementFee = _managementFee;
    }

    function setFeeReceipient(address _feeReceipient) external requiresAuth {
        require(_feeReceipient != address(0x0), "CANNOT_BE_VOID");
        emit SetFeeReceipient(msg.sender, feeReceipient, _feeReceipient);
        feeReceipient = _feeReceipient;
    }

    function setKeeper(address _keeper) external requiresAuth {
        require(_keeper != address(0x0), "CANNOT_BE_VOID");
        emit SetKeeper(msg.sender, keeper, _keeper);
        keeper = _keeper;
    }

    function startNewRound(uint256 _listingId) external requiresAuth nonReentrant {
        /// Check if listing ID is valid & last round's expiry is over
        (,uint256 strikePrice,,,,,, uint256 boardId) = LYRA_MARKET.optionListings(_listingId);
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

            if (collateralWithdrawn == usedFunds) {
                uint256 currentRoundManagementFees = collateralWithdrawn.fmul(managementFee, WEEKS_PER_YEAR);
                uint256 currentRoundPerfomanceFee = premiumCollected.fmul(performanceFee, WEEKS_PER_YEAR);
                totalFees = currentRoundManagementFees + currentRoundPerfomanceFee;
                COLLATERAL.safeTransfer(feeReceipient, totalFees);
            }
            uint256 collectedFunds = collateralWithdrawn + premiumCollected - totalFees;
            uint256 newIndex = collectedFunds.fdiv(totalShares, 1e18);
            performanceIndices[currentRound] = newIndex;

            totalShares += pendingDeposits.fdiv(newIndex, 1e18);
            totalShares -= pendingWithdraws;

            uint256 fundsPendingWithdraws = pendingWithdraws.fmul(newIndex, 1e18);
            totalFunds = collectedFunds + pendingDeposits - fundsPendingWithdraws;

            pendingDeposits = 0;
            pendingWithdraws = 0;
            usedFunds = 0;
            premiumCollected = 0;

            emit StartNewRound(currentRound + 1, _listingId, newIndex, expiry, strikePrice);
        } else {
            totalFunds = COLLATERAL.balanceOf(address(this));

            emit StartNewRound(1, _listingId, 1e18, expiry, strikePrice);
        }
        /// Set listing ID and start round
        currentRound++;
        currentListingId = _listingId;
        currentExpiry = expiry;
        currentStrike = strikePrice;
    }

    function sellOptions(uint256 _amt) external onlyKeeper nonReentrant whenNotPaused {
        uint256 maxAmt = (totalFunds - usedFunds).fdiv(currentStrike, 1e18);
        _amt = _amt > maxAmt ? maxAmt : _amt;
        require(_amt > 0, "NO_FUNDS_REMAINING");

        uint256 collateralAmt = _amt.fmul(currentStrike, 1e18);

        IOptionMarket.TradeType tradeType = IOptionMarket.TradeType.SHORT_PUT;

        IOptionMarketViewer.TradePremiumView memory zeroTradePremium = MARKET_VIEWER.getPremiumForOpen(currentListingId, tradeType, 0);
        IOptionMarketViewer.TradePremiumView memory tradePremium = MARKET_VIEWER.getPremiumForOpen(currentListingId, tradeType, _amt);

        require(zeroTradePremium.newIv - tradePremium.newIv < ivLimit, "IV_LIMIT_HIT");

        COLLATERAL.safeApprove(address(LYRA_MARKET), collateralAmt);
        uint256 totalCost = LYRA_MARKET.openPosition(currentListingId, tradeType, _amt);

        premiumCollected += totalCost;
        usedFunds += collateralAmt;

        emit SellOptions(currentRound, _amt, totalCost);
    }

    /// -----------------------------------------------------------------------
    /// Internal Methods
    /// -----------------------------------------------------------------------

    function _depositForRoundZero(address _user, uint256 _amt) internal {
        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);
        require(COLLATERAL.balanceOf(address(this)) <= vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        userInfo.totalShares += _amt;
        totalShares += _amt;
    }

    function _deposit(address _user, uint256 _amt) internal {
        COLLATERAL.safeTransferFrom(msg.sender, address(this), _amt);

        pendingDeposits += _amt;
        require(totalFunds + pendingDeposits < vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        if (userInfo.depositRound > 0 && userInfo.depositRound < currentRound) {
            userInfo.totalShares = userInfo.pendingDeposit.fdiv(performanceIndices[userInfo.depositRound], 1e18);
            userInfo.pendingDeposit = _amt;
        } else {
            userInfo.pendingDeposit += _amt;
        }
        userInfo.depositRound = currentRound;
    }
}