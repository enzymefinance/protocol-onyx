// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";
import {Global} from "src/global/Global.sol";
import {GlobalOwnableHarness} from "test/harnesses/GlobalOwnableHarness.sol";

contract MockImplementation {
    bool public initialized;

    function init() external {
        initialized = true;
    }
}

contract GlobalOwnableTest is Test {
    GlobalOwnableHarness globalOwnable;
    address globalOwner;

    function setUp() public {
        globalOwner = makeAddr("globalOwner");
        Global global = new Global();
        global.init({_owner: globalOwner});

        globalOwnable = new GlobalOwnableHarness({_global: address(global)});
    }

    function test_isOwner_success() public {
        address randomUser = makeAddr("randomUser");

        assertEq(globalOwnable.exposed_isOwner(randomUser), false);
        assertEq(globalOwnable.exposed_isOwner(globalOwner), true);
    }

    function test_onlyOwner_fail_randomUser() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(GlobalOwnable.GlobalOwnable__OnlyOwner__Unauthorized.selector);
        vm.prank(randomUser);
        globalOwnable.modifier_onlyOwner();
    }

    function test_onlyOwner_success() public {
        vm.prank(globalOwner);
        globalOwnable.modifier_onlyOwner();
    }
}
