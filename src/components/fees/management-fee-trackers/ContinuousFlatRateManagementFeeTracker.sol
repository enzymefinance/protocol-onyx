// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IManagementFeeTracker} from "src/components/fees/interfaces/IManagementFeeTracker.sol";
import {FeeTrackerHelpersMixin} from "src/components/fees/utils/FeeTrackerHelpersMixin.sol";
import {ONE_HUNDRED_PERCENT_BPS, SECONDS_IN_YEAR} from "src/utils/Constants.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title ContinuousFlatRateManagementFeeTracker Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A management fee with a configurable annual rate
/// @dev resetLastSettled() must be called once before first settlement,
/// in order to initialize lastSettled with an initial timestamp.
/// This should be done at whatever time the fee should begin accruing.
contract ContinuousFlatRateManagementFeeTracker is IManagementFeeTracker, FeeTrackerHelpersMixin {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant MANAGEMENT_FEE_TRACKER_STORAGE_LOCATION =
        0x25008e61d6a33ea3313338886e9ba1cacec26ac79d05629f9df4b5d62fb2ee00;
    string private constant MANAGEMENT_FEE_TRACKER_STORAGE_LOCATION_ID = "ManagementFeeTracker";

    /// @custom:storage-location erc7201:enzyme.ManagementFeeTracker
    /// @param rate Management fee rate as an annualized percentage of net value
    /// @param lastSettled Timestamp of the last settlement
    struct ManagementFeeTrackerStorage {
        uint16 rate;
        uint64 lastSettled;
    }

    function __getManagementFeeTrackerStorage() private pure returns (ManagementFeeTrackerStorage storage $) {
        bytes32 location = MANAGEMENT_FEE_TRACKER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event RateSet(uint16 rate);

    event Settled(uint256 valueDue);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ContinuousFlatRateManagementFeeTracker__SetRate__ExceedsMax();

    error ContinuousFlatRateManagementFeeTracker__SettleManagementFee__LastSettledNotInitialized();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: MANAGEMENT_FEE_TRACKER_STORAGE_LOCATION, _id: MANAGEMENT_FEE_TRACKER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    /// @notice Sets the last settled timestamp to the current block timestamp
    /// @dev Must be called once before first settlement
    function resetLastSettled() external onlyAdminOrOwner {
        __settle({_valueDue: 0});
    }

    /// @notice Sets the management fee rate
    /// @dev Updating rate will apply the new rate on any time since last settlement,
    /// i.e., it does not automatically settle with the old rate at the current timestamp
    function setRate(uint16 _rate) external onlyAdminOrOwner {
        require(_rate < ONE_HUNDRED_PERCENT_BPS, ContinuousFlatRateManagementFeeTracker__SetRate__ExceedsMax());

        ManagementFeeTrackerStorage storage $ = __getManagementFeeTrackerStorage();
        $.rate = _rate;

        emit RateSet(_rate);
    }

    //==================================================================================================================
    // Settlement
    //==================================================================================================================

    /// @inheritdoc IManagementFeeTracker
    function settleManagementFee(uint256 _netValue) external onlyFeeHandler returns (uint256 valueDue_) {
        uint256 lastSettled = getLastSettled();
        require(
            lastSettled > 0, ContinuousFlatRateManagementFeeTracker__SettleManagementFee__LastSettledNotInitialized()
        );

        uint256 secondsSinceSettlement = block.timestamp - lastSettled;
        valueDue_ = (_netValue * getRate() * secondsSinceSettlement) / (SECONDS_IN_YEAR * ONE_HUNDRED_PERCENT_BPS);

        // Always settle, even if no value is due
        __settle({_valueDue: valueDue_});
    }

    function __settle(uint256 _valueDue) internal {
        ManagementFeeTrackerStorage storage $ = __getManagementFeeTrackerStorage();

        $.lastSettled = uint64(block.timestamp);

        emit Settled({valueDue: _valueDue});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the last settled timestamp
    function getLastSettled() public view returns (uint256) {
        return __getManagementFeeTrackerStorage().lastSettled;
    }

    /// @notice Returns the management fee rate
    function getRate() public view returns (uint256) {
        return __getManagementFeeTrackerStorage().rate;
    }
}
