// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {CreWorkflowConsumer} from "src/components/automations/chainlink-cre/CreWorkflowConsumer.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract CreWorkflowConsumerHarness is CreWorkflowConsumer, ComponentHarnessMixin {
    constructor(address _shares, address _chainlinkKeystoneForwarder, address _allowedWorkflowOwner)
        CreWorkflowConsumer(_chainlinkKeystoneForwarder, _allowedWorkflowOwner)
        ComponentHarnessMixin(_shares)
    {}
}
