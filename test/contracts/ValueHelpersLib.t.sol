// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ValueHelpersLibHarness} from "test/harnesses/ValueHelpersLibHarness.sol";

contract ValueHelpersLibTest is Test {
    ValueHelpersLibHarness valueHelpersLib;

    function setUp() public {
        valueHelpersLib = new ValueHelpersLibHarness();
    }

    function test_calcSharesAmountForValue_success() public view {
        uint256 valuePerShare = 1_000;
        uint256 value = 5_000;
        uint256 expectedSharesAmount = 5e18;

        uint256 sharesAmount =
            valueHelpersLib.exposed_calcSharesAmountForValue({_valuePerShare: valuePerShare, _value: value});

        assertEq(sharesAmount, expectedSharesAmount);
    }

    function test_calcValueOfSharesAmount_success() public view {
        uint256 valuePerShare = 1_000;
        uint256 sharesAmount = 5e18;
        uint256 expectedValue = 5_000;

        uint256 value = valueHelpersLib.exposed_calcValueOfSharesAmount({
            _valuePerShare: valuePerShare, _sharesAmount: sharesAmount
        });

        assertEq(value, expectedValue);
    }

    function test_calcValuePerShare_success() public view {
        uint256 totalValue = 5_000;
        uint256 totalSharesAmount = 5e18;
        uint256 expectedValuePerShare = 1_000;

        uint256 valuePerShare =
            valueHelpersLib.exposed_calcValuePerShare({_totalValue: totalValue, _totalSharesAmount: totalSharesAmount});

        assertEq(valuePerShare, expectedValuePerShare);
    }

    function test_convert_success_rateQuotedInBase() public view {
        // Use different precisions for all
        uint256 basePrecision = 1e18;
        uint256 ratePrecision = 1e5;
        uint256 quotePrecision = 1e7;

        uint256 baseAmount = 15e18; // 15 base units
        uint256 rate = 5e5; // 5 base units per quote unit
        uint256 expectedQuoteAmount = 3e7; // 3 quote units

        uint256 quoteAmount = valueHelpersLib.exposed_convert({
            _baseAmount: baseAmount,
            _basePrecision: basePrecision,
            _quotePrecision: quotePrecision,
            _rate: rate,
            _ratePrecision: ratePrecision,
            _rateQuotedInBase: true
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }

    function test_convert_success_rateQuotedInQuote() public view {
        // Use different precisions for all
        uint256 basePrecision = 1e18;
        uint256 ratePrecision = 1e5;
        uint256 quotePrecision = 1e7;

        uint256 baseAmount = 3e18; // 3 base units
        uint256 rate = 5e5; // 5 quote units per base unit
        uint256 expectedQuoteAmount = 15e7; // 15 quote units

        uint256 quoteAmount = valueHelpersLib.exposed_convert({
            _baseAmount: baseAmount,
            _basePrecision: basePrecision,
            _quotePrecision: quotePrecision,
            _rate: rate,
            _ratePrecision: ratePrecision,
            _rateQuotedInBase: false
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }
}
