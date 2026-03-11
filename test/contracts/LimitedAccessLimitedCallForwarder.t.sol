// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {OpenAccessLimitedCallForwarder} from "src/components/roles/OpenAccessLimitedCallForwarder.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

import {LimitedAccessLimitedCallForwarderHarness} from "test/harnesses/LimitedAccessLimitedCallForwarderHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract LimitedAccessLimitedCallForwarderTest is TestHelpers {
    Shares shares;
    address owner;

    LimitedAccessLimitedCallForwarderHarness callForwarder;
    CallTarget callTarget;
    bytes4 callSelector = CallTarget.foo.selector;
    address authCaller = makeAddr("authCaller");

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        callForwarder = new LimitedAccessLimitedCallForwarderHarness({_shares: address(shares)});

        callTarget = new CallTarget();
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_addUser_fail_alreadyRegistered() public {
        vm.prank(owner);
        callForwarder.addUser(authCaller);

        vm.expectRevert(
            LimitedAccessLimitedCallForwarder.LimitedAccessLimitedCallForwarder__AddUser__AlreadyAdded.selector
        );

        // fails upon adding the same call
        vm.prank(owner);
        callForwarder.addUser(authCaller);
    }

    function test_addUser_fail_unauthorized() public {
        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        callForwarder.addUser(authCaller);
    }

    function test_addUser_success() public {
        assertFalse(callForwarder.isUser(authCaller));

        vm.expectEmit();
        emit LimitedAccessLimitedCallForwarder.UserAdded(authCaller);

        vm.prank(owner);
        callForwarder.addUser(authCaller);

        assertTrue(callForwarder.isUser(authCaller));
    }

    function test_removeUser_fail_notRegistered() public {
        vm.expectRevert(
            LimitedAccessLimitedCallForwarder.LimitedAccessLimitedCallForwarder__RemoveUser__NotAdded.selector
        );

        vm.prank(owner);
        callForwarder.removeUser(authCaller);
    }

    function test_removeUser_fail_unauthorized() public {
        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        callForwarder.removeUser(authCaller);
    }

    function test_removeUser_success() public {
        vm.prank(owner);
        callForwarder.addUser(authCaller);

        assertTrue(callForwarder.isUser(authCaller));

        vm.expectEmit();
        emit LimitedAccessLimitedCallForwarder.UserRemoved(authCaller);

        vm.prank(owner);
        callForwarder.removeUser(authCaller);

        assertFalse(callForwarder.isUser(authCaller));
    }

    //==================================================================================================================
    // Calls
    //==================================================================================================================

    function test_executeCalls_fail_unregisteredUser() public {
        // register call
        vm.prank(owner);
        callForwarder.addCall({_target: address(callTarget), _selector: callSelector});

        // do not register user
        OpenAccessLimitedCallForwarder.Call[] memory calls = new OpenAccessLimitedCallForwarder.Call[](1);
        calls[0] = OpenAccessLimitedCallForwarder.Call({
            target: address(callTarget), data: abi.encodeWithSelector(CallTarget.foo.selector), value: 0
        });

        vm.expectRevert(
            LimitedAccessLimitedCallForwarder.LimitedAccessLimitedCallForwarder__ExecuteCall__UnauthorizedUser.selector
        );

        callForwarder.executeCalls(calls);
    }

    function test_executeCalls_success() public {
        assertFalse(callTarget.called());

        // register call
        vm.prank(owner);
        callForwarder.addCall({_target: address(callTarget), _selector: callSelector});

        // register user
        vm.prank(owner);
        callForwarder.addUser(authCaller);

        // prepare calls
        OpenAccessLimitedCallForwarder.Call[] memory calls = new OpenAccessLimitedCallForwarder.Call[](1);
        calls[0] = OpenAccessLimitedCallForwarder.Call({
            target: address(callTarget), data: abi.encodeWithSelector(CallTarget.foo.selector), value: 0
        });

        // call
        vm.prank(authCaller);
        bytes[] memory returnData = callForwarder.executeCalls(calls);

        assertTrue(callTarget.called());
        assertEq(returnData.length, 1);
    }
}

contract CallTarget {
    bool public called;

    function foo() external {
        called = true;
    }
}
