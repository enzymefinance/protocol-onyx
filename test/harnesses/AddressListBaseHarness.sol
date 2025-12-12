// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";

contract AddressListBaseHarness is AddressListBase {
    address public authAccount;

    function setAuthAccount(address _authAccount) external {
        authAccount = _authAccount;
    }

    /// @inheritdoc AddressListBase
    function isAuth(address _who) public view override returns (bool) {
        return _who == authAccount;
    }
}
