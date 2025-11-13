// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

library DeploymentHelpersLib {
    /// @notice Deploys a contract at an address that will be unique across all chains
    /// @param _bytecode The initialization bytecode of the contract to deploy
    /// @param _nonce A unique nonce
    /// @return deployedAddress_ The address of the deployed contract
    /// @dev _nonce MUST be unique for the implementing contract on this chain
    function deployAtUniqueAddress(bytes memory _bytecode, uint256 _nonce) internal returns (address deployedAddress_) {
        bytes32 salt = keccak256(abi.encode(_nonce, block.chainid));

        return Create2.deploy({amount: 0, salt: salt, bytecode: _bytecode});
    }
}
