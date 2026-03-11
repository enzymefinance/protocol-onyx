// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";
import {AddressListBaseHarness} from "test/harnesses/AddressListBaseHarness.sol";

contract AddressListBaseTest is Test {
    AddressListBaseHarness addressList;
    address authAccount;

    function setUp() public {
        addressList = new AddressListBaseHarness();

        authAccount = makeAddr("authAccount");
        addressList.setAuthAccount(authAccount);
    }

    //==================================================================================================================
    // addToList
    //==================================================================================================================

    function test_addToList_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address item = makeAddr("item");
        address[] memory items = new address[](1);
        items[0] = item;

        vm.expectRevert(AddressListBase.AddressList__Unauthorized.selector);

        vm.prank(randomUser);
        addressList.addToList(items);
    }

    function test_addToList_fail_alreadyInList() public {
        address item = makeAddr("item");
        address[] memory items = new address[](1);
        items[0] = item;

        vm.prank(authAccount);
        addressList.addToList(items);

        vm.expectRevert(AddressListBase.AddressList__AddToList__ItemAlreadyInList.selector);

        vm.prank(authAccount);
        addressList.addToList(items);
    }

    function test_addToList_success_multipleItems() public {
        address item1 = makeAddr("item1");
        address item2 = makeAddr("item2");
        address[] memory items = new address[](2);
        items[0] = item1;
        items[1] = item2;

        assertFalse(addressList.isInList(item1), "item1 should NOT be in list before adding");
        assertFalse(addressList.isInList(item2), "item2 should NOT be in list before adding");

        vm.expectEmit(address(addressList));
        emit AddressListBase.ItemAdded(item1);

        vm.expectEmit(address(addressList));
        emit AddressListBase.ItemAdded(item2);

        vm.prank(authAccount);
        addressList.addToList(items);

        assertTrue(addressList.isInList(item1), "item1 should be in list");
        assertTrue(addressList.isInList(item2), "item2 should be in list");
    }

    //==================================================================================================================
    // removeFromList
    //==================================================================================================================

    function test_removeFromList_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address item = makeAddr("item");
        address[] memory items = new address[](1);
        items[0] = item;

        vm.expectRevert(AddressListBase.AddressList__Unauthorized.selector);

        vm.prank(randomUser);
        addressList.removeFromList(items);
    }

    function test_removeFromList_fail_notInList() public {
        address item = makeAddr("item");
        address[] memory items = new address[](1);
        items[0] = item;

        vm.expectRevert(AddressListBase.AddressList__RemoveFromList__ItemNotInList.selector);

        vm.prank(authAccount);
        addressList.removeFromList(items);
    }

    function test_removeFromList_success_multipleItems() public {
        address item1 = makeAddr("item1");
        address item2 = makeAddr("item2");
        address item3 = makeAddr("item3");
        address[] memory itemsToAdd = new address[](3);
        itemsToAdd[0] = item1;
        itemsToAdd[1] = item2;
        itemsToAdd[2] = item3;

        // First add the items
        vm.prank(authAccount);
        addressList.addToList(itemsToAdd);

        // Then remove some of the items

        vm.expectEmit(address(addressList));
        emit AddressListBase.ItemRemoved(item1);

        vm.expectEmit(address(addressList));
        emit AddressListBase.ItemRemoved(item3);

        address[] memory itemsToRemove = new address[](2);
        itemsToRemove[0] = item1;
        itemsToRemove[1] = item3;

        vm.prank(authAccount);
        addressList.removeFromList(itemsToRemove);

        // No longer in list
        assertFalse(addressList.isInList(item1), "item1 should NOT be in list after removing");
        assertFalse(addressList.isInList(item3), "item3 should NOT be in list after removing");

        // Still in list
        assertTrue(addressList.isInList(item2), "item2 should be in list after removing");
    }
}
