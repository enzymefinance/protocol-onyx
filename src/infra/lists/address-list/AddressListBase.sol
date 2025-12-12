// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title AddressListBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A base contract for managing a list of addresses
abstract contract AddressListBase is IAddressList {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant ADDRESS_LIST_BASE_STORAGE_LOCATION =
        0xbdf8df28b0690daa2b80a9a43d66dc30bfa3557748d06b2e704e1b9747c7f000;
    string private constant ADDRESS_LIST_BASE_STORAGE_LOCATION_ID = "AddressListBase";

    /// @custom:storage-location erc7201:enzyme.AddressListBase
    /// @param itemToIsInList Mapping of addresses to their list membership status
    struct AddressListBaseStorage {
        mapping(address => bool) itemToIsInList;
    }

    function __getAddressListBaseStorage() internal pure returns (AddressListBaseStorage storage $) {
        bytes32 location = ADDRESS_LIST_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event ItemAdded(address item);

    event ItemRemoved(address item);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error AddressList__Unauthorized();

    error AddressList__AddToList__ItemAlreadyInList();

    error AddressList__RemoveFromList__ItemNotInList();

    //==================================================================================================================
    // Modifiers
    //==================================================================================================================

    modifier onlyAuth() {
        require(isAuth(msg.sender), AddressList__Unauthorized());
        _;
    }

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: ADDRESS_LIST_BASE_STORAGE_LOCATION, _id: ADDRESS_LIST_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // List management
    //==================================================================================================================

    /// @notice Adds items to a given list
    /// @param _items The items to add to the list
    function addToList(address[] calldata _items) external onlyAuth {
        for (uint256 i; i < _items.length; i++) {
            address item = _items[i];
            require(!isInList(item), AddressList__AddToList__ItemAlreadyInList());

            AddressListBaseStorage storage $ = __getAddressListBaseStorage();
            $.itemToIsInList[item] = true;

            emit ItemAdded(item);
        }
    }

    /// @notice Removes items from a given list
    /// @param _items The items to remove from the list
    function removeFromList(address[] calldata _items) external onlyAuth {
        for (uint256 i; i < _items.length; i++) {
            address item = _items[i];
            require(isInList(item), AddressList__RemoveFromList__ItemNotInList());

            AddressListBaseStorage storage $ = __getAddressListBaseStorage();
            $.itemToIsInList[item] = false;

            emit ItemRemoved(item);
        }
    }

    //==================================================================================================================
    // Required: IAddressList
    //==================================================================================================================

    /// @inheritdoc IAddressList
    function isInList(address _item) public view returns (bool) {
        return __getAddressListBaseStorage().itemToIsInList[_item];
    }

    //==================================================================================================================
    // Virtual functions
    //==================================================================================================================

    /// @dev True if a given account can add and remove items from the list
    function isAuth(address _who) public view virtual returns (bool);
}
