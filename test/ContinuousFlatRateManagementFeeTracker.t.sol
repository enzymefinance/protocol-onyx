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
    ContinuousFlatRateManagementFeeTracker
} from "src/components/fees/management-fee-trackers/ContinuousFlatRateManagementFeeTracker.sol";
import {FeeTrackerHelpersMixin} from "src/components/fees/utils/FeeTrackerHelpersMixin.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";
import {ONE_HUNDRED_PERCENT_BPS, SECONDS_IN_YEAR} from "src/utils/Constants.sol";

import {
    ContinuousFlatRateManagementFeeTrackerHarness
} from "test/harnesses/ContinuousFlatRateManagementFeeTrackerHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ContinuousFlatRateManagementFeeTrackerTest is TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");
    address mockFeeHandler = makeAddr("mockFeeHandler");

    ContinuousFlatRateManagementFeeTrackerHarness managementFeeTracker;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        // Set fee handler on Shares
        vm.prank(admin);
        shares.setFeeHandler(mockFeeHandler);

        managementFeeTracker = new ContinuousFlatRateManagementFeeTrackerHarness({_shares: address(shares)});
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    function test_resetLastSettled_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        managementFeeTracker.resetLastSettled();
    }

    function test_resetLastSettled_success() public {
        uint256 time1 = 123456;
        vm.warp(time1);

        vm.prank(admin);
        managementFeeTracker.resetLastSettled();

        assertEq(managementFeeTracker.getLastSettled(), time1);

        uint256 time2 = time1 + 7;
        vm.warp(time2);

        vm.prank(admin);
        managementFeeTracker.resetLastSettled();

        assertEq(managementFeeTracker.getLastSettled(), time2);
    }

    function test_setRate_fail_onlyAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        managementFeeTracker.setRate(1);
    }

    function test_setRate_success() public {
        uint16 rate = 123;

        vm.expectEmit();
        emit ContinuousFlatRateManagementFeeTracker.RateSet({rate: rate});

        vm.prank(admin);
        managementFeeTracker.setRate(rate);

        assertEq(managementFeeTracker.getRate(), rate);
        assertEq(managementFeeTracker.getLastSettled(), 0);
    }

    //==================================================================================================================
    // Settlement
    //==================================================================================================================

    function test_settleManagementFee_fail_onlyFeeHandler() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(FeeTrackerHelpersMixin.FeeTrackerHelpersMixin__OnlyFeeHandler__Unauthorized.selector);

        vm.prank(randomUser);
        managementFeeTracker.settleManagementFee({_netValue: 0});
    }

    function test_settleManagementFee_fail_noLastSettled() public {
        vm.expectRevert(
            ContinuousFlatRateManagementFeeTracker.ContinuousFlatRateManagementFeeTracker__SettleManagementFee__LastSettledNotInitialized
                .selector
        );

        vm.prank(mockFeeHandler);
        managementFeeTracker.settleManagementFee({_netValue: 0});
    }

    function test_settleManagementFee_success_valueDue() public {
        // Set a 10% rate
        uint16 rate = uint16(ONE_HUNDRED_PERCENT_BPS) / 10;
        vm.prank(admin);
        managementFeeTracker.setRate(rate);

        // Warp to a time for initialization
        uint256 settlementTime1 = 123456;
        vm.warp(settlementTime1);

        vm.prank(admin);
        managementFeeTracker.resetLastSettled();

        // Warp to a time for 2nd settlement
        uint256 netValue = 1000;
        uint256 secondsSinceSettlement = SECONDS_IN_YEAR / 5; // 20% of the yearly rate
        uint256 settlementTime2 = settlementTime1 + secondsSinceSettlement;
        vm.warp(settlementTime2);

        uint256 expectedValueDue = netValue * rate / 5 / ONE_HUNDRED_PERCENT_BPS;

        vm.expectEmit();
        emit ContinuousFlatRateManagementFeeTracker.Settled({valueDue: expectedValueDue});

        vm.prank(mockFeeHandler);
        uint256 valueDue = managementFeeTracker.settleManagementFee({_netValue: netValue});

        assertEq(valueDue, expectedValueDue);
        assertEq(managementFeeTracker.getLastSettled(), settlementTime2);
    }
}
