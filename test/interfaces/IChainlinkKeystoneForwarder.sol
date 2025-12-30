// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

interface IChainlinkKeystoneForwarder {
    function route(
        bytes32 _transmissionId,
        address _transmitter,
        address _receiver,
        bytes calldata _metadata,
        bytes calldata _report
    ) external returns (bool success_);

    function addForwarder(address _forwarder) external;

    function owner() external view returns (address owner_);
}
