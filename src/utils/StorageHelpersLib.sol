// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title StorageHelpersLib Library
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Common utility functions for handling storage
library StorageHelpersLib {
    error StorageHelpersLib__VerifyErc7201Location__Mismatch();

    /// @dev https://eips.ethereum.org/EIPS/eip-7201
    function deriveErc7201Location(string memory _id) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(uint256(keccak256(bytes(string.concat("enzyme.", _id)))) - 1))
                & ~bytes32(uint256(0xff));
    }

    function verifyErc7201LocationForId(bytes32 _location, string memory _id) internal pure {
        require(_location == deriveErc7201Location(_id), StorageHelpersLib__VerifyErc7201Location__Mismatch());
    }
}
