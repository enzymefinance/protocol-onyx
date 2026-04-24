// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Errors} from "@openzeppelin/contracts/utils/Errors.sol";
import {DeterministicBeaconFactory} from "src/factories/DeterministicBeaconFactory.sol";
import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";
import {Global} from "src/global/Global.sol";

contract MockImplementation {
    bool public initialized;

    function init() external {
        initialized = true;
    }
}

contract DeterministicBeaconFactoryTest is Test {
    DeterministicBeaconFactory factory;
    Global global;
    address globalOwner;
    address mockImpl;
    bytes32 salt = keccak256("test-salt");
    bytes initData = abi.encodeWithSelector(MockImplementation.init.selector);

    function setUp() public {
        globalOwner = makeAddr("globalOwner");
        global = new Global();
        global.init({_owner: globalOwner});

        factory = new DeterministicBeaconFactory({_global: address(global)});
        mockImpl = address(new MockImplementation());
    }

    function test_WhenDeploying() external view {
        // It should set the GLOBAL address.
        assertEq(address(factory.GLOBAL()), address(global), "GLOBAL address mismatch");
    }

    modifier whenCallingSetImplementation() {
        _;
    }

    function test_WhenTheCallerIsNotTheOwner() external whenCallingSetImplementation {
        // It should revert with {GlobalOwnable__OnlyOwner__Unauthorized}.
        address randomUser = makeAddr("randomUser");

        vm.expectRevert({
            revertData: GlobalOwnable.GlobalOwnable__OnlyOwner__Unauthorized.selector, reverter: address(factory)
        });

        vm.prank(randomUser);
        factory.setImplementation(mockImpl);
    }

    function test_WhenTheCallerIsTheOwner() external whenCallingSetImplementation {
        // It should set the implementation address.
        // It should emit a {ImplementationSet} event.
        vm.expectEmit(address(factory));
        emit DeterministicBeaconFactory.ImplementationSet({implementation: mockImpl});

        vm.prank(globalOwner);
        factory.setImplementation(mockImpl);

        assertEq(factory.implementation(), mockImpl, "implementation address mismatch");
    }

    modifier whenCallingDeployProxy() {
        vm.prank(globalOwner);
        factory.setImplementation(mockImpl);
        _;
    }

    function test_RevertGiven_AProxyHasAlreadyBeenDeployedWithTheSameSaltAndInitData() external whenCallingDeployProxy {
        // It should revert.
        factory.deployProxy({_salt: salt, _initData: initData});

        vm.expectRevert({revertData: Errors.FailedDeployment.selector, reverter: address(factory)});

        factory.deployProxy({_salt: salt, _initData: initData});
    }

    function test_GivenNoProxyExistsAtTheDeterministicAddress() external whenCallingDeployProxy {
        // It should deploy a new beacon proxy.
        // It should set isInstance to true for the deployed proxy.
        // It should emit a {ProxyDeployed} event.
        // It should return the proxy address.
        address expectedProxy =
            factory.computeProxyAddress({_deployer: address(this), _salt: salt, _initData: initData});

        vm.expectEmit(address(factory));
        emit DeterministicBeaconFactory.ProxyDeployed({proxy: expectedProxy});

        address proxy = factory.deployProxy({_salt: salt, _initData: initData});

        assertEq(proxy, expectedProxy, "proxy address should match computed address");
        assertTrue(factory.isInstance(proxy), "proxy should be registered as instance");
        assertTrue(MockImplementation(proxy).initialized(), "proxy should be initialized");
    }

    function test_GivenTwoDifferentDeployersUseTheSameSaltAndInitData() external whenCallingDeployProxy {
        // It should produce different proxy addresses.
        address deployer1 = makeAddr("deployer1");
        address deployer2 = makeAddr("deployer2");

        address computed1 = factory.computeProxyAddress({_deployer: deployer1, _salt: salt, _initData: initData});
        address computed2 = factory.computeProxyAddress({_deployer: deployer2, _salt: salt, _initData: initData});

        assertTrue(computed1 != computed2, "different deployers should produce different computed addresses");

        vm.prank(deployer1);
        address deployed1 = factory.deployProxy({_salt: salt, _initData: initData});

        vm.prank(deployer2);
        address deployed2 = factory.deployProxy({_salt: salt, _initData: initData});

        assertEq(deployed1, computed1, "deployer1 deployed address should match computed");
        assertEq(deployed2, computed2, "deployer2 deployed address should match computed");
        assertTrue(deployed1 != deployed2, "deployed addresses should differ");
    }

    function test_WhenCallingComputeProxyAddress() external {
        // It should return the deterministic address for the given salt and init data.
        // It should match the address returned by deployProxy for the same parameters.
        vm.prank(globalOwner);
        factory.setImplementation(mockImpl);

        address computedAddress =
            factory.computeProxyAddress({_deployer: address(this), _salt: salt, _initData: initData});
        address deployedProxy = factory.deployProxy({_salt: salt, _initData: initData});

        assertEq(computedAddress, deployedProxy, "computed address should match deployed proxy address");
    }

    modifier whenCallingIsInstance() {
        _;
    }

    function test_GivenTheAddressIsADeployedProxy() external whenCallingIsInstance {
        // It should return true.
        vm.prank(globalOwner);
        factory.setImplementation(mockImpl);

        address proxy = factory.deployProxy({_salt: salt, _initData: initData});

        assertTrue(factory.isInstance(proxy), "deployed proxy should be an instance");
    }

    function test_GivenTheAddressIsNotADeployedProxy() external whenCallingIsInstance {
        // It should return false.
        address randomAddress = makeAddr("randomAddress");

        assertFalse(factory.isInstance(randomAddress), "random address should not be an instance");
    }
}
