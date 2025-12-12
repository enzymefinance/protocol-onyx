// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddressListBase} from "src/infra/lists/address-list/AddressListBase.sol";

/// @title OwnableAddressList Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice An address list that defers authorization to an owner
contract OwnableAddressList is AddressListBase, OwnableUpgradeable {
    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    function init(address _owner) external initializer {
        __Ownable_init({initialOwner: _owner});
    }

    //==================================================================================================================
    // Required: AddressListBase
    //==================================================================================================================

    /// @inheritdoc AddressListBase
    function isAuth(address _who) public view override returns (bool) {
        return _who == owner();
    }
}
