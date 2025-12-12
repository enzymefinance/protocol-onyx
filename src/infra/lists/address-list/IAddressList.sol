// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

/// @title IAddressList Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IAddressList {
    /// @notice Checks if an item is in the list
    /// @param _item The item to check
    /// @return isInList_ True if the item is in the list
    function isInList(address _item) external view returns (bool isInList_);
}
