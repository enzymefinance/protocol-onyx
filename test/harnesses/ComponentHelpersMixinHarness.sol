// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ComponentHarnessMixin} from "test/harnesses/utils/ComponentHarnessMixin.sol";

contract ComponentHelpersMixinHarness is ComponentHelpersMixin, ComponentHarnessMixin {
    constructor(address _shares) ComponentHarnessMixin(_shares) {}
}
