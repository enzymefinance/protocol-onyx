// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IChainlinkAggregator} from "src/interfaces/external/IChainlinkAggregator.sol";
import {SHARES_PRECISION, VALUE_ASSET_PRECISION} from "src/utils/Constants.sol";

/// @title ValueHelpersLib Library
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Common utility functions for handling value calculations
library ValueHelpersLib {
    error ValueHelpersLib__ParseValidatedRateFromAggregatorV3__InvalidAnswer(int256 answer);

    error ValueHelpersLib__ParseValidatedRateFromAggregatorV3__MinTimestampNotMet(uint256 timestamp);

    // GENERIC HELPERS

    function calcSharesAmountForValue(uint256 _valuePerShare, uint256 _value)
        internal
        pure
        returns (uint256 sharesAmount_)
    {
        return (SHARES_PRECISION * _value) / _valuePerShare;
    }

    function calcValueOfSharesAmount(uint256 _valuePerShare, uint256 _sharesAmount)
        internal
        pure
        returns (uint256 value_)
    {
        return (_valuePerShare * _sharesAmount) / SHARES_PRECISION;
    }

    function calcValuePerShare(uint256 _totalValue, uint256 _totalSharesAmount)
        internal
        pure
        returns (uint256 valuePerShare_)
    {
        return (SHARES_PRECISION * _totalValue) / _totalSharesAmount;
    }

    /// @dev Converts a base amount into a target (quote) amount, using a known rate.
    /// `_rateQuotedInBase` is true if the rate is quoted in the base value, false if in the quote value.
    function convert(
        uint256 _baseAmount,
        uint256 _basePrecision,
        uint256 _quotePrecision,
        uint256 _rate,
        uint256 _ratePrecision,
        bool _rateQuotedInBase
    ) internal pure returns (uint256 quoteAmount_) {
        if (_rateQuotedInBase) {
            // case: base asset-quoted rate
            return Math.mulDiv(_baseAmount * _ratePrecision, _quotePrecision, (_rate * _basePrecision));
        } else {
            // case: quote asset-quoted rate
            return Math.mulDiv(_baseAmount * _rate, _quotePrecision, (_ratePrecision * _basePrecision));
        }
    }

    // CHAINLINK AGGREGATOR HELPERS

    /// @dev Converts an amount of the Shares "value asset" (18-decimals precision) into a target (quote) asset amount,
    /// using a chainlink-like aggregator rate. Returned value is in the quote asset's precision.
    /// `_oracleQuotedInValueAsset` is true if the rate is quoted in the value asset, false if in the quote value.
    function convertFromValueAssetWithAggregatorV3(
        uint256 _value,
        uint256 _quotePrecision,
        address _oracle,
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInValueAsset
    ) internal view returns (uint256 quoteAmount_) {
        return convertWithAggregatorV3({
            _baseAmount: _value,
            _basePrecision: VALUE_ASSET_PRECISION,
            _quotePrecision: _quotePrecision,
            _oracle: _oracle,
            _oraclePrecision: _oraclePrecision,
            _oracleTimestampTolerance: _oracleTimestampTolerance,
            _oracleQuotedInBase: _oracleQuotedInValueAsset ? true : false
        });
    }

    /// @dev Converts an amount of a base asset into an amount of the Shares "value asset".
    /// using a chainlink-like aggregator rate. Returned value has 18-decimals precision.
    /// `_oracleQuotedInValueAsset` is true if the rate is quoted in the value asset, false if in the base asset.
    function convertToValueAssetWithAggregatorV3(
        uint256 _baseAmount,
        uint256 _basePrecision,
        address _oracle,
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInValueAsset
    ) internal view returns (uint256 value_) {
        return convertWithAggregatorV3({
            _baseAmount: _baseAmount,
            _basePrecision: _basePrecision,
            _quotePrecision: VALUE_ASSET_PRECISION,
            _oracle: _oracle,
            _oraclePrecision: _oraclePrecision,
            _oracleTimestampTolerance: _oracleTimestampTolerance,
            _oracleQuotedInBase: _oracleQuotedInValueAsset ? false : true
        });
    }

    /// @dev Converts an amount of a base asset into an amount of a quote asset, using a chainlink-like aggregator rate.
    /// Returned value is in the quote asset's precision.
    function convertWithAggregatorV3(
        uint256 _baseAmount,
        uint256 _basePrecision,
        uint256 _quotePrecision,
        address _oracle, // quoted in
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInBase
    ) internal view returns (uint256 quoteAmount_) {
        uint256 oracleRate = parseValidatedRateFromAggregatorV3({
            _aggregator: _oracle, _timestampTolerance: _oracleTimestampTolerance
        });

        return convert({
            _baseAmount: _baseAmount,
            _basePrecision: _basePrecision,
            _quotePrecision: _quotePrecision,
            _rate: oracleRate,
            _ratePrecision: _oraclePrecision,
            _rateQuotedInBase: _oracleQuotedInBase
        });
    }

    /// @dev Parses the rate from a chainlink-like aggregator, validating that:
    /// - rate > 0
    /// - the aggregator's timestamp is within the specified duration of validity (`_timestampTolerance`)
    function parseValidatedRateFromAggregatorV3(address _aggregator, uint256 _timestampTolerance)
        internal
        view
        returns (uint256 rate_)
    {
        (, int256 answer,, uint256 timestamp,) = IChainlinkAggregator(_aggregator).latestRoundData();

        require(answer > 0, ValueHelpersLib__ParseValidatedRateFromAggregatorV3__InvalidAnswer(answer));

        uint256 minTimestamp = block.timestamp - _timestampTolerance;
        require(
            timestamp >= minTimestamp,
            ValueHelpersLib__ParseValidatedRateFromAggregatorV3__MinTimestampNotMet(timestamp)
        );

        return uint256(answer);
    }
}
