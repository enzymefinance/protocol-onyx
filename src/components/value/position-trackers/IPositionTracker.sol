// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IPositionTracker Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IPositionTracker {
    /// @notice Returns the current +/- value of the position quoted in the Shares value asset
    /// @return value_ The value (18-decimal precision)
    function getPositionValue() external view returns (int256 value_);
}
