// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {OpenAccessLimitedCallForwarder} from "src/components/roles/OpenAccessLimitedCallForwarder.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

import {OpenAccessLimitedCallForwarderHarness} from "test/harnesses/OpenAccessLimitedCallForwarderHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract OpenAccessLimitedCallForwarderTest is TestHelpers {
    Shares shares;
    address owner;

    OpenAccessLimitedCallForwarderHarness callForwarder;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        callForwarder = new OpenAccessLimitedCallForwarderHarness({_shares: address(shares)});
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function test_addCall_fail_alreadyRegistered() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        vm.prank(owner);
        callForwarder.addCall({_target: target, _selector: selector});

        vm.expectRevert(OpenAccessLimitedCallForwarder.OpenAccessLimitedCallForwarder__AddCall__AlreadyAdded.selector);

        // fails upon adding the same call
        vm.prank(owner);
        callForwarder.addCall({_target: target, _selector: selector});
    }

    function test_addCall_fail_unauthorized() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        callForwarder.addCall({_target: target, _selector: selector});
    }

    function test_addCall_success() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        assertFalse(callForwarder.canCall({_target: target, _selector: selector}));

        vm.expectEmit();
        emit OpenAccessLimitedCallForwarder.CallAdded({target: target, selector: selector});

        vm.prank(owner);
        callForwarder.addCall({_target: target, _selector: selector});

        assertTrue(callForwarder.canCall({_target: target, _selector: selector}));
    }

    function test_removeCall_fail_notRegistered() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        vm.expectRevert(OpenAccessLimitedCallForwarder.OpenAccessLimitedCallForwarder__RemoveCall__NotAdded.selector);

        vm.prank(owner);
        callForwarder.removeCall({_target: target, _selector: selector});
    }

    function test_removeCall_fail_unauthorized() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        callForwarder.removeCall({_target: target, _selector: selector});
    }

    function test_removeCall_success() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        vm.prank(owner);
        callForwarder.addCall({_target: target, _selector: selector});

        assertTrue(callForwarder.canCall({_target: target, _selector: selector}));

        vm.expectEmit();
        emit OpenAccessLimitedCallForwarder.CallRemoved({target: target, selector: selector});

        vm.prank(owner);
        callForwarder.removeCall({_target: target, _selector: selector});

        assertFalse(callForwarder.canCall({_target: target, _selector: selector}));
    }

    //==================================================================================================================
    // Calls
    //==================================================================================================================

    function test_executeCalls_fail_unregisteredCall() public {
        address target = makeAddr("target");
        bytes4 selector = CallTarget.foo.selector;

        // do not register call
        OpenAccessLimitedCallForwarder.Call[] memory calls = new OpenAccessLimitedCallForwarder.Call[](1);
        calls[0] =
            OpenAccessLimitedCallForwarder.Call({target: target, data: abi.encodeWithSelector(selector), value: 0});

        vm.expectRevert(
            OpenAccessLimitedCallForwarder.OpenAccessLimitedCallForwarder__ExecuteCall__UnauthorizedCall.selector
        );

        callForwarder.executeCalls(calls);
    }

    function test_executeCalls_success() public {
        address caller = makeAddr("caller");

        CallTarget callTarget1 = new CallTarget();
        CallTarget callTarget2 = new CallTarget();

        // register calls
        vm.startPrank(owner);
        callForwarder.addCall({_target: address(callTarget1), _selector: CallTarget.foo.selector});
        callForwarder.addCall({_target: address(callTarget2), _selector: CallTarget.foo.selector});
        vm.stopPrank();

        // define call values
        uint256 bar1 = 123;
        uint256 bar2 = 456;
        bytes memory callData1 = abi.encodeWithSelector(CallTarget.foo.selector, bar1);
        bytes memory callData2 = abi.encodeWithSelector(CallTarget.foo.selector, bar2);
        uint256 value1 = 100;
        uint256 value2 = 300;
        uint256 msgValue = value1 + value2;

        // prepare calls
        OpenAccessLimitedCallForwarder.Call[] memory calls = new OpenAccessLimitedCallForwarder.Call[](2);
        calls[0] = OpenAccessLimitedCallForwarder.Call({target: address(callTarget1), data: callData1, value: value1});
        calls[1] = OpenAccessLimitedCallForwarder.Call({target: address(callTarget2), data: callData2, value: value2});

        // seed caller with native asset
        vm.deal(caller, msgValue);

        // pre-assert events
        vm.expectEmit();
        emit OpenAccessLimitedCallForwarder.CallExecuted({
            sender: caller, target: address(callTarget1), data: callData1, value: value1
        });

        vm.expectEmit();
        emit OpenAccessLimitedCallForwarder.CallExecuted({
            sender: caller, target: address(callTarget2), data: callData2, value: value2
        });

        // call
        vm.prank(caller);
        bytes[] memory returnData = callForwarder.executeCalls{value: msgValue}(calls);

        // verify return values
        assertEq(returnData.length, 2);
        assertEq(abi.decode(returnData[0], (uint256)), callTarget1.expectedFooReturnValue({_bar: bar1}));
        assertEq(abi.decode(returnData[1], (uint256)), callTarget2.expectedFooReturnValue({_bar: bar2}));

        // verify state
        assertEq(callTarget1.bar(), bar1);
        assertEq(callTarget2.bar(), bar2);

        // verify value forwarded
        assertEq(address(callTarget1).balance, value1);
        assertEq(address(callTarget2).balance, value2);
    }
}

contract CallTarget {
    uint256 public bar;

    function foo(uint256 _bar) external payable returns (uint256 doubleBar_) {
        bar = _bar;

        return expectedFooReturnValue(_bar);
    }

    function expectedFooReturnValue(uint256 _bar) public pure returns (uint256) {
        return _bar * 3;
    }
}
