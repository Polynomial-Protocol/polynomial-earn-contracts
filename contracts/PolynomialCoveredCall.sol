// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { Auth, Authority } from "@rari-capital/solmate/src/auth/Auth.sol";
import { ERC20 } from "@rari-capital/solmate/src/tokens/ERC20.sol";
import { FixedPointMathLib } from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import { ReentrancyGuard } from "@rari-capital/solmate/src/utils/ReentrancyGuard.sol";
import { SafeTransferLib } from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import { IPolynomialCoveredCall } from "./interfaces/IPolynomialCoveredCall.sol";

import { IOptionMarket } from "./interfaces/lyra/IOptionMarket.sol";
import { IOptionMarketPricer } from "./interfaces/lyra/IOptionMarketPricer.sol";
import { IOptionMarketViewer } from "./interfaces/lyra/IOptionMarketViewer.sol";
import { ISynthetix } from "./interfaces/lyra/ISynthetix.sol";

import { Pausable } from "./utils/Pausable.sol";

contract PolynomialCoveredCall is IPolynomialCoveredCall, ReentrancyGuard, Auth, Pausable {
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

    /// @notice Underlying Asset
    ERC20 public immutable UNDERLYING;

    /// @notice Synthetix
    ISynthetix public immutable SYNTHETIX;

    /// @notice Lyra Option Market
    IOptionMarket public immutable LYRA_MARKET;

    /// @notice Synthetix currency key of the underlying token
    bytes32 public immutable SYNTH_KEY_UNDERLYING;

    /// @notice Synthetix currency key of the premium token
    bytes32 public immutable SYNTH_KEY_PREMIUM;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice Human Readable Name of the Vault
    string public name;

    /// @notice Address of the vault keeper
    address public keeper;

    /// @notice Fee Reciepient
    address public feeReciepient;

    /// @notice Current round
    uint256 public currentRound;

    /// @notice Current Listing ID (Listing id is a specific option in Lyra Market)
    uint256 public currentListingId;

    /// @notice Current Listing ID's Expiry
    uint256 public currentExpiry;

    /// @notice Current Listing Strike Price
    uint256 public currentStrike;

    /// @notice Total premium collected in the round (so far)
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

    /// @notice Total pending deposit amounts (in UNDERLYING)
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

    event StartNewRound(
        uint256 indexed round,
        uint256 indexed listingId,
        uint256 newIndex,
        uint256 expiry,
        uint256 strikePrice,
        uint256 lostColl,
        uint256 qty
    );

    event SellOptions(
        uint256 indexed round,
        uint256 optionsSold,
        uint256 totalCost,
        uint256 expiry,
        uint256 strikePrice
    );

    event CompleteWithdraw(
        address indexed user,
        uint256 indexed withdrawnRound,
        uint256 shares,
        uint256 funds
    );

    event Deposit(
        address indexed user,
        uint256 indexed depositRound,
        uint256 amt
    );

    event RequestWithdraw(
        address indexed user,
        uint256 indexed withdrawnRound, uint256 shares
    );

    event CancelWithdraw(
        address indexed user,
        uint256 indexed withdrawnRound,
        uint256 shares
    );

    event SetCap(
        address indexed auth,
        uint256 oldCap,
        uint256 newCap
    );

    event SetUserDepositLimit(
        address indexed auth,
        uint256 oldDepositLimit,
        uint256 newDepositLimit
    );

    event SetIvLimit(
        address indexed auth,
        uint256 oldLimit,
        uint256 newLimit
    );

    event SetFees(
        address indexed auth,
        uint256 oldManageFee,
        uint256 oldPerfFee,
        uint256 newManageFee,
        uint256 newPerfFee
    );

    event SetFeeReciepient(
        address indexed auth,
        address oldReceipient,
        address newReceipient
    );

    event SetKeeper(
        address indexed auth,
        address oldKeeper,
        address newKeeper
    );

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier onlyKeeper {
        require(msg.sender == keeper, "NOT_KEEPER");
        _;
    }

    constructor(
        string memory _name,
        ERC20 _underlying,
        ISynthetix _synthetix,
        IOptionMarket _lyraMarket,
        bytes32 _underlyingKey,
        bytes32 _premiumKey
    ) Auth(msg.sender, Authority(address(0x0))) {
        name = _name;
        UNDERLYING = _underlying;
        SYNTHETIX = _synthetix;
        LYRA_MARKET = _lyraMarket;
        SYNTH_KEY_UNDERLYING = _underlyingKey;
        SYNTH_KEY_PREMIUM = _premiumKey;

        performanceIndices[0] = 1e18;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    /// @notice Deposits UNDERLYING tokens to the vault
    /// Shares assigned at the end of the current round (unless the round is 0)
    /// @param _amt Amount of UNDERLYING tokens to deposit
    function deposit(uint256 _amt) external override nonReentrant whenNotPaused {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");

        if (currentRound == 0) {
            _depositForRoundZero(msg.sender, _amt);
        } else {
            _deposit(msg.sender, _amt);
        }

        emit Deposit(msg.sender, currentRound, _amt);
    }

    /// @notice Deposits UNDERLYING tokens to the vault for another address
    /// Used in periphery contracts to swap and deposit
    /// @param _amt Amount of UNDERLYING tokens to deposit
    function deposit(address _user, uint256 _amt) external override nonReentrant whenNotPaused {
        require(_amt > 0, "AMT_CANNOT_BE_ZERO");

        if (currentRound == 0) {
            _depositForRoundZero(_user, _amt);
        } else {
            _deposit(_user, _amt);
        }

        emit Deposit(_user, currentRound, _amt);
    }

    /// @notice Request withdraw from the vault
    /// Unless cancelled, withdraw request can be completed at the end of the round
    /// @param _shares Amount of shares to withdraw
    function requestWithdraw(uint256 _shares) external override nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];

        if (userInfo.depositRound < currentRound && userInfo.pendingDeposit > 0) {
            /// Convert any pending deposit to shares
            userInfo.totalShares += userInfo.pendingDeposit.fdiv(
                performanceIndices[userInfo.depositRound],
                1e18
            );
            userInfo.pendingDeposit = 0;
        }

        require(userInfo.totalShares >= _shares, "INSUFFICIENT_SHARES");

        if (currentRound == 0) {
            UNDERLYING.safeTransfer(msg.sender, _shares);
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

    /// @notice Cancel a withdraw request
    /// Cannot cancel a withdraw request if a round has already passed
    /// @param _shares Amount of shares to cancel
    function cancelWithdraw(uint256 _shares) external override nonReentrant whenNotPaused {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(userInfo.withdrawnShares >= _shares, "NO_WITHDRAW_REQUESTS");
        require(userInfo.withdrawRound == currentRound, "CANNOT_CANCEL_AFTER_ROUND");

        userInfo.withdrawnShares -= _shares;
        pendingWithdraws -= _shares;
        userInfo.totalShares += _shares;

        emit CancelWithdraw(msg.sender, currentRound, _shares);
    }

    /// @notice Complete withdraw request and claim UNDERLYING tokens from the vault
    function completeWithdraw() external override nonReentrant {
        UserInfo storage userInfo = userInfos[msg.sender];

        require(currentRound > userInfo.withdrawRound, "ROUND_NOT_OVER");

        /// Calculate amount to withdraw from withdrawn round's performance index
        uint256 pendingWithdrawAmount = userInfo.withdrawnShares.fmul(
            performanceIndices[userInfo.withdrawRound],
            1e18
        );
        UNDERLYING.safeTransfer(msg.sender, pendingWithdrawAmount);

        emit CompleteWithdraw(
            msg.sender,
            userInfo.withdrawRound,
            userInfo.withdrawnShares,
            pendingWithdrawAmount
        );

        userInfo.withdrawnShares = 0;
        userInfo.withdrawRound = 0;
    }

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    /// @notice Set vault capacity
    /// @param _newCap Vault capacity amount in UNDERLYING
    function setCap(uint256 _newCap) external requiresAuth {
        require(_newCap > 0, "CAP_CANNOT_BE_ZERO");
        emit SetCap(msg.sender, vaultCapacity, _newCap);
        vaultCapacity = _newCap;
    }

    /// @notice Set user deposit limit
    /// @param _depositLimit Max deposit amount per each deposit, in UNDERLYING
    function setUserDepositLimit(uint256 _depositLimit) external requiresAuth {
        require(_depositLimit > 0, "LIMIT_CANNOT_BE_ZERO");
        emit SetUserDepositLimit(msg.sender, userDepositLimit, _depositLimit);
        userDepositLimit = _depositLimit;
    }

    /// @notice Set IV Limit
    /// @param _ivLimit IV Limit. 1e16 == 1%
    function setIvLimit(uint256 _ivLimit) external requiresAuth {
        require(_ivLimit > 0, "SLIPPAGE_CANNOT_BE_ZERO");
        emit SetIvLimit(msg.sender, ivLimit, _ivLimit);
        ivLimit = _ivLimit;
    }

    /// @notice Set vault fees
    /// Fees use 8 decimals. 1% == 1e6, 10% == 1e7 & 100% == 1e8
    /// @param _perfomanceFee Performance fee
    /// @param _managementFee Management Fee
    function setFees(uint256 _perfomanceFee, uint256 _managementFee) external requiresAuth {
        require(_perfomanceFee <= 1e7, "PERF_FEE_TOO_HIGH");
        require(_managementFee <= 5e6, "MANAGE_FEE_TOO_HIGH");

        emit SetFees(
            msg.sender,
            managementFee,
            performanceFee,
            _managementFee,
            _perfomanceFee
        );

        performanceFee = _perfomanceFee;
        managementFee = _managementFee;
    }

    /// @notice Set fee reciepient address
    /// @param _feeReciepient Fee reciepient address
    function setFeeReciepient(address _feeReciepient) external requiresAuth {
        require(_feeReciepient != address(0x0), "CANNOT_BE_VOID");
        emit SetFeeReciepient(msg.sender, feeReciepient, _feeReciepient);
        feeReciepient = _feeReciepient;
    }

    /// @notice Set Keeper address
    /// Keeper bot sells options from the vault once a round is started
    /// @param _keeper Address of the keeper
    function setKeeper(address _keeper) external requiresAuth {
        emit SetKeeper(msg.sender, keeper, _keeper);
        keeper = _keeper;
    }

    /// @notice Pause contract
    /// Once paused, deposits and selling options are closed
    function pause() external requiresAuth {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external requiresAuth {
        _unpause();
    }

    /// @notice Start a new round by providing listing ID for an upcoming option
    /// @param _listingId Unique listing ID from Lyra Option Market
    function startNewRound(uint256 _listingId) external requiresAuth nonReentrant {
        /// Check if listing ID is valid & last round's expiry is over
        (,uint256 strikePrice,,,,,, uint256 boardId) = LYRA_MARKET.optionListings(_listingId);
        (, uint256 expiry,,) = LYRA_MARKET.optionBoards(boardId);
        require(expiry >= block.timestamp, "INVALID_LISTING_ID");
        require(block.timestamp > currentExpiry, "ROUND_NOT_OVER");

        /// Close position if round != 0 & Calculate funds & new index value
        if (currentRound > 0) {
            uint256 newIndex = performanceIndices[currentRound - 1];
            uint256 collateralWithdrawn = usedFunds;
            uint256 collectedFunds = totalFunds;
            uint256 totalFees;
            
            if (usedFunds > 0) {
                uint256 preSettleBal = UNDERLYING.balanceOf(address(this));
                /// Settle all the options sold from last round
                LYRA_MARKET.settleOptions(currentListingId, IOptionMarket.TradeType.SHORT_CALL);
                uint256 postSettleBal = UNDERLYING.balanceOf(address(this));
                collateralWithdrawn = postSettleBal - preSettleBal;

                /// Calculate and collect fees, if the option expired OTM
                if (collateralWithdrawn == usedFunds) {
                    uint256 currentRoundManagementFees = collateralWithdrawn.fmul(managementFee, WEEKS_PER_YEAR);
                    uint256 currentRoundPerfomanceFee = premiumCollected.fmul(performanceFee, WEEKS_PER_YEAR);
                    totalFees = currentRoundManagementFees + currentRoundPerfomanceFee;
                    UNDERLYING.safeTransfer(feeReciepient, totalFees);
                }
                /// Calculate last round's performance index
                uint256 unusedFunds = totalFunds - usedFunds;
                collectedFunds = collateralWithdrawn + premiumCollected + unusedFunds - totalFees;
                newIndex = collectedFunds.fdiv(totalShares, 1e18);
            }

            performanceIndices[currentRound] = newIndex;

            /// Process pending deposits and withdrawals
            totalShares += pendingDeposits.fdiv(newIndex, 1e18);
            totalShares -= pendingWithdraws;

            /// Calculate available funds for the round that's starting
            uint256 fundsPendingWithdraws = pendingWithdraws.fmul(newIndex, 1e18);
            totalFunds = collectedFunds + pendingDeposits - fundsPendingWithdraws;

            emit StartNewRound(
                currentRound + 1,
                _listingId,
                newIndex,
                expiry,
                strikePrice,
                usedFunds - collateralWithdrawn,
                usedFunds
            );

            pendingDeposits = 0;
            pendingWithdraws = 0;
            usedFunds = 0;
            premiumCollected = 0;
        } else {
            totalFunds = UNDERLYING.balanceOf(address(this));

            emit StartNewRound(1, _listingId, 1e18, expiry, strikePrice, 0, 0);
        }
        /// Set listing ID and start round
        currentRound++;
        currentListingId = _listingId;
        currentExpiry = expiry;
        currentStrike = strikePrice;
    }

    /// @notice Sell options to Lyra AMM
    /// Called via Keeper bot
    /// @param _amt Amount of options to sell
    function sellOptions(uint256 _amt) external onlyKeeper nonReentrant whenNotPaused {
        _amt = _amt > (totalFunds - usedFunds) ? totalFunds - usedFunds : _amt;
        require(_amt > 0, "NO_FUNDS_REMAINING");

        IOptionMarket.TradeType tradeType = IOptionMarket.TradeType.SHORT_CALL;

        /// Get initial board IV, and listing skew to calculate initial IV
        (,, uint256 initSkew,,,,, uint256 boardId) = LYRA_MARKET.optionListings(currentListingId);
        (,, uint256 initBaseIv,) = LYRA_MARKET.optionBoards(boardId);

        /// Sell options to Lyra AMM
        UNDERLYING.safeApprove(address(LYRA_MARKET), _amt);
        uint256 totalCost = LYRA_MARKET.openPosition(currentListingId, tradeType, _amt);

        /// Get final board IV, and listing skew to calculate final IV
        (,, uint256 finalSkew,,,,,) = LYRA_MARKET.optionListings(currentListingId);
        (,, uint256 finalBaseIv,) = LYRA_MARKET.optionBoards(boardId);

        /// Calculate IVs and revert if IV impact is high
        uint256 initIv = initBaseIv.fmul(initSkew, 1e18);
        uint256 finalIv = finalBaseIv.fmul(finalSkew, 1e18);
        require(initIv - finalIv < ivLimit, "IV_LIMIT_HIT");
        
        /// Swap recieved sUSD premium to UNDERLYING
        uint256 totalCostInUnderlying = SYNTHETIX.exchange(
            SYNTH_KEY_PREMIUM,
            totalCost,
            SYNTH_KEY_UNDERLYING
        );

        premiumCollected += totalCostInUnderlying;
        usedFunds += _amt;

        emit SellOptions(currentRound, _amt, totalCostInUnderlying, currentExpiry, currentStrike);
    }

    /// -----------------------------------------------------------------------
    /// Internal Methods
    /// -----------------------------------------------------------------------

    /// @notice Deposit for round zero
    /// Shares are issued during the round itself
    function _depositForRoundZero(address _user, uint256 _amt) internal {
        UNDERLYING.safeTransferFrom(msg.sender, address(this), _amt);
        require(UNDERLYING.balanceOf(address(this)) <= vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        userInfo.totalShares += _amt;
        require(userInfo.totalShares <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");
        totalShares += _amt;
    }

    /// @notice Internal deposit function
    /// Shares issued after the current round is over
    function _deposit(address _user, uint256 _amt) internal {
        UNDERLYING.safeTransferFrom(msg.sender, address(this), _amt);

        pendingDeposits += _amt;
        require(totalFunds + pendingDeposits < vaultCapacity, "CAPACITY_EXCEEDED");

        UserInfo storage userInfo = userInfos[_user];
        /// Process any pending deposit, if any
        if (userInfo.depositRound > 0 && userInfo.depositRound < currentRound) {
            userInfo.totalShares += userInfo.pendingDeposit.fdiv(
                performanceIndices[userInfo.depositRound],
                1e18
            );
            userInfo.pendingDeposit = _amt;
        } else {
            userInfo.pendingDeposit += _amt;
        }
        userInfo.depositRound = currentRound;

        uint256 totalBalance = userInfo.pendingDeposit + userInfo.totalShares.fmul(performanceIndices[currentRound - 1], 1e18);
        require(totalBalance <= userDepositLimit, "USER_DEPOSIT_LIMIT_EXCEEDED");
    }
}
