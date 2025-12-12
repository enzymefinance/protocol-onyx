// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {ISharesTransferValidator} from "src/interfaces/ISharesTransferValidator.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title AddressListsSharesTransferValidator Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Validates shares transfers by comparing sender and recipient against address lists
contract AddressListsSharesTransferValidator is ISharesTransferValidator, ComponentHelpersMixin {
    //==================================================================================================================
    // Types
    //==================================================================================================================

    enum ListType {
        None,
        Allow,
        Disallow
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SHARES_TRANSFER_VALIDATOR_STORAGE_LOCATION =
        0x1d610e4d64fa4e8ba281fc0d06b837ed64d6505800b483cb7f845f44c75c7100;
    string private constant SHARES_TRANSFER_VALIDATOR_STORAGE_LOCATION_ID = "SharesTransferValidator";

    /// @custom:storage-location erc7201:enzyme.SharesTransferValidator
    /// @param recipientAllowlist Address of the IAddressList contract for recipient validation
    struct SharesTransferValidatorStorage {
        address senderList;
        address recipientList;
        ListType recipientListType;
        ListType senderListType;
    }

    function __getSharesTransferValidatorStorage() internal pure returns (SharesTransferValidatorStorage storage $) {
        bytes32 location = SHARES_TRANSFER_VALIDATOR_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event RecipientListSet(address list, ListType listType);
    event SenderListSet(address list, ListType listType);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SharesTransferValidator__ValidateSetList__InvalidTypeForList();
    error SharesTransferValidator__ValidateSharesTransfer__RecipientNotAllowed();
    error SharesTransferValidator__ValidateSharesTransfer__SenderNotAllowed();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SHARES_TRANSFER_VALIDATOR_STORAGE_LOCATION, _id: SHARES_TRANSFER_VALIDATOR_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    function setRecipientList(address _list, ListType _listType) external onlyAdminOrOwner {
        __validateSetList({_list: _list, _listType: _listType});

        SharesTransferValidatorStorage storage $ = __getSharesTransferValidatorStorage();
        $.recipientList = _list;
        $.recipientListType = _listType;

        emit RecipientListSet({list: _list, listType: _listType});
    }

    function setSenderList(address _list, ListType _listType) external onlyAdminOrOwner {
        __validateSetList({_list: _list, _listType: _listType});

        SharesTransferValidatorStorage storage $ = __getSharesTransferValidatorStorage();
        $.senderList = _list;
        $.senderListType = _listType;

        emit SenderListSet({list: _list, listType: _listType});
    }

    function __validateSetList(address _list, ListType _listType) internal pure {
        require(
            _list == address(0) && _listType == ListType.None || _list != address(0) && _listType != ListType.None,
            SharesTransferValidator__ValidateSetList__InvalidTypeForList()
        );
    }

    //==================================================================================================================
    // Required: ISharesTransferValidator
    //==================================================================================================================

    /// @inheritdoc ISharesTransferValidator
    function validateSharesTransfer(address _from, address _to, uint256) external view override {
        __validateSender(_from);
        __validateRecipient(_to);
    }

    function __isAllowedByList(address _who, address _list, ListType _listType) internal view returns (bool) {
        if (_listType == ListType.None) {
            return true;
        } else if (_listType == ListType.Allow) {
            return IAddressList(_list).isInList(_who);
        } else if (_listType == ListType.Disallow) {
            return !IAddressList(_list).isInList(_who);
        }

        return false;
    }

    function __validateRecipient(address _recipient) internal view {
        bool allowed =
            __isAllowedByList({_who: _recipient, _list: getRecipientList(), _listType: getRecipientListType()});
        require(allowed, SharesTransferValidator__ValidateSharesTransfer__RecipientNotAllowed());
    }

    function __validateSender(address _sender) internal view {
        bool allowed = __isAllowedByList({_who: _sender, _list: getSenderList(), _listType: getSenderListType()});
        require(allowed, SharesTransferValidator__ValidateSharesTransfer__SenderNotAllowed());
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    function getRecipientList() public view returns (address) {
        return __getSharesTransferValidatorStorage().recipientList;
    }

    function getRecipientListType() public view returns (ListType) {
        return __getSharesTransferValidatorStorage().recipientListType;
    }

    function getSenderList() public view returns (address) {
        return __getSharesTransferValidatorStorage().senderList;
    }

    function getSenderListType() public view returns (ListType) {
        return __getSharesTransferValidatorStorage().senderListType;
    }
}
