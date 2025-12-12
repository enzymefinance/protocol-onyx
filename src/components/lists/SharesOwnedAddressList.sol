// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";

/// @title SharesOwnedAddressList Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice An Onyx Component for managing a list of addresses
contract SharesOwnedAddressList is AddressListBase, ComponentHelpersMixin {
    //==================================================================================================================
    // Required: AddressListBase
    //==================================================================================================================

    /// @inheritdoc AddressListBase
    function isAuth(address _who) public view override returns (bool) {
        return __isAdminOrOwner(_who);
    }
}
