// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

contract ValueHelpersLibHarness {
    function exposed_calcSharesAmountForValue(uint256 _valuePerShare, uint256 _value)
        external
        pure
        returns (uint256 sharesAmount_)
    {
        return ValueHelpersLib.calcSharesAmountForValue({_valuePerShare: _valuePerShare, _value: _value});
    }

    function exposed_calcValueOfSharesAmount(uint256 _valuePerShare, uint256 _sharesAmount)
        external
        pure
        returns (uint256 value_)
    {
        return ValueHelpersLib.calcValueOfSharesAmount({_valuePerShare: _valuePerShare, _sharesAmount: _sharesAmount});
    }

    function exposed_calcValuePerShare(uint256 _totalValue, uint256 _totalSharesAmount)
        external
        pure
        returns (uint256 valuePerShare_)
    {
        return ValueHelpersLib.calcValuePerShare({_totalValue: _totalValue, _totalSharesAmount: _totalSharesAmount});
    }

    function exposed_convert(
        uint256 _baseAmount,
        uint256 _basePrecision,
        uint256 _quotePrecision,
        uint256 _rate,
        uint256 _ratePrecision,
        bool _rateQuotedInBase
    ) external pure returns (uint256 convertedAmount_) {
        return ValueHelpersLib.convert({
            _baseAmount: _baseAmount,
            _basePrecision: _basePrecision,
            _quotePrecision: _quotePrecision,
            _rate: _rate,
            _ratePrecision: _ratePrecision,
            _rateQuotedInBase: _rateQuotedInBase
        });
    }

    function exposed_convertFromValueAssetWithAggregatorV3(
        uint256 _value,
        uint256 _quotePrecision,
        address _oracle,
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInValueAsset
    ) external view returns (uint256 quoteAmount_) {
        return ValueHelpersLib.convertFromValueAssetWithAggregatorV3({
            _value: _value,
            _quotePrecision: _quotePrecision,
            _oracle: _oracle,
            _oraclePrecision: _oraclePrecision,
            _oracleTimestampTolerance: _oracleTimestampTolerance,
            _oracleQuotedInValueAsset: _oracleQuotedInValueAsset
        });
    }

    function exposed_convertToValueAssetWithAggregatorV3(
        uint256 _baseAmount,
        uint256 _basePrecision,
        address _oracle,
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInValueAsset
    ) external view returns (uint256 value_) {
        return ValueHelpersLib.convertToValueAssetWithAggregatorV3({
            _baseAmount: _baseAmount,
            _basePrecision: _basePrecision,
            _oracle: _oracle,
            _oraclePrecision: _oraclePrecision,
            _oracleTimestampTolerance: _oracleTimestampTolerance,
            _oracleQuotedInValueAsset: _oracleQuotedInValueAsset
        });
    }

    function exposed_convertWithAggregatorV3(
        uint256 _baseAmount,
        uint256 _basePrecision,
        uint256 _quotePrecision,
        address _oracle,
        uint256 _oraclePrecision,
        uint256 _oracleTimestampTolerance,
        bool _oracleQuotedInBase
    ) external view returns (uint256 quoteAmount_) {
        return ValueHelpersLib.convertWithAggregatorV3({
            _baseAmount: _baseAmount,
            _basePrecision: _basePrecision,
            _quotePrecision: _quotePrecision,
            _oracle: _oracle,
            _oraclePrecision: _oraclePrecision,
            _oracleTimestampTolerance: _oracleTimestampTolerance,
            _oracleQuotedInBase: _oracleQuotedInBase
        });
    }

    function exposed_parseValidatedRateFromAggregatorV3(address _aggregator, uint256 _timestampTolerance)
        external
        view
        returns (uint256 rate_)
    {
        return ValueHelpersLib.parseValidatedRateFromAggregatorV3({
            _aggregator: _aggregator, _timestampTolerance: _timestampTolerance
        });
    }
}
