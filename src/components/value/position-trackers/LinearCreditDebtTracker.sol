// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IPositionTracker} from "src/components/value/position-trackers/IPositionTracker.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title LinearCreditDebtTracker Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice An IPositionTracker implementation that tracks linear credit and/or debt positions
contract LinearCreditDebtTracker is IPositionTracker, ComponentHelpersMixin {
    //==================================================================================================================
    // Types
    //==================================================================================================================

    /// @dev Stores information about a credit or debt line-item
    /// @param totalValue The total value of the item (quoted in the Shares value asset), written down linearly over time
    /// @param settledValue The settled, non-linear value of the item (quoted in the Shares value asset)
    /// @param id The unique identifier of the item
    /// @param index The array index of the item in `ids[]`
    /// @param start The start timestamp of the linear write-down period
    /// @param duration The duration of the linear write-down period (in seconds)
    struct Item {
        // 1st slot
        int128 totalValue;
        int128 settledValue;
        // 2nd slot
        uint24 id;
        uint24 index;
        uint40 start;
        uint32 duration;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant LINEAR_CREDIT_DEBT_TRACKER_STORAGE_LOCATION =
        0xf3c5e97ea0f49b3293469a3b3dca5503879e1f21da2c7f1e770e480cdbe07300;
    string private constant LINEAR_CREDIT_DEBT_TRACKER_STORAGE_LOCATION_ID = "LinearCreditDebtTracker";

    /// @custom:storage-location erc7201:enzyme.LinearCreditDebtTracker
    /// @param lastItemId The id of the last item that was added
    /// @param ids The list of active item ids (all items that have not been removed)
    /// @param idToItem A mapping of item ids to their corresponding Item info
    struct LinearCreditDebtTrackerStorage {
        uint24 lastItemId; // starts from 1
        uint24[] ids;
        mapping(uint24 => Item) idToItem;
    }

    function __getLinearCreditDebtTrackerStorage() private pure returns (LinearCreditDebtTrackerStorage storage $) {
        bytes32 location = LINEAR_CREDIT_DEBT_TRACKER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event ItemAdded(uint24 id, int128 totalValue, uint40 start, uint32 duration, string description);

    event ItemRemoved(uint24 id);

    event ItemTotalSettledUpdated(uint24 id, int128 totalSettled);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error LinearCreditDebtTracker__AddItem__EmptyTotalValue();

    error LinearCreditDebtTracker__RemoveItem__DoesNotExist();

    error LinearCreditDebtTracker__UpdateSettledValue__DoesNotExist();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: LINEAR_CREDIT_DEBT_TRACKER_STORAGE_LOCATION, _id: LINEAR_CREDIT_DEBT_TRACKER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Item management (access: Shares admin or owner)
    //==================================================================================================================

    /// @notice Adds a new line-item to the tracker
    /// @param _totalValue The total value of the item (quoted in the Shares value asset), written down linearly over time
    /// @param _start The start timestamp of the linear write-down period
    /// @param _duration The duration of the linear write-down period (in seconds)
    /// @param _description A description of the item
    /// @return id_ The id of the new line-item
    /// @dev A _duration of 0 indicates a discrete value change at the _start timestamp
    function addItem(int128 _totalValue, uint40 _start, uint32 _duration, string calldata _description)
        external
        onlyAdminOrOwner
        returns (uint24 id_)
    {
        require(_totalValue != 0, LinearCreditDebtTracker__AddItem__EmptyTotalValue());

        LinearCreditDebtTrackerStorage storage $ = __getLinearCreditDebtTrackerStorage();
        id_ = ++$.lastItemId; // first item will be `id_ = 1`
        uint24 index = uint24(getItemsCount());

        $.ids.push(id_);
        $.idToItem[id_] =
            Item({totalValue: _totalValue, settledValue: 0, id: id_, index: index, start: _start, duration: _duration});

        emit ItemAdded({
            id: id_, totalValue: _totalValue, start: _start, duration: _duration, description: _description
        });
    }

    /// @notice Removes an existing line-item from the tracker
    function removeItem(uint24 _id) external onlyAdminOrOwner {
        Item memory item = getItem({_id: _id});
        require(item.id != 0, LinearCreditDebtTracker__RemoveItem__DoesNotExist());

        LinearCreditDebtTrackerStorage storage $ = __getLinearCreditDebtTrackerStorage();
        uint256 finalIndex = getItemsCount() - 1;
        if (item.index != finalIndex) {
            Item memory finalItem = __getItemAtIndex({_index: finalIndex});
            // move final item to old item's index
            $.ids[item.index] = finalItem.id;
            $.idToItem[finalItem.id].index = item.index;
        }
        $.ids.pop();
        delete $.idToItem[_id];

        emit ItemRemoved({id: _id});
    }

    /// @notice Updates the settled value of an existing line-item, written down immediately
    /// @param _id The line-item id
    /// @param _totalSettled The total settled value of the line-item (quoted in the Shares value asset)
    function updateSettledValue(uint24 _id, int128 _totalSettled) external onlyAdminOrOwner {
        require(getItem({_id: _id}).id != 0, LinearCreditDebtTracker__UpdateSettledValue__DoesNotExist());

        LinearCreditDebtTrackerStorage storage $ = __getLinearCreditDebtTrackerStorage();
        $.idToItem[_id].settledValue = _totalSettled;

        emit ItemTotalSettledUpdated({id: _id, totalSettled: _totalSettled});
    }

    //==================================================================================================================
    // Position value
    //==================================================================================================================

    /// @notice Calculates the value of a line-item at the current timestamp
    /// @param _id The line-item id
    /// @return value_ The value of the line-item (quoted in the Shares value asset)
    /// @dev Cases:
    /// - prior to item.start = settled value only
    /// - while within "item.start + item.duration" = settled value + linearly pro-rated total value
    /// - otherwise = settled value + total value
    function calcItemValue(uint24 _id) public view returns (int256 value_) {
        Item memory item = getItem({_id: _id});

        // Handle cases outside of start and stop bounds
        if (block.timestamp <= item.start) {
            return item.settledValue;
        } else if (block.timestamp >= item.start + item.duration) {
            return item.settledValue + item.totalValue;
        }

        uint256 lapsed = block.timestamp - item.start;

        int256 proRatedValue = item.totalValue * int256(lapsed) / int256(uint256(item.duration));

        return item.settledValue + proRatedValue;
    }

    /// @inheritdoc IPositionTracker
    function getPositionValue() external view override returns (int256 value_) {
        uint24[] memory ids = getItemIds();
        for (uint256 i; i < ids.length; i++) {
            value_ += calcItemValue({_id: ids[i]});
        }

        return value_;
    }

    //==================================================================================================================
    // Misc
    //==================================================================================================================

    function __getItemAtIndex(uint256 _index) internal view returns (Item memory item_) {
        return getItem({_id: __getLinearCreditDebtTrackerStorage().ids[_index]});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    function getItem(uint24 _id) public view returns (Item memory item_) {
        return __getLinearCreditDebtTrackerStorage().idToItem[_id];
    }

    function getItemIds() public view returns (uint24[] memory ids_) {
        return __getLinearCreditDebtTrackerStorage().ids;
    }

    function getItemsCount() public view returns (uint256 count_) {
        return __getLinearCreditDebtTrackerStorage().ids.length;
    }

    function getLastItemId() public view returns (uint24 id_) {
        return __getLinearCreditDebtTrackerStorage().lastItemId;
    }
}
