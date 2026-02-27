// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {LinearCreditDebtTracker} from "src/components/value/position-trackers/LinearCreditDebtTracker.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

import {LinearCreditDebtTrackerHarness} from "test/harnesses/LinearCreditDebtTrackerHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract LinearCreditDebtTrackerTest is Test, TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("admin");

    LinearCreditDebtTracker tracker;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        tracker = LinearCreditDebtTracker(address(new LinearCreditDebtTrackerHarness({_shares: address(shares)})));
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    /// @dev Helper to create an item, optionally set settled value, and warp to a timestamp
    function __createItemAndWarp(
        int128 _totalValue,
        uint40 _start,
        uint32 _duration,
        int128 _settledValue,
        uint256 _warpTo
    ) internal returns (uint24 itemId_) {
        vm.startPrank(admin);
        itemId_ =
            tracker.addItem({_totalValue: _totalValue, _start: _start, _duration: _duration, _description: "test"});
        if (_settledValue != 0) {
            tracker.updateSettledValue({_id: itemId_, _totalSettled: _settledValue});
        }
        vm.stopPrank();

        vm.warp(_warpTo);
    }

    //==================================================================================================================
    // Item management (access: Shares admin or owner)
    //==================================================================================================================

    function test_addItem_fail_notAdminOrOwner() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
    }

    function test_addItem_fail_emptyTotalValue() public {
        vm.expectRevert(
            abi.encodeWithSelector(LinearCreditDebtTracker.LinearCreditDebtTracker__AddItem__EmptyTotalValue.selector)
        );

        vm.prank(admin);
        tracker.addItem({_totalValue: 0, _start: 123, _duration: 456, _description: "test"});
    }

    function test_addItem_success() public {
        // positive value
        __test_addItem_success({_totalValue: 100, _start: 123, _duration: 456});
        // negative value
        __test_addItem_success({_totalValue: -100, _start: 123, _duration: 456});
    }

    function __test_addItem_success(int128 _totalValue, uint40 _start, uint32 _duration) internal {
        uint24 expectedId = tracker.getLastItemId() + 1;
        uint24[] memory prevItemIds = tracker.getItemIds();
        uint256 prevItemsCount = prevItemIds.length;
        uint256 expectedIndex = prevItemsCount;
        string memory description = "test";

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemAdded({
            id: expectedId, totalValue: _totalValue, start: _start, duration: _duration, description: description
        });

        vm.prank(admin);
        tracker.addItem({_totalValue: _totalValue, _start: _start, _duration: _duration, _description: description});

        assertEq(tracker.getLastItemId(), expectedId, "incorrect last item id");
        assertEq(tracker.getItemsCount(), prevItemsCount + 1, "incorrect items count");
        assertEq(tracker.getItemIds()[expectedIndex], expectedId, "incorrect item id at index");

        LinearCreditDebtTracker.Item memory item = tracker.getItem({_id: expectedId});
        assertEq(item.id, expectedId, "incorrect item id");
        assertEq(item.index, expectedIndex, "incorrect item index");
        assertEq(item.totalValue, _totalValue, "incorrect item totalValue");
        assertEq(item.start, _start, "incorrect item start");
        assertEq(item.duration, _duration, "incorrect item duration");
        assertEq(item.settledValue, 0, "incorrect item settledValue");
    }

    function test_removeItem_fail_notAdminOrOwner() public {
        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(makeAddr("randomUser"));
        tracker.removeItem({_id: 1});
    }

    function test_removeItem_success_oneItem() public {
        // Add one item
        vm.prank(admin);
        uint24 id = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});

        assertEq(tracker.getItemsCount(), 1, "incorrect items count before removal");

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemRemoved({id: id});

        vm.prank(admin);
        tracker.removeItem({_id: id});

        assertEq(tracker.getItemsCount(), 0, "incorrect items count after removal");
        // Item is removed, so id is now 0
        assertEq(tracker.getItem({_id: id}).id, 0, "removed item id should be 0");
    }

    function test_removeItem_success_firstItem() public {
        // Add a few items
        vm.startPrank(admin);
        uint24 firstId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 middleId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 lastId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        vm.stopPrank();

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemRemoved({id: firstId});

        vm.prank(admin);
        tracker.removeItem({_id: firstId});

        assertEq(tracker.getItem({_id: firstId}).id, 0, "removed item id should be 0");

        // Array order now has final item as first item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2, "incorrect items count");
        assertEq(itemIds[0], lastId, "incorrect id at index 0");
        assertEq(itemIds[1], middleId, "incorrect id at index 1");
    }

    function test_removeItem_success_middleItem() public {
        // Add a few items
        vm.startPrank(admin);
        uint24 firstId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 middleId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 lastId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        vm.stopPrank();

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemRemoved({id: middleId});

        vm.prank(admin);
        tracker.removeItem({_id: middleId});

        assertEq(tracker.getItem({_id: middleId}).id, 0, "removed item id should be 0");

        // Array order is preserved, without middle item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2, "incorrect items count");
        assertEq(itemIds[0], firstId, "incorrect id at index 0");
        assertEq(itemIds[1], lastId, "incorrect id at index 1");
    }

    function test_removeItem_success_lastItem() public {
        // Add a few items
        vm.startPrank(admin);
        uint24 firstId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 middleId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        uint24 lastId = tracker.addItem({_totalValue: 100, _start: 123, _duration: 456, _description: "test"});
        vm.stopPrank();

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemRemoved({id: lastId});

        vm.prank(admin);
        tracker.removeItem({_id: lastId});

        assertEq(tracker.getItem({_id: lastId}).id, 0, "removed item id should be 0");

        // Array order is preserved, without last item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2, "incorrect items count");
        assertEq(itemIds[0], firstId, "incorrect id at index 0");
        assertEq(itemIds[1], middleId, "incorrect id at index 1");
    }

    function test_updateSettledValue_fail_notAdminOrOwner() public {
        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(makeAddr("randomUser"));
        tracker.updateSettledValue({_id: 1, _totalSettled: 100});
    }

    function test_updateSettledValue_success() public {
        int128 totalValue = 100;
        uint40 start = 123;
        uint32 duration = 456;
        int128 totalSettled = 1234;

        // Add a few items
        vm.startPrank(admin);
        tracker.addItem({_totalValue: totalValue, _start: start, _duration: duration, _description: "test"});
        uint24 middleId =
            tracker.addItem({_totalValue: totalValue, _start: start, _duration: duration, _description: "test"});
        tracker.addItem({_totalValue: totalValue, _start: start, _duration: duration, _description: "test"});
        vm.stopPrank();

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemTotalSettledUpdated({id: middleId, totalSettled: totalSettled});

        vm.prank(admin);
        tracker.updateSettledValue({_id: middleId, _totalSettled: totalSettled});

        // Check that the item was updated
        LinearCreditDebtTracker.Item memory item = tracker.getItem({_id: middleId});
        assertEq(item.settledValue, totalSettled, "incorrect settledValue");
        // initial values are unchanged
        assertEq(item.totalValue, totalValue, "totalValue should be unchanged");
        assertEq(item.start, start, "start should be unchanged");
        assertEq(item.duration, duration, "duration should be unchanged");
        assertEq(item.id, middleId, "id should be unchanged");
    }

    //==================================================================================================================
    // Position value
    //==================================================================================================================

    /// @dev Non-existent item returns 0
    function test_calcItemValue_success_nonExistentItem() public view {
        assertEq(tracker.calcItemValue({_id: 999}), 0, "non-existent item should return 0");
    }

    /// @dev Before start: returns settledValue only
    function test_calcItemValue_success_beforeStart() public {
        int128 settledValue = 200;
        uint24 itemId = __createItemAndWarp({
            _totalValue: 1000, _start: 300, _duration: 100, _settledValue: settledValue, _warpTo: 299
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue, "incorrect value");
    }

    /// @dev At exact start: returns settledValue only
    function test_calcItemValue_success_atExactStart_withDuration() public {
        int128 settledValue = 200;
        uint24 itemId = __createItemAndWarp({
            _totalValue: 1000, _start: 300, _duration: 100, _settledValue: settledValue, _warpTo: 300
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue, "incorrect value");
    }

    /// @dev During linear period: returns settledValue + pro-rated totalValue
    function test_calcItemValue_success_duringLinear() public {
        int128 settledValue = 200;
        uint24 itemId = __createItemAndWarp({
            _totalValue: 1000,
            _start: 300,
            _duration: 100,
            _settledValue: settledValue,
            _warpTo: 320 // 20% through
        });

        int128 proRatedValue = 200; // 1000 * 20%
        assertEq(tracker.calcItemValue({_id: itemId}), settledValue + proRatedValue, "incorrect value");
    }

    /// @dev During linear period with negative totalValue (debt)
    function test_calcItemValue_success_duringLinear_negativeTotal() public {
        int128 settledValue = 500;
        uint24 itemId = __createItemAndWarp({
            _totalValue: -1000,
            _start: 300,
            _duration: 100,
            _settledValue: settledValue,
            _warpTo: 320 // 20% through
        });

        int128 proRatedValue = -200; // -1000 * 20%
        assertEq(tracker.calcItemValue({_id: itemId}), settledValue + proRatedValue, "incorrect value");
    }

    /// @dev At exact end: returns settledValue + totalValue
    function test_calcItemValue_success_atExactEnd() public {
        int128 settledValue = 200;
        int128 totalValue = 1000;
        uint24 itemId = __createItemAndWarp({
            _totalValue: totalValue, _start: 300, _duration: 100, _settledValue: settledValue, _warpTo: 400
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue + totalValue, "incorrect value");
    }

    /// @dev After end: returns settledValue + totalValue
    function test_calcItemValue_success_afterEnd() public {
        int128 settledValue = 200;
        int128 totalValue = 1000;
        uint24 itemId = __createItemAndWarp({
            _totalValue: totalValue, _start: 300, _duration: 100, _settledValue: settledValue, _warpTo: 2000
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue + totalValue, "incorrect value");
    }

    /// @dev With duration 0, before start: returns settledValue only
    function test_calcItemValue_success_zeroDuration_beforeStart() public {
        int128 settledValue = 200;
        uint24 itemId = __createItemAndWarp({
            _totalValue: 1000, _start: 300, _duration: 0, _settledValue: settledValue, _warpTo: 299
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue, "incorrect value");
    }

    /// @dev With duration 0, at exact start: returns settledValue only
    function test_calcItemValue_success_zeroDuration_atExactStart() public {
        int128 settledValue = 500;
        uint24 itemId = __createItemAndWarp({
            _totalValue: 1000, _start: 300, _duration: 0, _settledValue: settledValue, _warpTo: 300
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue, "incorrect value");
    }

    /// @dev With duration 0, after start: returns settledValue + totalValue
    function test_calcItemValue_success_zeroDuration_afterEnd() public {
        int128 settledValue = 200;
        int128 totalValue = 1000;
        uint24 itemId = __createItemAndWarp({
            _totalValue: totalValue, _start: 300, _duration: 0, _settledValue: settledValue, _warpTo: 301
        });

        assertEq(tracker.calcItemValue({_id: itemId}), settledValue + totalValue, "incorrect value");
    }

    function __test_getPositionValue_addItems(uint256 _currentTime) private {
        // 1. start in the future
        uint24 futureItemId = tracker.addItem({
            _totalValue: 100, _start: uint40(_currentTime + 1), _duration: uint32(1000), _description: "test"
        });
        tracker.updateSettledValue({_id: futureItemId, _totalSettled: -400});

        // 2. equally between start and stop
        uint24 midwayItemId = tracker.addItem({
            _totalValue: 5_000, _start: uint40(_currentTime - 10), _duration: uint32(20), _description: "test"
        });
        tracker.updateSettledValue({_id: midwayItemId, _totalSettled: -1_000});

        // 3. stop in the past (i.e., matured)
        uint24 pastItemId = tracker.addItem({
            _totalValue: -30_000, _start: uint40(_currentTime - 1000), _duration: 999, _description: "test"
        });
        tracker.updateSettledValue({_id: pastItemId, _totalSettled: 10_000});
    }

    function test_getPositionValue_success() public {
        uint256 currentTime = 123456;
        vm.warp(currentTime);

        // Expected values:
        // future: -400 (settled value only)
        // midway: 1,500 (settled value (-1,000) + linear value at 50% (2,500))
        // past: -20,000 (settled value + total value)
        int256 expectedValue = -400 + 1_500 + (-20_000);

        vm.startPrank(admin);
        __test_getPositionValue_addItems(currentTime);
        vm.stopPrank();

        assertEq(tracker.getPositionValue(), expectedValue, "incorrect total position value");
    }
}
