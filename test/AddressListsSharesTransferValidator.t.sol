// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {OwnableAddressList} from "src/infra/lists/address-list/OwnableAddressList.sol";
import {
    AddressListsSharesTransferValidator
} from "src/components/shares-transfer-validators/AddressListsSharesTransferValidator.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";

import {
    AddressListsSharesTransferValidatorHarness
} from "test/harnesses/AddressListsSharesTransferValidatorHarness.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract AddressListsSharesTransferValidatorTest is Test, TestHelpers {
    Shares shares;
    address owner;
    address admin = makeAddr("AddressListsSharesTransferValidatorTest.admin");

    address listAddress;
    address listItem = makeAddr("listItem");

    AddressListsSharesTransferValidatorHarness validator;

    function setUp() public {
        shares = createShares();
        owner = shares.owner();

        vm.prank(owner);
        shares.addAdmin(admin);

        validator = new AddressListsSharesTransferValidatorHarness(address(shares));

        // Create a list with owner and item
        OwnableAddressList list = new OwnableAddressList();
        address listOwner = makeAddr("listOwner");
        list.init({_owner: listOwner});

        address[] memory items = new address[](1);
        items[0] = listItem;
        vm.prank(listOwner);
        list.addToList({_items: items});

        listAddress = address(list);
    }

    //==================================================================================================================
    // setRecipientList
    //==================================================================================================================

    function test_setRecipientList_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        validator.setRecipientList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.None});
    }

    function test_setRecipientList_fail_invalidTypeForList_zeroAddressWithNonNoneType() public {
        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSetList__InvalidTypeForList.selector
        );

        vm.prank(admin);
        validator.setRecipientList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.Allow});
    }

    function test_setRecipientList_fail_invalidTypeForList_nonZeroAddressWithNoneType() public {
        address list = makeAddr("list");

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSetList__InvalidTypeForList.selector
        );

        vm.prank(admin);
        validator.setRecipientList({_list: list, _listType: AddressListsSharesTransferValidator.ListType.None});
    }

    function test_setRecipientList_success_setAllowlist() public {
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.RecipientListSet({
            list: listAddress, listType: AddressListsSharesTransferValidator.ListType.Allow
        });

        vm.prank(admin);
        validator.setRecipientList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        assertEq(validator.getRecipientList(), listAddress, "incorrect recipient list");
        assertEq(
            uint8(validator.getRecipientListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Allow),
            "incorrect recipient list type"
        );
    }

    function test_setRecipientList_success_setDisallowlist() public {
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.RecipientListSet({
            list: listAddress, listType: AddressListsSharesTransferValidator.ListType.Disallow
        });

        vm.prank(admin);
        validator.setRecipientList({
            _list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow
        });

        assertEq(validator.getRecipientList(), listAddress, "incorrect recipient list");
        assertEq(
            uint8(validator.getRecipientListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Disallow),
            "incorrect recipient list type"
        );
    }

    function test_setRecipientList_success_clearList() public {
        // First set a list
        vm.prank(admin);
        validator.setRecipientList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        // Then clear it
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.RecipientListSet({
            list: address(0), listType: AddressListsSharesTransferValidator.ListType.None
        });

        vm.prank(admin);
        validator.setRecipientList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.None});

        assertEq(validator.getRecipientList(), address(0), "incorrect recipient list");
        assertEq(
            uint8(validator.getRecipientListType()),
            uint8(AddressListsSharesTransferValidator.ListType.None),
            "incorrect recipient list type"
        );
    }

    //==================================================================================================================
    // setSenderList
    //==================================================================================================================

    function test_setSenderList_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        validator.setSenderList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.None});
    }

    function test_setSenderList_fail_invalidTypeForList_zeroAddressWithNonNoneType() public {
        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSetList__InvalidTypeForList.selector
        );

        vm.prank(admin);
        validator.setSenderList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.Disallow});
    }

    function test_setSenderList_fail_invalidTypeForList_nonZeroAddressWithNoneType() public {
        address list = makeAddr("list");

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSetList__InvalidTypeForList.selector
        );

        vm.prank(admin);
        validator.setSenderList({_list: list, _listType: AddressListsSharesTransferValidator.ListType.None});
    }

    function test_setSenderList_success_setAllowlist() public {
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.SenderListSet({
            list: listAddress, listType: AddressListsSharesTransferValidator.ListType.Allow
        });

        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        assertEq(validator.getSenderList(), listAddress, "incorrect sender list");
        assertEq(
            uint8(validator.getSenderListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Allow),
            "incorrect sender list type"
        );
    }

    function test_setSenderList_success_setDisallowlist() public {
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.SenderListSet({
            list: listAddress, listType: AddressListsSharesTransferValidator.ListType.Disallow
        });

        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow});

        assertEq(validator.getSenderList(), listAddress, "incorrect sender list");
        assertEq(
            uint8(validator.getSenderListType()),
            uint8(AddressListsSharesTransferValidator.ListType.Disallow),
            "incorrect sender list type"
        );
    }

    function test_setSenderList_success_clearList() public {
        // First set a list
        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        // Then clear it
        vm.expectEmit(address(validator));
        emit AddressListsSharesTransferValidator.SenderListSet({
            list: address(0), listType: AddressListsSharesTransferValidator.ListType.None
        });

        vm.prank(admin);
        validator.setSenderList({_list: address(0), _listType: AddressListsSharesTransferValidator.ListType.None});

        assertEq(validator.getSenderList(), address(0), "incorrect sender list");
        assertEq(
            uint8(validator.getSenderListType()),
            uint8(AddressListsSharesTransferValidator.ListType.None),
            "incorrect sender list type"
        );
    }

    //==================================================================================================================
    // validateSharesTransfer
    //==================================================================================================================

    // -- Sender allowlist --

    function test_validateSharesTransfer_fail_senderAllowlist_senderNotInList() public {
        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        address badSender = makeAddr("badSender");
        address recipient = makeAddr("recipient");

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSharesTransfer__SenderNotAllowed
            .selector
        );

        validator.validateSharesTransfer(badSender, recipient, 123);
    }

    function test_validateSharesTransfer_success_senderAllowlist_senderInList() public {
        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        address goodSender = listItem;
        address recipient = makeAddr("recipient");

        // Should not revert
        validator.validateSharesTransfer(goodSender, recipient, 123);
    }

    // -- Sender disallowlist (blocklist) --

    function test_validateSharesTransfer_fail_senderDisallowlist_senderInList() public {
        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow});

        address badSender = listItem;
        address recipient = makeAddr("recipient");

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSharesTransfer__SenderNotAllowed
            .selector
        );

        validator.validateSharesTransfer(badSender, recipient, 123);
    }

    function test_validateSharesTransfer_success_senderDisallowlist_senderNotInList() public {
        vm.prank(admin);
        validator.setSenderList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow});

        address goodSender = makeAddr("goodSender");
        address recipient = makeAddr("recipient");

        // Should not revert (sender not in disallowlist)
        validator.validateSharesTransfer(goodSender, recipient, 123);
    }

    // -- Recipient allowlist --

    function test_validateSharesTransfer_fail_recipientAllowlist_recipientNotInList() public {
        vm.prank(admin);
        validator.setRecipientList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        address sender = makeAddr("sender");
        address badRecipient = makeAddr("badRecipient");

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSharesTransfer__RecipientNotAllowed
                .selector
        );

        validator.validateSharesTransfer(sender, badRecipient, 123);
    }

    function test_validateSharesTransfer_success_recipientAllowlist_recipientInList() public {
        vm.prank(admin);
        validator.setRecipientList({_list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Allow});

        address sender = makeAddr("sender");
        address goodRecipient = listItem;

        // Should not revert
        validator.validateSharesTransfer(sender, goodRecipient, 123);
    }

    // -- Recipient disallowlist (blocklist) --

    function test_validateSharesTransfer_fail_recipientDisallowlist_recipientInList() public {
        vm.prank(admin);
        validator.setRecipientList({
            _list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow
        });

        address sender = makeAddr("sender");
        address badRecipient = listItem;

        vm.expectRevert(
            AddressListsSharesTransferValidator.SharesTransferValidator__ValidateSharesTransfer__RecipientNotAllowed
                .selector
        );

        validator.validateSharesTransfer(sender, badRecipient, 123);
    }

    function test_validateSharesTransfer_success_recipientDisallowlist_recipientNotInList() public {
        vm.prank(admin);
        validator.setRecipientList({
            _list: listAddress, _listType: AddressListsSharesTransferValidator.ListType.Disallow
        });

        address sender = makeAddr("sender");
        address goodRecipient = makeAddr("goodRecipient");

        // Should not revert (recipient not in disallowlist)
        validator.validateSharesTransfer(sender, goodRecipient, 123);
    }
}
