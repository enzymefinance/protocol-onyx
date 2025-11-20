// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IPerformanceFeeTracker} from "src/components/fees/interfaces/IPerformanceFeeTracker.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {FeeTrackerHelpersMixin} from "src/components/fees/utils/FeeTrackerHelpersMixin.sol";
import {ONE_HUNDRED_PERCENT_BPS, SECONDS_IN_YEAR} from "src/utils/Constants.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title ContinuousFlatRatePerformanceFeeTracker Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A performance fee with configurable performance rate and hurdle rate
/// @dev Fees are only charged on the portion of share price that exceeds the high-water mark by the pro-rata hurdle rate.
/// An initial hwm must be set before first settlement, by calling either resetHighWaterMark() or adjustHighWaterMark().
contract ContinuousFlatRatePerformanceFeeTracker is IPerformanceFeeTracker, FeeTrackerHelpersMixin {
    using SafeCast for uint256;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 internal constant PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION =
        0x9b5db54aad07ab0d695a15cbe8f6baf30e20bec0d8b73b9bd4ded75e29fae800;
    string private constant PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION_ID = "PerformanceFeeTracker";

    /// @custom:storage-location erc7201:enzyme.PerformanceFeeTracker
    /// @param rate Performance fee rate as a percentage of share value increase
    /// @param highWaterMark Current high water mark (share price at last settlement), in shares value asset (18-decimal precision)
    /// @param highWaterMarkTimestamp Timestamp when the high water mark was last updated
    /// @param hurdleRate An annualized percentage by which to adjust the reference share price (high water mark) during settlement
    /// @dev `hurdleRate` is an int to be able to support negative hurdle rates in the future
    struct PerformanceFeeTrackerStorage {
        uint16 rate;
        uint128 highWaterMark;
        uint40 highWaterMarkTimestamp;
        int16 hurdleRate;
    }

    function __getPerformanceFeeTrackerStorage() internal pure returns (PerformanceFeeTrackerStorage storage $) {
        bytes32 location = PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    /// @dev Emitted when the high water mark is adjusted by the admin
    event HighWaterMarkAdjusted(uint256 highWaterMark, uint256 timestamp);

    /// @dev Emitted when the high water mark is updated via calculation at current value
    event HighWaterMarkUpdated(uint256 highWaterMark);

    event HurdleRateSet(int16 hurdleRate);

    event RateSet(uint16 rate);

    event Settled(uint256 valueDue);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__HighWaterMarkIsZero();

    error ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampInFuture();

    error ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampIsZero();

    error ContinuousFlatRatePerformanceFeeTracker__CalcHurdleAdjustedHwm__NoHurdleRate();

    error ContinuousFlatRatePerformanceFeeTracker__SetHurdleRate__LessThanMin();

    error ContinuousFlatRatePerformanceFeeTracker__SetRate__ExceedsMax();

    error ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkNotInitialized();

    error ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkTimestampIsZero();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION, _id: PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    /// @notice Adjusts the high water mark to an arbitrary value and timestamp.
    /// @param _hwm The high water mark value (share value with 18-decimal precision)
    /// @param _timestamp The timestamp to associate with the high water mark
    function adjustHighWaterMark(uint256 _hwm, uint256 _timestamp) external onlyAdminOrOwner {
        require(_hwm > 0, ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__HighWaterMarkIsZero());
        require(_timestamp > 0, ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampIsZero());
        require(
            _timestamp <= block.timestamp,
            ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampInFuture()
        );

        PerformanceFeeTrackerStorage storage $ = __getPerformanceFeeTrackerStorage();
        $.highWaterMark = _hwm.toUint128();
        $.highWaterMarkTimestamp = _timestamp.toUint40();

        emit HighWaterMarkAdjusted({highWaterMark: _hwm, timestamp: _timestamp});
    }

    /// @notice Sets the high water mark to the current share price.
    /// @dev Does not validate share price timestamp freshness.
    /// Must be called once before first settlement.
    function resetHighWaterMark() external onlyAdminOrOwner {
        (uint256 price,) = Shares(__getShares()).sharePrice();

        __updateHighWaterMark({_sharePrice: price});
    }

    /// @notice Sets the hurdle rate.
    /// @param _hurdleRate Annualized hurdle rate
    /// @dev A negative hurdle rate is not currently supported
    function setHurdleRate(int16 _hurdleRate) external onlyAdminOrOwner {
        require(_hurdleRate >= 0, ContinuousFlatRatePerformanceFeeTracker__SetHurdleRate__LessThanMin());

        PerformanceFeeTrackerStorage storage $ = __getPerformanceFeeTrackerStorage();
        $.hurdleRate = _hurdleRate;

        emit HurdleRateSet(_hurdleRate);
    }

    /// @notice Sets the performance fee rate.
    /// @param _rate Performance fee rate
    function setRate(uint16 _rate) external onlyAdminOrOwner {
        require(_rate < ONE_HUNDRED_PERCENT_BPS, ContinuousFlatRatePerformanceFeeTracker__SetRate__ExceedsMax());

        PerformanceFeeTrackerStorage storage $ = __getPerformanceFeeTrackerStorage();
        $.rate = _rate;

        emit RateSet(_rate);
    }

    //==================================================================================================================
    // Settlement
    //==================================================================================================================

    /// @inheritdoc IPerformanceFeeTracker
    function settlePerformanceFee(uint256 _netValue) external onlyFeeHandler returns (uint256 valueDue_) {
        Shares shares = Shares(__getShares());
        uint256 sharesSupply = shares.totalSupply();
        uint256 hwm = getHighWaterMark();
        uint256 hwmTimestamp = getHighWaterMarkTimestamp();
        int16 hurdleRate = getHurdleRate();

        // Always require an initial hwm to be set
        require(hwm > 0, ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkNotInitialized());
        // If hurdle rate is used, require a hwm timestamp (a legacy implementation did not store the timestamp)
        require(
            hwmTimestamp > 0 || hurdleRate == 0,
            ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkTimestampIsZero()
        );

        if (sharesSupply == 0) {
            // case: no shares
            // Reset hwm to default share price without settlement

            ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());

            __updateHighWaterMark({_sharePrice: valuationHandler.getDefaultSharePrice()});

            return 0;
        }

        // Calculate the hurdle-adjusted high water mark
        uint256 hurdleAdjustedHwm = hurdleRate == 0
            ? hwm
            // forge-lint: disable-next-line(unsafe-typecast)
            : __calcHurdleAdjustedHwm({_hwm: hwm, _hwmTimestamp: hwmTimestamp, _hurdleRate: hurdleRate});

        // Calculate value per share. Return without settlement if hurdle-adjusted HWM is not exceeded.
        uint256 valuePerShare =
            ValueHelpersLib.calcValuePerShare({_totalValue: _netValue, _totalSharesAmount: sharesSupply});
        if (valuePerShare <= hurdleAdjustedHwm) return 0;

        // Calculate the value due for the increase above the hurdle-adjusted HWM
        uint256 valueIncreasePerShare = valuePerShare - hurdleAdjustedHwm;
        uint256 valueIncrease = ValueHelpersLib.calcValueOfSharesAmount({
            _valuePerShare: valueIncreasePerShare, _sharesAmount: sharesSupply
        });
        valueDue_ = (valueIncrease * getRate()) / ONE_HUNDRED_PERCENT_BPS;

        // Always settle, even if no value is due.
        // Use the net share value post-performance fee settlement.
        uint256 netValueIncludingFee = _netValue - valueDue_;
        __updateHighWaterMark({
            _sharePrice: ValueHelpersLib.calcValuePerShare({
                _totalValue: netValueIncludingFee, _totalSharesAmount: sharesSupply
            })
        });

        emit Settled({valueDue: valueDue_});
    }

    function __calcHurdleAdjustedHwm(uint256 _hwm, uint256 _hwmTimestamp, int16 _hurdleRate)
        internal
        view
        returns (uint256 hurdleAdjustedHwm_)
    {
        require(_hurdleRate > 0, ContinuousFlatRatePerformanceFeeTracker__CalcHurdleAdjustedHwm__NoHurdleRate());
        uint256 hurdleRateUint = uint256(uint16(_hurdleRate));

        // Calculate time elapsed since HWM was last updated
        uint256 timeElapsed = block.timestamp - _hwmTimestamp;

        // Calculate the hurdle-adjusted HWM
        // Formula: hwm * (1 + (hurdleRate * timeElapsed / SECONDS_IN_YEAR))
        uint256 hurdleIncrease = (_hwm * hurdleRateUint * timeElapsed) / (SECONDS_IN_YEAR * ONE_HUNDRED_PERCENT_BPS);
        hurdleAdjustedHwm_ = _hwm + hurdleIncrease;
    }

    function __updateHighWaterMark(uint256 _sharePrice) internal {
        PerformanceFeeTrackerStorage storage $ = __getPerformanceFeeTrackerStorage();
        $.highWaterMark = _sharePrice.toUint128();
        $.highWaterMarkTimestamp = uint40(block.timestamp);

        emit HighWaterMarkUpdated(_sharePrice);
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the current high water mark, a share price in the share value asset
    function getHighWaterMark() public view returns (uint256) {
        return __getPerformanceFeeTrackerStorage().highWaterMark;
    }

    /// @notice Returns the timestamp when the high water mark was last updated
    function getHighWaterMarkTimestamp() public view returns (uint256) {
        return __getPerformanceFeeTrackerStorage().highWaterMarkTimestamp;
    }

    /// @notice Returns the hurdle rate in basis points
    function getHurdleRate() public view returns (int16) {
        return __getPerformanceFeeTrackerStorage().hurdleRate;
    }

    /// @notice Returns the performance fee rate
    function getRate() public view returns (uint16) {
        return __getPerformanceFeeTrackerStorage().rate;
    }
}
