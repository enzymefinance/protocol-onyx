// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {BeaconFactory} from "src/factories/BeaconFactory.sol";
import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";
import {Global} from "src/global/Global.sol";

contract MockImplementation {
    bool public initialized;

    function init() external {
        initialized = true;
    }
}

contract BeaconFactoryTest is Test {
    BeaconFactory factory;
    address globalOwner;

    function setUp() public {
        Global global = new Global();
        global.init({_owner: address(this)});
        globalOwner = global.owner();

        factory = new BeaconFactory({_global: address(global)});
    }

    function test_setImplementation_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(GlobalOwnable.GlobalOwnable__OnlyOwner__Unauthorized.selector);

        vm.prank(randomUser);
        factory.setImplementation(address(0));
    }

    function test_setImplementation_success() public {
        address implementation = address(new MockImplementation());

        vm.expectEmit();
        emit BeaconFactory.ImplementationSet(implementation);

        vm.prank(globalOwner);
        factory.setImplementation(implementation);

        assertEq(factory.implementation(), implementation);
    }

    function test_deployProxy_success() public {
        address implementation = address(new MockImplementation());
        bytes memory initData = abi.encodeWithSelector(MockImplementation.init.selector);

        vm.prank(globalOwner);
        factory.setImplementation({_implementation: address(implementation)});

        // Get the proxy address by mock deploying and then reverting
        address proxy;
        {
            uint256 snapshotId = vm.snapshotState();
            proxy = factory.deployProxy({_initData: initData});
            vm.revertToStateAndDelete(snapshotId);
        }

        // Proxy should not yet be a registered instance
        assertEq(factory.isInstance(proxy), false);

        vm.expectEmit(address(factory));
        emit BeaconFactory.ProxyDeployed({proxy: proxy});

        factory.deployProxy({_initData: initData});

        assertEq(factory.isInstance(proxy), true);

        // Asserts: (1) success of init() call, (2) call to proxy uses the implementation
        assertEq(MockImplementation(proxy).initialized(), true);
    }
}
