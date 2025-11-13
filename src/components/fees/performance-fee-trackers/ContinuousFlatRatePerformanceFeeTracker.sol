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
import {ONE_HUNDRED_PERCENT_BPS} from "src/utils/Constants.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title ContinuousFlatRatePerformanceFeeTracker Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A performance fee with a configurable rate
/// @dev resetHighWaterMark() must be called once before first settlement,
/// in order to initialize highWaterMark with an initial share price.
/// This should be done at whatever share price the fee should begin accruing.
contract ContinuousFlatRatePerformanceFeeTracker is IPerformanceFeeTracker, FeeTrackerHelpersMixin {
    using SafeCast for uint256;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION =
        0x9b5db54aad07ab0d695a15cbe8f6baf30e20bec0d8b73b9bd4ded75e29fae800;
    string private constant PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION_ID = "PerformanceFeeTracker";

    /// @custom:storage-location erc7201:enzyme.PerformanceFeeTracker
    /// @param rate Performance fee rate as a percentage of share value increase
    /// @param highWaterMark Current high water mark (share price at last settlement), in shares value asset (18-decimal precision)
    struct PerformanceFeeTrackerStorage {
        uint16 rate;
        uint128 highWaterMark;
    }

    function __getPerformanceFeeTrackerStorage() private pure returns (PerformanceFeeTrackerStorage storage $) {
        bytes32 location = PERFORMANCE_FEE_TRACKER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event HighWaterMarkUpdated(uint256 highWaterMark);

    event RateSet(uint16 rate);

    event Settled(uint256 valueDue);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ContinuousFlatRatePerformanceFeeTracker__SetRate__ExceedsMax();

    error ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkNotInitialized();

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

    /// @notice Sets the high water mark to the current share price.
    /// @dev Does not validate share price timestamp freshness.
    /// Must be called once before first settlement.
    function resetHighWaterMark() external onlyAdminOrOwner {
        (uint256 price,) = Shares(__getShares()).sharePrice();

        __updateHighWaterMark({_sharePrice: price});
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
        // Always require an initial hwm to be set
        uint256 hwm = getHighWaterMark();
        require(hwm > 0, ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkNotInitialized());

        Shares shares = Shares(__getShares());

        uint256 sharesSupply = shares.totalSupply();
        if (sharesSupply == 0) {
            // case: no shares
            // Reset hwm to default share price without settlement

            ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());

            __updateHighWaterMark({_sharePrice: valuationHandler.getDefaultSharePrice()});

            return 0;
        }

        // Calculate value per share. Return early if hwm is not exceeded.
        uint256 valuePerShare =
            ValueHelpersLib.calcValuePerShare({_totalValue: _netValue, _totalSharesAmount: sharesSupply});
        if (valuePerShare <= hwm) return 0;

        // Calculate the value due for the increase
        uint256 valueIncreasePerShare = valuePerShare - hwm;
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

    function __updateHighWaterMark(uint256 _sharePrice) internal {
        PerformanceFeeTrackerStorage storage $ = __getPerformanceFeeTrackerStorage();
        $.highWaterMark = _sharePrice.toUint128();

        emit HighWaterMarkUpdated(_sharePrice);
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the current high water mark, a share price in the share value asset
    function getHighWaterMark() public view returns (uint256) {
        return __getPerformanceFeeTrackerStorage().highWaterMark;
    }

    /// @notice Returns the performance fee rate
    function getRate() public view returns (uint16) {
        return __getPerformanceFeeTrackerStorage().rate;
    }
}
