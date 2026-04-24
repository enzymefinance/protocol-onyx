// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {WalletsManager} from "src/components/ccip/WalletsManager.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract WalletsManagerHarness is WalletsManager, ComponentHarnessMixin {
    constructor(address _shares, address _ccipRouter, address _depositorWalletsFactory)
        WalletsManager(_ccipRouter, _depositorWalletsFactory)
        ComponentHarnessMixin(_shares)
    {}
}
