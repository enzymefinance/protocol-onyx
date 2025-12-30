// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

abstract contract Constants {
    // `[NETWORK]_BLOCK_LATEST` can be increased as-needed, and should be used in all tests
    uint256 internal constant ETHEREUM_BLOCK_LATEST = 23967530; // Dec 8th, 2025
    uint256 internal constant ARBITRUM_BLOCK_LATEST = 408447230; // Dec 8th, 2025
    uint256 internal constant BASE_BLOCK_LATEST = 39201030; // Dec 8th, 2025
    uint256 internal constant PLUME_BLOCK_LATEST = 41664170; // Dec 8th, 2025
}
