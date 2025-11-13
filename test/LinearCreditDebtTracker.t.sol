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

        assertEq(tracker.getLastItemId(), expectedId);
        assertEq(tracker.getItemsCount(), prevItemsCount + 1);
        assertEq(tracker.getItemIds()[expectedIndex], expectedId);

        LinearCreditDebtTracker.Item memory item = tracker.getItem({_id: expectedId});
        assertEq(item.id, expectedId);
        assertEq(item.index, expectedIndex);
        assertEq(item.totalValue, _totalValue);
        assertEq(item.start, _start);
        assertEq(item.duration, _duration);
        assertEq(item.settledValue, 0);
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

        assertEq(tracker.getItemsCount(), 1);

        vm.expectEmit();
        emit LinearCreditDebtTracker.ItemRemoved({id: id});

        vm.prank(admin);
        tracker.removeItem({_id: id});

        assertEq(tracker.getItemsCount(), 0);
        // Item is removed, so id is now 0
        assertEq(tracker.getItem({_id: id}).id, 0);
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

        assertEq(tracker.getItem({_id: firstId}).id, 0);

        // Array order now has final item as first item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2);
        assertEq(itemIds[0], lastId);
        assertEq(itemIds[1], middleId);
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

        assertEq(tracker.getItem({_id: middleId}).id, 0);

        // Array order is preserved, without middle item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2);
        assertEq(itemIds[0], firstId);
        assertEq(itemIds[1], lastId);
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

        assertEq(tracker.getItem({_id: lastId}).id, 0);

        // Array order is preserved, without last item
        uint24[] memory itemIds = tracker.getItemIds();
        assertEq(itemIds.length, 2);
        assertEq(itemIds[0], firstId);
        assertEq(itemIds[1], middleId);
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
        assertEq(item.settledValue, totalSettled);
        // initial values are unchanged
        assertEq(item.totalValue, totalValue);
        assertEq(item.start, start);
        assertEq(item.duration, duration);
        assertEq(item.id, middleId);
    }

    //==================================================================================================================
    // Position value
    //==================================================================================================================

    function test_getPositionValue_success() public {
        uint256 currentTime = 123456;
        vm.warp(currentTime);

        // Add items with settlements:
        // 1. start in the future
        // 2. equally between start and stop
        // 3. stop in the past (i.e., matured)

        int128 futureItemTotalValue = 100;
        int128 futureItemTotalSettled = -400;
        int256 futureItemExpectedValue = -400; // settled value only

        int128 midwayItemTotalValue = 5_000;
        int128 midwayItemTotalSettled = -1_000;
        int256 midwayItemExpectedValue = 1_500; // settled value (-1,000) + linear value at 50% (2,500)

        int128 pastItemTotalValue = -30_000;
        int128 pastItemTotalSettled = 10_000;
        int256 pastItemExpectedValue = -20_000; // settled value + total value

        int256 expectedValue = futureItemExpectedValue + midwayItemExpectedValue + pastItemExpectedValue;

        vm.startPrank(admin);
        uint24 futureItemId = tracker.addItem({
            _totalValue: futureItemTotalValue,
            _start: uint40(currentTime + 1),
            _duration: uint32(1000),
            _description: "test"
        });
        uint24 midwayItemId = tracker.addItem({
            _totalValue: midwayItemTotalValue,
            _start: uint40(currentTime - 10),
            _duration: uint32(20),
            _description: "test"
        });
        uint24 pastItemId = tracker.addItem({
            _totalValue: pastItemTotalValue, _start: uint40(currentTime - 1000), _duration: 999, _description: "test"
        });
        tracker.updateSettledValue({_id: futureItemId, _totalSettled: futureItemTotalSettled});
        tracker.updateSettledValue({_id: midwayItemId, _totalSettled: midwayItemTotalSettled});
        tracker.updateSettledValue({_id: pastItemId, _totalSettled: pastItemTotalSettled});
        vm.stopPrank();

        assertEq(tracker.getPositionValue(), expectedValue);
    }
}
