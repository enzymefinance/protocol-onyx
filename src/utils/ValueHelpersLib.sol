// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SHARES_PRECISION} from "src/utils/Constants.sol";

/// @title ValueHelpersLib Library
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Common utility functions for handling value calculations
library ValueHelpersLib {
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
}
