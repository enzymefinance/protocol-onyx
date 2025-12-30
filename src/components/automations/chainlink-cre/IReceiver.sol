// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IReceiver - receives keystone reports
/// @notice Implementations must support the IReceiver interface through ERC165.
interface IReceiver is IERC165 {
    /// @notice Handles incoming keystone reports.
    /// @dev If this function call reverts, it can be retried with a higher gas
    /// limit. The receiver is responsible for discarding stale reports.
    /// @param _metadata Report's metadata.
    /// @param _report Workflow report.
    function onReport(bytes calldata _metadata, bytes calldata _report) external;
}
