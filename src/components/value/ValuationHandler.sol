// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20Metadata as IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IPositionTracker} from "src/components/value/position-trackers/IPositionTracker.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {VALUE_ASSET_PRECISION} from "src/utils/Constants.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title ValuationHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice An IValuationHandler implementation that supports share value updates by aggregating
/// untracked (user-input) value and tracked (on-chain) value
contract ValuationHandler is IValuationHandler, ComponentHelpersMixin {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for int256;
    using SafeCast for uint256;

    uint256 public constant RATE_PRECISION = 10 ** 18;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    /// @param asset The base asset of the rate
    /// @param rate The rate of the asset, quoted in Shares value asset, with 18 decimals of precision
    /// @param expiry The timestamp after which the rate will be considered invalid
    struct AssetRateInput {
        address asset;
        uint128 rate;
        uint40 expiry;
    }

    /// @param rate The rate of the asset, quoted in Shares value asset, with 18 decimals of precision
    /// @param expiry The timestamp after which the rate will be considered invalid
    struct AssetRateInfo {
        uint128 rate;
        uint40 expiry;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 public constant VALUATION_HANDLER_STORAGE_LOCATION =
        0x0373e40468ba9049d30c485103b40a820f4c179dde567c20624b82c9feb65b00;
    string public constant VALUATION_HANDLER_STORAGE_LOCATION_ID = "ValuationHandler";

    /// @custom:storage-location erc7201:enzyme.ValuationHandler
    /// @param positionTrackers The set of IPositionTracker contracts queried to aggregate on-chain "tracked value"
    /// @param assetToRate A mapping of assets to rate info
    /// @param lastShareValue The share value at most recent update (18-decimal precision)
    /// @param lastShareValueTimestamp The timestamp when lastShareValue was stored
    struct ValuationHandlerStorage {
        EnumerableSet.AddressSet positionTrackers;
        mapping(address => AssetRateInfo) assetToRate;
        uint128 lastShareValue;
        uint40 lastShareValueTimestamp;
    }

    function __getValuationHandlerStorage() internal pure returns (ValuationHandlerStorage storage $) {
        bytes32 location = VALUATION_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AssetRateSet(address asset, uint128 rate, uint40 expiry);

    event PositionTrackerAdded(address positionTracker);

    event PositionTrackerRemoved(address positionTracker);

    event ShareValueUpdated(
        uint256 netShareValue, int256 trackedPositionsValue, int256 untrackedPositionsValue, uint256 totalFeesOwed
    );

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ValuationHandler__AddPositionTracker__AlreadyAdded();

    error ValuationHandler__RemovePositionTracker__AlreadyRemoved();

    error ValuationHandler__ValidateRate__RateExpired();

    error ValuationHandler__ValidateRate__RateNotSet();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: VALUATION_HANDLER_STORAGE_LOCATION, _id: VALUATION_HANDLER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function addPositionTracker(address _positionTracker) external onlyAdminOrOwner {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();

        bool added = $.positionTrackers.add(_positionTracker);
        require(added, ValuationHandler__AddPositionTracker__AlreadyAdded());

        emit PositionTrackerAdded(_positionTracker);
    }

    function removePositionTracker(address _positionTracker) external onlyAdminOrOwner {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();

        bool removed = $.positionTrackers.remove(_positionTracker);
        require(removed, ValuationHandler__RemovePositionTracker__AlreadyRemoved());

        emit PositionTrackerRemoved(_positionTracker);
    }

    //==================================================================================================================
    // Valuation
    //==================================================================================================================

    /// @dev Returns 18-decimal precision
    function convertAssetAmountToValue(address _asset, uint256 _assetAmount) public view returns (uint256 value_) {
        __validateRate(_asset);

        AssetRateInfo memory rateInfo = getAssetRateInfo(_asset);

        return ValueHelpersLib.convert({
            _baseAmount: _assetAmount,
            _basePrecision: 10 ** IERC20(_asset).decimals(),
            _quotePrecision: VALUE_ASSET_PRECISION,
            _rate: rateInfo.rate,
            _ratePrecision: RATE_PRECISION,
            _rateQuotedInBase: false
        });
    }

    /// @dev Returns _asset precision
    function convertValueToAssetAmount(uint256 _value, address _asset) public view returns (uint256 assetAmount_) {
        __validateRate(_asset);

        AssetRateInfo memory rateInfo = getAssetRateInfo(_asset);

        return ValueHelpersLib.convert({
            _baseAmount: _value,
            _basePrecision: VALUE_ASSET_PRECISION,
            _quotePrecision: 10 ** IERC20(_asset).decimals(),
            _rate: rateInfo.rate,
            _ratePrecision: RATE_PRECISION,
            _rateQuotedInBase: true
        });
    }

    /// @dev Returns 18-decimal precision
    function getDefaultSharePrice() public pure returns (uint256 sharePrice_) {
        return VALUE_ASSET_PRECISION;
    }

    /// @dev Returns 18-decimal precision.
    /// Returns the price per-share, not value, which is returned by getShareValue().
    function getSharePrice() public view returns (uint256 price_, uint256 timestamp_) {
        uint256 value;
        (value, timestamp_) = getShareValue();

        price_ = value > 0 ? value : getDefaultSharePrice();
    }

    /// @dev Returns 18-decimal precision.
    /// Returns the actual value per share, not the price, which is returned by getSharePrice().
    function getShareValue() public view override returns (uint256 value_, uint256 timestamp_) {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        return ($.lastShareValue, $.lastShareValueTimestamp);
    }

    function __validateRate(address _asset) internal view {
        AssetRateInfo memory rateInfo = getAssetRateInfo(_asset);
        require(rateInfo.rate > 0, ValuationHandler__ValidateRate__RateNotSet());
        require(rateInfo.expiry > block.timestamp, ValuationHandler__ValidateRate__RateExpired());
    }

    //==================================================================================================================
    // Value updates (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the rate of a given asset, quoted in the Shares value asset
    function setAssetRate(AssetRateInput calldata _rateInput) external onlyAdminOrOwner {
        __setAssetRate({_asset: _rateInput.asset, _rate: _rateInput.rate, _expiry: _rateInput.expiry});
    }

    /// @notice Convenience function to execute setAssetRate() and then updateShareValue()
    /// @dev See natspec of individual functions
    function setAssetRatesThenUpdateShareValue(AssetRateInput[] calldata _rateInputs, int256 _untrackedPositionsValue)
        external
        onlyAdminOrOwner
        returns (uint256 netShareValue_)
    {
        for (uint256 i; i < _rateInputs.length; i++) {
            AssetRateInput memory rateInput = _rateInputs[i];
            __setAssetRate({_asset: rateInput.asset, _rate: rateInput.rate, _expiry: rateInput.expiry});
        }

        return __updateShareValue({_untrackedPositionsValue: _untrackedPositionsValue});
    }

    /// @notice Updates the share value by aggregating the given untracked positions value with tracked on-chain value,
    /// and settling dynamic fees.
    function updateShareValue(int256 _untrackedPositionsValue)
        external
        onlyAdminOrOwner
        returns (uint256 netShareValue_)
    {
        return __updateShareValue({_untrackedPositionsValue: _untrackedPositionsValue});
    }

    function __setAssetRate(address _asset, uint128 _rate, uint40 _expiry) internal {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        $.assetToRate[_asset] = AssetRateInfo({rate: _rate, expiry: _expiry});

        emit AssetRateSet({asset: _asset, rate: _rate, expiry: _expiry});
    }

    /// @dev _untrackedPositionsValue and netShareValue_ are 18-decimal precision.
    /// If no shares exist:
    /// - logic still runs
    /// - FeeHandler is still called to settle fees
    /// - lastShareValue is set to 0
    /// Reverts if:
    /// - totalPositionsValue < 0
    /// - totalPositionsValue < totalFeesOwed
    function __updateShareValue(int256 _untrackedPositionsValue) internal returns (uint256 netShareValue_) {
        Shares shares = Shares(__getShares());

        // Sum tracked positions
        int256 trackedPositionsValue;
        address[] memory positionTrackers = getPositionTrackers();
        for (uint256 i; i < positionTrackers.length; i++) {
            trackedPositionsValue += IPositionTracker(positionTrackers[i]).getPositionValue();
        }

        // Sum tracked + untracked positions
        uint256 totalPositionsValue = (trackedPositionsValue + _untrackedPositionsValue).toUint256();

        // Settle dynamic fees and get total fees owed
        uint256 totalFeesOwed;
        address feeHandler = shares.getFeeHandler();
        if (feeHandler != address(0)) {
            IFeeHandler(feeHandler).settleDynamicFeesGivenPositionsValue({_totalPositionsValue: totalPositionsValue});
            totalFeesOwed = IFeeHandler(feeHandler).getTotalValueOwed();
        }

        // Calculate net share value (inclusive of total fees owed)
        uint256 sharesSupply = shares.totalSupply();
        if (sharesSupply > 0) {
            netShareValue_ = ValueHelpersLib.calcValuePerShare({
                _totalValue: totalPositionsValue - totalFeesOwed, _totalSharesAmount: sharesSupply
            });
        }
        // else: no shares, netShareValue_ = 0

        // Store share value
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        $.lastShareValue = netShareValue_.toUint128();
        $.lastShareValueTimestamp = uint40(block.timestamp);

        emit ShareValueUpdated({
            netShareValue: netShareValue_,
            trackedPositionsValue: trackedPositionsValue,
            untrackedPositionsValue: _untrackedPositionsValue,
            totalFeesOwed: totalFeesOwed
        });
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    function getAssetRateInfo(address _asset) public view returns (AssetRateInfo memory assetRateInfo_) {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        return $.assetToRate[_asset];
    }

    function getPositionTrackers() public view returns (address[] memory) {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        return $.positionTrackers.values();
    }

    function isPositionTracker(address _positionTracker) public view returns (bool) {
        ValuationHandlerStorage storage $ = __getValuationHandlerStorage();
        return $.positionTrackers.contains(_positionTracker);
    }
}
