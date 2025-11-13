// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    ContinuousFlatRatePerformanceFeeTracker
} from "src/components/fees/performance-fee-trackers/ContinuousFlatRatePerformanceFeeTracker.sol";
import {FeeTrackerHelpersMixin} from "src/components/fees/utils/FeeTrackerHelpersMixin.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";
import {VALUE_ASSET_PRECISION, ONE_HUNDRED_PERCENT_BPS} from "src/utils/Constants.sol";

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

    function test_resetHighWaterMark_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        performanceFeeTracker.resetHighWaterMark();
    }

    function test_resetHighWaterMark_success() public {
        uint256 sharePrice = 123;
        shares_mockSharePrice({_shares: address(shares), _sharePrice: sharePrice, _timestamp: block.timestamp});

        vm.prank(admin);
        performanceFeeTracker.resetHighWaterMark();

        assertEq(performanceFeeTracker.getHighWaterMark(), sharePrice);
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

        assertEq(performanceFeeTracker.getRate(), rate);
    }

    //==================================================================================================================
    // Settlement
    //==================================================================================================================

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

    function test_settlePerformanceFee_success_noSharesSupply() public {
        uint256 defaultSharePrice = 12345678;

        // Set valuation handler with default share price
        address valuationHandler = makeAddr("valuationHandler");
        valuationHandler_mockGetDefaultSharePrice({
            _valuationHandler: valuationHandler, _defaultSharePrice: defaultSharePrice
        });
        vm.prank(admin);
        shares.setValuationHandler(valuationHandler);

        // Give initial HWM that is not default value
        uint256 initialSharePrice = VALUE_ASSET_PRECISION * 11;
        shares_mockSharePrice({_shares: address(shares), _sharePrice: initialSharePrice, _timestamp: block.timestamp});
        vm.prank(admin);
        performanceFeeTracker.resetHighWaterMark();
        assertEq(performanceFeeTracker.getHighWaterMark(), initialSharePrice);

        __test_settlePerformanceFee_success({
            _rate: 100, // unused
            _netValue: 123, // unused
            _expectedHwm: defaultSharePrice,
            _expectedValueDue: 0
        });
    }

    function test_settlePerformanceFee_success_belowHwm() public {
        // Give initial HWM of 1e18
        shares_mockSharePrice({
            _shares: address(shares), _sharePrice: VALUE_ASSET_PRECISION, _timestamp: block.timestamp
        });
        vm.prank(admin);
        performanceFeeTracker.resetHighWaterMark();
        uint256 initialHwm = performanceFeeTracker.getHighWaterMark();
        assertEq(initialHwm, VALUE_ASSET_PRECISION);

        // Report share price decrease
        uint256 netValue = 5_000;
        uint256 sharesSupply = 10_000;
        // valuePerShare = 0.5e18;

        increaseSharesSupply({_shares: address(shares), _increaseAmount: sharesSupply});

        // expect: same hwm, no value due
        __test_settlePerformanceFee_success({
            _rate: 1_000, // 10%
            _netValue: netValue,
            _expectedHwm: initialHwm,
            _expectedValueDue: 0
        });
    }

    function test_settlePerformanceFee_success_aboveHwm() public {
        // Give initial HWM of 1e18
        shares_mockSharePrice({
            _shares: address(shares), _sharePrice: VALUE_ASSET_PRECISION, _timestamp: block.timestamp
        });
        vm.prank(admin);
        performanceFeeTracker.resetHighWaterMark();
        uint256 initialHwm = performanceFeeTracker.getHighWaterMark();
        assertEq(initialHwm, VALUE_ASSET_PRECISION);

        // Report share price increase
        uint256 netValue = 30_000;
        uint256 sharesSupply = 10_000;
        // valuePerShare = 3e18;
        uint16 rate = 1_000; // 10%
        // value due = 20,000 value increase * 10% = 2,000
        uint256 expectedValueDue = 2_000;
        // valueDuePerShare = 0.2e18; // valueDue / sharesSupply in shares precision
        uint256 expectedHwm = 2.8e18; // valuePerShare - valueDuePerShare;

        increaseSharesSupply({_shares: address(shares), _increaseAmount: sharesSupply});

        __test_settlePerformanceFee_success({
            _rate: rate, _netValue: netValue, _expectedHwm: expectedHwm, _expectedValueDue: expectedValueDue
        });
    }

    function __test_settlePerformanceFee_success(
        uint16 _rate,
        uint256 _netValue,
        uint256 _expectedHwm,
        uint256 _expectedValueDue
    ) internal {
        uint256 lastHwm = performanceFeeTracker.getHighWaterMark();

        vm.prank(admin);
        performanceFeeTracker.setRate(_rate);

        if (lastHwm != _expectedHwm) {
            vm.expectEmit();
            emit ContinuousFlatRatePerformanceFeeTracker.HighWaterMarkUpdated({highWaterMark: _expectedHwm});
        }

        if (_expectedValueDue > 0) {
            vm.expectEmit();
            emit ContinuousFlatRatePerformanceFeeTracker.Settled({valueDue: _expectedValueDue});
        }

        vm.prank(mockFeeHandler);
        uint256 valueDue = performanceFeeTracker.settlePerformanceFee({_netValue: _netValue});

        assertEq(valueDue, _expectedValueDue);
        assertEq(performanceFeeTracker.getHighWaterMark(), _expectedHwm);
    }
}
