// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

import {ValueHelpersLibHarness} from "test/harnesses/ValueHelpersLibHarness.sol";
import {MockChainlinkAggregator} from "test/mocks/MockChainlinkAggregator.sol";

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

    function test_convertFromValueAssetWithAggregatorV3_success_notQuotedInValueAsset() public {
        // Use different precisions for all
        uint256 quotePrecision = 1e7;
        uint256 oraclePrecision = 1e5;
        uint8 oracleDecimals = 5;

        uint256 value = 3e18; // 3 value asset units
        uint256 oracleRate = 5e5; // 5 value units per asset unit
        uint256 expectedQuoteAmount = 15e7; // 15 quote units

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(oracleDecimals);
        mockAggregator.setRate(oracleRate);
        mockAggregator.setTimestamp(block.timestamp);

        uint256 quoteAmount = valueHelpersLib.exposed_convertFromValueAssetWithAggregatorV3({
            _value: value,
            _quotePrecision: quotePrecision,
            _oracle: address(mockAggregator),
            _oraclePrecision: oraclePrecision,
            _oracleTimestampTolerance: 0,
            _oracleQuotedInValueAsset: false
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }

    function test_convertFromValueAssetWithAggregatorV3_success_quotedInValueAsset() public {
        // Use different precisions for all
        uint256 quotePrecision = 1e7;
        uint256 oraclePrecision = 1e5;
        uint8 oracleDecimals = 5;

        uint256 value = 15e18; // 15 value asset units
        uint256 oracleRate = 5e5; // 5 value units per asset unit
        uint256 expectedQuoteAmount = 3e7; // 3 quote units

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(oracleDecimals);
        mockAggregator.setRate(oracleRate);
        mockAggregator.setTimestamp(block.timestamp);

        uint256 quoteAmount = valueHelpersLib.exposed_convertFromValueAssetWithAggregatorV3({
            _value: value,
            _quotePrecision: quotePrecision,
            _oracle: address(mockAggregator),
            _oraclePrecision: oraclePrecision,
            _oracleTimestampTolerance: 0,
            _oracleQuotedInValueAsset: true
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }

    function test_convertWithAggregatorV3_success_rateQuotedInBase() public {
        // Use different precisions for all
        uint256 basePrecision = 1e18;
        uint256 quotePrecision = 1e7;
        uint256 oraclePrecision = 1e5;
        uint8 oracleDecimals = 5;

        uint256 baseAmount = 15e18; // 15 base units
        uint256 oracleRate = 5e5; // 5 base units per quote unit
        uint256 expectedQuoteAmount = 3e7; // 3 quote units

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(oracleDecimals);
        mockAggregator.setRate(oracleRate);
        mockAggregator.setTimestamp(block.timestamp);

        uint256 quoteAmount = valueHelpersLib.exposed_convertWithAggregatorV3({
            _baseAmount: baseAmount,
            _basePrecision: basePrecision,
            _quotePrecision: quotePrecision,
            _oracle: address(mockAggregator),
            _oraclePrecision: oraclePrecision,
            _oracleTimestampTolerance: 0,
            _oracleQuotedInBase: true
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }

    function test_convertWithAggregatorV3_success_rateQuotedInQuote() public {
        // Use different precisions for all
        uint256 basePrecision = 1e18;
        uint256 quotePrecision = 1e7;
        uint256 oraclePrecision = 1e5;
        uint8 oracleDecimals = 5;

        uint256 baseAmount = 3e18; // 3 base units
        uint256 oracleRate = 5e5; // 5 quote units per base unit
        uint256 expectedQuoteAmount = 15e7; // 15 quote units

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(oracleDecimals);
        mockAggregator.setRate(oracleRate);
        mockAggregator.setTimestamp(block.timestamp);

        uint256 quoteAmount = valueHelpersLib.exposed_convertWithAggregatorV3({
            _baseAmount: baseAmount,
            _basePrecision: basePrecision,
            _quotePrecision: quotePrecision,
            _oracle: address(mockAggregator),
            _oraclePrecision: oraclePrecision,
            _oracleTimestampTolerance: 0,
            _oracleQuotedInBase: false
        });

        assertEq(quoteAmount, expectedQuoteAmount);
    }

    function test_parseValidatedRateFromAggregatorV3_fail_answerNotPositive() public {
        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(8);
        int256 answer = 0;
        mockAggregator.setRate(uint256(answer));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValueHelpersLib.ValueHelpersLib__ParseValidatedRateFromAggregatorV3__InvalidAnswer.selector, answer
            )
        );

        valueHelpersLib.exposed_parseValidatedRateFromAggregatorV3({
            _aggregator: address(mockAggregator),
            _timestampTolerance: block.timestamp // effectively unlimited
        });
    }

    function test_parseValidatedRateFromAggregatorV3_fail_minTimestampNotMet() public {
        uint256 currentTime = 456;
        uint256 timestampTolerance = 5;
        // One second outside of tolerance limit
        uint256 oracleTimestamp = 450;

        vm.warp(currentTime);

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(8);
        mockAggregator.setRate(1);
        mockAggregator.setTimestamp(oracleTimestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValueHelpersLib.ValueHelpersLib__ParseValidatedRateFromAggregatorV3__MinTimestampNotMet.selector,
                oracleTimestamp
            )
        );

        valueHelpersLib.exposed_parseValidatedRateFromAggregatorV3({
            _aggregator: address(mockAggregator), _timestampTolerance: timestampTolerance
        });
    }

    function test_parseValidatedRateFromAggregatorV3_success() public {
        uint256 rate = 123;
        uint8 decimals = 8;

        uint256 currentTime = 456;
        uint256 timestampTolerance = 5;
        // Exact tolerance limit
        uint256 oracleTimestamp = 451;

        vm.warp(currentTime);

        MockChainlinkAggregator mockAggregator = new MockChainlinkAggregator(decimals);
        mockAggregator.setRate(rate);
        mockAggregator.setTimestamp(oracleTimestamp);

        assertEq(
            valueHelpersLib.exposed_parseValidatedRateFromAggregatorV3({
                _aggregator: address(mockAggregator), _timestampTolerance: timestampTolerance
            }),
            rate
        );
    }
}
