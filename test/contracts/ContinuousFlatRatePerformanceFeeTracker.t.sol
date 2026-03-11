// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {FeeTrackerHelpersMixin} from "src/components/fees/utils/FeeTrackerHelpersMixin.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";
import {VALUE_ASSET_PRECISION, ONE_HUNDRED_PERCENT_BPS, SECONDS_IN_YEAR} from "src/utils/Constants.sol";

import {
    ContinuousFlatRatePerformanceFeeTrackerHarness
} from "test/harnesses/ContinuousFlatRatePerformanceFeeTrackerHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ContinuousFlatRatePerformanceFeeTrackerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address mockFeeHandler = makeAddr("mockFeeHandler");

    ContinuousFlatRatePerformanceFeeTrackerHarness performanceFeeTracker;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Set fee handler on Shares
        vm.prank(admin);
        shares.setFeeHandler(mockFeeHandler);

        performanceFeeTracker = new ContinuousFlatRatePerformanceFeeTrackerHarness({_shares: address(shares)});
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    function test_adjustHighWaterMark_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.adjustHighWaterMark({_hwm: 1e18, _timestamp: 1000});
    }

    function test_adjustHighWaterMark_fail_highWaterMarkIsZero() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__HighWaterMarkIsZero
                .selector
        );

        vm.prank(admin);
        performanceFeeTracker.adjustHighWaterMark({_hwm: 0, _timestamp: 1000});
    }

    function test_adjustHighWaterMark_fail_timestampInFuture() public {
        uint256 futureTimestamp = block.timestamp + 1 days;

        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampInFuture
                .selector
        );

        vm.prank(admin);
        performanceFeeTracker.adjustHighWaterMark({_hwm: 1e18, _timestamp: futureTimestamp});
    }

    function test_adjustHighWaterMark_fail_timestampIsZero() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__AdjustHighWaterMark__TimestampIsZero
                .selector
        );

        vm.prank(admin);
        performanceFeeTracker.adjustHighWaterMark({_hwm: 1e18, _timestamp: 0});
    }

    function test_adjustHighWaterMark_success() public {
        uint256 hwm = 1.5e18;
        // Set a reasonable block timestamp first
        vm.warp(2 days);
        uint256 timestamp = block.timestamp - 10; // Use a timestamp in the past

        vm.expectEmit();
        emit ContinuousFlatRatePerformanceFeeTracker.HighWaterMarkAdjusted({highWaterMark: hwm, timestamp: timestamp});

        vm.prank(admin);
        performanceFeeTracker.adjustHighWaterMark({_hwm: hwm, _timestamp: timestamp});

        assertEq(performanceFeeTracker.getHighWaterMark(), hwm, "incorrect hwm");
        assertEq(performanceFeeTracker.getHighWaterMarkTimestamp(), timestamp, "incorrect hwm timestamp");
    }

    function test_resetHighWaterMark_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.resetHighWaterMark();
    }

    function test_resetHighWaterMark_success() public {
        uint256 sharePrice = 123;
        uint256 sharePriceTimestamp = 123456;
        shares_mockSharePrice({_shares: address(shares), _sharePrice: sharePrice, _timestamp: sharePriceTimestamp});

        uint256 hwmTimestamp = sharePriceTimestamp + 555;
        vm.warp(hwmTimestamp);

        vm.expectEmit();
        emit ContinuousFlatRatePerformanceFeeTracker.HighWaterMarkUpdated({highWaterMark: sharePrice});

        vm.prank(admin);
        performanceFeeTracker.resetHighWaterMark();

        assertEq(performanceFeeTracker.getHighWaterMark(), sharePrice, "incorrect reset hwm");
        assertEq(performanceFeeTracker.getHighWaterMarkTimestamp(), hwmTimestamp, "incorrect reset hwm timestamp");
    }

    function test_setHurdleRate_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.setHurdleRate(100);
    }

    function test_setHurdleRate_fail_lessThanMin() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__SetHurdleRate__LessThanMin
                .selector
        );

        vm.prank(admin);
        performanceFeeTracker.setHurdleRate(-1);
    }

    function test_setHurdleRate_success_zero() public {
        __test_setHurdleRate_success({_rate: 0});
    }

    function test_setHurdleRate_success_positive() public {
        __test_setHurdleRate_success({_rate: 500}); // 5%
    }

    function __test_setHurdleRate_success(int16 _rate) internal {
        vm.expectEmit();
        emit ContinuousFlatRatePerformanceFeeTracker.HurdleRateSet({hurdleRate: _rate});

        vm.prank(admin);
        performanceFeeTracker.setHurdleRate(_rate);

        assertEq(performanceFeeTracker.getHurdleRate(), _rate, "incorrect hurdle rate");
    }

    function test_setRate_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.setRate(1);
    }

    function test_setRate_success() public {
        uint16 rate = 123;

        vm.expectEmit();
        emit ContinuousFlatRatePerformanceFeeTracker.RateSet({rate: rate});

        vm.prank(admin);
        performanceFeeTracker.setRate(rate);

        assertEq(performanceFeeTracker.getRate(), rate, "incorrect rate");
    }

    //==================================================================================================================
    // Settlement
    //==================================================================================================================

    function test_calcHurdleAdjustedHwm_fail_zeroHurdleRate() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__CalcHurdleAdjustedHwm__NoHurdleRate
                .selector
        );

        performanceFeeTracker.exposed_calcHurdleAdjustedHwm({_hwm: 1e18, _hwmTimestamp: 123, _hurdleRate: 0});
    }

    function test_calcHurdleAdjustedHwm_fail_negativeHurdleRate() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__CalcHurdleAdjustedHwm__NoHurdleRate
                .selector
        );

        performanceFeeTracker.exposed_calcHurdleAdjustedHwm({_hwm: 1e18, _hwmTimestamp: 123, _hurdleRate: -100});
    }

    function test_calcHurdleAdjustedHwm_success_zeroTimeElapsed() public {
        __test_calcHurdleAdjustedHwm_success({
            _hwm: 3e18,
            _elapsedTime: 0,
            _hurdleRate: 500, // 5%
            _expectedHurdleAdjustedHwm: 3e18 // No time elapsed, so hurdle-adjusted HWM should equal HWM
        });
    }

    function test_calcHurdleAdjustedHwm_success_halfYear() public {
        __test_calcHurdleAdjustedHwm_success({
            _hwm: 3e18,
            _elapsedTime: SECONDS_IN_YEAR / 2,
            _hurdleRate: 1_000, // 10%
            _expectedHurdleAdjustedHwm: 3.15e18 // After 0.5 year with 10% hurdle rate: 3e18 * 1.05 = 3.15e18
        });
    }

    function __test_calcHurdleAdjustedHwm_success(
        uint256 _hwm,
        uint256 _elapsedTime,
        int16 _hurdleRate,
        uint256 _expectedHurdleAdjustedHwm
    ) internal {
        // Define an arbitrary initial hwm timestamp
        uint256 hwmTimestamp = 1_000_000;

        // Warp forward to the final timestamp
        vm.warp(hwmTimestamp + _elapsedTime);

        // Call the exposed function to calculate hurdle-adjusted HWM
        uint256 hurdleAdjustedHwm = performanceFeeTracker.exposed_calcHurdleAdjustedHwm({
            _hwm: _hwm, _hwmTimestamp: hwmTimestamp, _hurdleRate: _hurdleRate
        });

        // Assert the result matches the expected value
        assertEq(hurdleAdjustedHwm, _expectedHurdleAdjustedHwm, "incorrect hurdle adjusted hwm");
    }

    function test_settlePerformanceFee_fail_onlyFeeHandler() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(FeeTrackerHelpersMixin.FeeTrackerHelpersMixin__OnlyFeeHandler__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.settlePerformanceFee({_netValue: 0});
    }

    function test_settlePerformanceFee_fail_noHwm() public {
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkNotInitialized
                .selector
        );

        vm.prank(mockFeeHandler);
        performanceFeeTracker.settlePerformanceFee({_netValue: 0});
    }

    function test_settlePerformanceFee_fail_hurdleRateSetButTimestampIsZero() public {
        // Manually set HWM without timestamp (simulating legacy state)
        performanceFeeTracker.exposed_storage_highWaterMark_set(123);

        // Set hurdle rate
        vm.prank(admin);
        performanceFeeTracker.setHurdleRate(500); // 5%

        // Expect revert when settling with non-zero hurdle rate but zero timestamp
        vm.expectRevert(
            ContinuousFlatRatePerformanceFeeTracker.ContinuousFlatRatePerformanceFeeTracker__SettlePerformanceFee__HighWaterMarkTimestampIsZero
                .selector
        );

        vm.prank(mockFeeHandler);
        performanceFeeTracker.settlePerformanceFee({_netValue: 1000});
    }

    function test_settlePerformanceFee_success_noSharesSupply() public {
        uint256 defaultSharePrice = 12345678;

        // Set valuation handler with default share price
        address valuationHandler = makeAddr("valuationHandler");
        valuationHandler_mockGetDefaultSharePrice({
            _valuationHandler: valuationHandler, _defaultSharePrice: defaultSharePrice
        });
        vm.prank(admin);
        shares.setValuationHandler(valuationHandler);

        // expect: default share price as hwm, no value due
        __test_settlePerformanceFee_success({
            _rate: 100, // unused
            _hurdleRate: 500, // unused
            _initialHwm: defaultSharePrice * 11, // must be different from default share price
            _netValue: 123, // unused
            _sharesSupply: 0,
            _timeElapsed: 123456, // unused
            _expectedHwm: defaultSharePrice,
            _expectedValueDue: 0
        });
    }

    function test_settlePerformanceFee_success_noHurdleRate_belowHwm() public {
        uint16 rate = 1_000; // 10%
        int16 hurdleRate = 0; // NO HURDLE
        uint256 timeElapsed = 1; // unused

        // Report minor share price decrease
        uint256 initialHwm = 1e18;
        uint256 netValue = 9_900;
        uint256 sharesSupply = 10_000;
        // finalValuePerShare = 0.99e18;

        // expect: same hwm, no value due
        __test_settlePerformanceFee_success({
            _rate: rate,
            _hurdleRate: hurdleRate,
            _initialHwm: initialHwm,
            _netValue: netValue,
            _sharesSupply: sharesSupply,
            _timeElapsed: timeElapsed,
            _expectedHwm: initialHwm,
            _expectedValueDue: 0
        });
    }

    function test_settlePerformanceFee_success_positiveHurdleRate_belowHwm() public {
        uint16 rate = 1_000; // 10%
        int16 hurdleRate = 500; // 5%
        uint256 timeElapsed = SECONDS_IN_YEAR;

        // Report share price increase, but below the hurdle-adjusted HWM
        uint256 initialHwm = 1e18;
        uint256 netValue = 10_499;
        uint256 sharesSupply = 10_000;
        // finalValuePerShare = 1.0499e18;

        // expect: same hwm, no value due
        __test_settlePerformanceFee_success({
            _rate: rate,
            _hurdleRate: hurdleRate,
            _initialHwm: initialHwm,
            _netValue: netValue,
            _sharesSupply: sharesSupply,
            _timeElapsed: timeElapsed,
            _expectedHwm: initialHwm,
            _expectedValueDue: 0
        });
    }

    function test_settlePerformanceFee_success_noHurdleRate_aboveHwm() public {
        uint16 rate = 1_000; // 10%
        int16 hurdleRate = 0; // NO HURDLE
        uint256 timeElapsed = 1; // unused

        // Report share price increase
        uint256 initialHwm = 1e18;
        uint256 netValue = 30_000;
        uint256 sharesSupply = 10_000;
        // valuePerShare = 3e18;

        // value due = 20,000 value increase * 10% = 2,000
        uint256 expectedValueDue = 2_000;

        // valueDuePerShare = 0.2e18; // valueDue / sharesSupply in shares precision
        uint256 expectedHwm = 2.8e18; // valuePerShare - valueDuePerShare;

        __test_settlePerformanceFee_success({
            _rate: rate,
            _hurdleRate: hurdleRate,
            _initialHwm: initialHwm,
            _netValue: netValue,
            _sharesSupply: sharesSupply,
            _timeElapsed: timeElapsed,
            _expectedHwm: expectedHwm,
            _expectedValueDue: expectedValueDue
        });
    }

    function test_settlePerformanceFee_success_positiveHurdleRate_aboveHwm() public {
        uint16 rate = 2_000; // 20%
        int16 hurdleRate = 500; // 5%
        uint256 timeElapsed = SECONDS_IN_YEAR; // 1 year for hurdle calculation

        // Report share price increase
        uint256 initialHwm = 1e18;
        uint256 netValue = 30_000;
        uint256 sharesSupply = 10_000;
        // valuePerShare = 3e18;

        // With 5% hurdle rate over 1 year, hurdle-adjusted HWM = 1.05e18
        // Gain above hurdle = 3e18 - 1.05e18 = 1.95e18 per share
        // Total gain above hurdle = 1.95e18 * 10,000 / 1e18 = 19,500
        // value due = 19,500 * 20% = 3,900
        uint256 expectedValueDue = 3_900;

        // valueDuePerShare = 3,900 * 1e18 / 10,000 = 0.39e18
        // expectedHwm = valuePerShare - valueDuePerShare = 3e18 - 0.39e18 = 2.61e18
        uint256 expectedHwm = 2.61e18;

        __test_settlePerformanceFee_success({
            _rate: rate,
            _hurdleRate: hurdleRate,
            _initialHwm: initialHwm,
            _netValue: netValue,
            _sharesSupply: sharesSupply,
            _timeElapsed: timeElapsed,
            _expectedHwm: expectedHwm,
            _expectedValueDue: expectedValueDue
        });
    }

    function __test_settlePerformanceFee_success(
        uint16 _rate,
        int16 _hurdleRate,
        uint256 _initialHwm,
        uint256 _netValue,
        uint256 _sharesSupply,
        uint256 _timeElapsed,
        uint256 _expectedHwm,
        uint256 _expectedValueDue
    ) internal {
        // Define an arbitrary initial hwm timestamp
        uint256 initialHwmTimestamp = 123456;
        uint256 finalBlockTimestamp = initialHwmTimestamp + _timeElapsed;

        // Set performance fee rate
        vm.prank(admin);
        performanceFeeTracker.setRate(_rate);

        // Set hurdle rate
        vm.prank(admin);
        performanceFeeTracker.setHurdleRate(_hurdleRate);

        // Warp to initial timestamp
        vm.warp(initialHwmTimestamp);

        // Set initial HWM
        vm.prank(admin);
        performanceFeeTracker.adjustHighWaterMark({_hwm: _initialHwm, _timestamp: initialHwmTimestamp});

        // Warp forward to the final timestamp
        vm.warp(finalBlockTimestamp);

        // Set shares supply (part of updating share value)
        increaseSharesSupply({_shares: address(shares), _increaseAmount: _sharesSupply});

        if (_initialHwm != _expectedHwm) {
            vm.expectEmit();
            emit ContinuousFlatRatePerformanceFeeTracker.HighWaterMarkUpdated({highWaterMark: _expectedHwm});
        }

        if (_expectedValueDue > 0) {
            vm.expectEmit();
            emit ContinuousFlatRatePerformanceFeeTracker.Settled({valueDue: _expectedValueDue});
        }

        vm.prank(mockFeeHandler);
        uint256 valueDue = performanceFeeTracker.settlePerformanceFee({_netValue: _netValue});

        assertEq(valueDue, _expectedValueDue, "incorrect value due");
        assertEq(performanceFeeTracker.getHighWaterMark(), _expectedHwm, "incorrect final hwm");
        assertEq(
            performanceFeeTracker.getHighWaterMarkTimestamp(),
            _initialHwm == _expectedHwm ? initialHwmTimestamp : finalBlockTimestamp,
            "incorrect final hwm timestamp"
        );
    }
}
