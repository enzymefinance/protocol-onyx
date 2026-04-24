// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {GlobalOwnable} from "src/global/utils/GlobalOwnable.sol";

/// @title DeterministicBeaconFactory Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A factory contract for deploying beacon proxy instances at deterministic addresses via CREATE2
contract DeterministicBeaconFactory is IBeacon, GlobalOwnable {
    //==================================================================================================================
    // State
    //==================================================================================================================

    address public override implementation;
    mapping(address _who => bool) public isInstance;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event ImplementationSet(address implementation);

    event ProxyDeployed(address proxy);

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(address _global) GlobalOwnable(_global) {}

    //==================================================================================================================
    // Config (access: owner)
    //==================================================================================================================

    function setImplementation(address _implementation) external onlyOwner {
        implementation = _implementation;

        emit ImplementationSet(_implementation);
    }

    //==================================================================================================================
    // Functions
    //==================================================================================================================

    function deployProxy(bytes32 _salt, bytes calldata _initData) external returns (address proxy_) {
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(this), _initData));

        proxy_ = Create2.deploy({amount: 0, salt: keccak256(abi.encode(msg.sender, _salt)), bytecode: bytecode});

        isInstance[proxy_] = true;

        emit ProxyDeployed({proxy: proxy_});
    }

    //==================================================================================================================
    // Getters
    //==================================================================================================================

    function computeProxyAddress(address _deployer, bytes32 _salt, bytes calldata _initData)
        external
        view
        returns (address addr_)
    {
        bytes memory bytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(this), _initData));

        return
            Create2.computeAddress({salt: keccak256(abi.encode(_deployer, _salt)), bytecodeHash: keccak256(bytecode)});
    }
}
