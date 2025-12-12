// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";

contract OwnableAddressListTest is Test {
    OwnableAddressList addressList;
    address owner;

    function setUp() public {
        owner = makeAddr("owner");

        addressList = new OwnableAddressList();
        addressList.init({_owner: owner});
    }

    //==================================================================================================================
    // init
    //==================================================================================================================

    function test_init_success() public view {
        assertEq(addressList.owner(), owner, "incorrect owner");
    }

    function test_init_fail_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        addressList.init({_owner: makeAddr("newOwner")});
    }

    //==================================================================================================================
    // isAuth
    //==================================================================================================================

    function test_isAuth_success() public {
        assertTrue(addressList.isAuth(owner), "owner should be authorized");
        assertFalse(addressList.isAuth(makeAddr("randomUser")), "randomUser should not be authorized");
    }

    //==================================================================================================================
    // List management
    //==================================================================================================================

    // HANDLED IN AddressListBase.t.sol
}
