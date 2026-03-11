// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Shares} from "src/shares/Shares.sol";

import {SharesOwnedAddressListHarness} from "test/harnesses/SharesOwnedAddressListHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract SharesOwnedAddressListTest is TestHelpers {
    Shares shares;
    address owner;
    address admin;

    SharesOwnedAddressListHarness addressList;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        admin = makeAddr("admin");
        vm.prank(owner);
        shares.addAdmin(admin);

        addressList = new SharesOwnedAddressListHarness({_shares: address(shares)});
    }

    //==================================================================================================================
    // isAuth
    //==================================================================================================================

    function test_isAuth_fail_randomUser() public {
        address randomUser = makeAddr("randomUser");
        assertFalse(addressList.isAuth(randomUser), "randomUser should not be authorized");
    }

    function test_isAuth_success_owner() public view {
        assertTrue(addressList.isAuth(owner), "owner should be authorized");
    }

    function test_isAuth_success_admin() public view {
        assertTrue(addressList.isAuth(admin), "admin should be authorized");
    }

    //==================================================================================================================
    // List management
    //==================================================================================================================

    // HANDLED IN AddressListBase.t.sol
}
