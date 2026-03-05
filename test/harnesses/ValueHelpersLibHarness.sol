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
}
