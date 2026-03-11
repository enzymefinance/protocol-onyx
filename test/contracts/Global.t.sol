// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Global} from "src/global/Global.sol";

contract GlobalTest is Test {
    address owner = makeAddr("owner");

    Global global;

    function setUp() public {
        // Deploy as proxy with first lib
        address lib = address(new Global());
        global = Global(
            address(new ERC1967Proxy({implementation: lib, _data: abi.encodeWithSelector(Global.init.selector, owner)}))
        );
    }

    function test_init_fail_alreadyInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        global.init({_owner: owner});
    }

    function test_init_success() public view {
        assertEq(global.owner(), owner);
    }

    function test_proxy_upgradeToAndCall_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");
        address newGlobalLib = address(new Global());

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, randomUser));
        vm.prank(randomUser);
        global.upgradeToAndCall({newImplementation: newGlobalLib, data: new bytes(0)});
    }

    function test_proxy_upgradeToAndCall_success() public {
        address newGlobalLib = address(new Global());

        vm.prank(owner);
        global.upgradeToAndCall({newImplementation: newGlobalLib, data: new bytes(0)});
    }
}
