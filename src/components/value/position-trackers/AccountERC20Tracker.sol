// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IPositionTracker} from "src/components/value/position-trackers/IPositionTracker.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IValuationHandler} from "src/interfaces/IValuationHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title AccountERC20Tracker Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice An IPositionTracker implementation that tracks value of ERC20 tokens held by an account
contract AccountERC20Tracker is IPositionTracker, ComponentHelpersMixin {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCast for uint256;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant ACCOUNT_ERC20_TRACKER_STORAGE_LOCATION =
        0x85378e297d6c8e578e867cf1e0cdf12245bc85fa8c2e83002e863bfec07d5e00;
    string private constant ACCOUNT_ERC20_TRACKER_STORAGE_LOCATION_ID = "AccountERC20Tracker";

    /// @custom:storage-location erc7201:enzyme.AccountERC20Tracker
    /// @param assets A set of ERC20 token addresses to track
    /// @param account The account to track
    struct AccountERC20TrackerStorage {
        EnumerableSet.AddressSet assets;
        address account;
    }

    function __getAccountERC20TrackerStorage() private pure returns (AccountERC20TrackerStorage storage $) {
        bytes32 location = ACCOUNT_ERC20_TRACKER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AccountSet(address account);

    event AssetAdded(address asset);

    event AssetRemoved(address asset);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error AccountERC20Tracker__AddAsset__AlreadyAdded();

    error AccountERC20Tracker__Init__AlreadyInitialized();

    error AccountERC20Tracker__Init__EmptyAccount();

    error AccountERC20Tracker__GetPositionValue__NotInitialized();

    error AccountERC20Tracker__RemoveAsset__NotAdded();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: ACCOUNT_ERC20_TRACKER_STORAGE_LOCATION, _id: ACCOUNT_ERC20_TRACKER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    function init(address _account) external {
        require(!__isInitialized(), AccountERC20Tracker__Init__AlreadyInitialized());
        require(_account != address(0), AccountERC20Tracker__Init__EmptyAccount());

        AccountERC20TrackerStorage storage $ = __getAccountERC20TrackerStorage();
        $.account = _account;

        emit AccountSet(_account);
    }

    function __isInitialized() internal view returns (bool) {
        return getAccount() != address(0);
    }

    //==================================================================================================================
    // Config (access: admin)
    //==================================================================================================================

    function addAsset(address _asset) external onlyAdminOrOwner {
        AccountERC20TrackerStorage storage $ = __getAccountERC20TrackerStorage();
        bool added = $.assets.add(_asset);
        require(added, AccountERC20Tracker__AddAsset__AlreadyAdded());

        emit AssetAdded(_asset);
    }

    function removeAsset(address _asset) external onlyAdminOrOwner {
        AccountERC20TrackerStorage storage $ = __getAccountERC20TrackerStorage();
        bool removed = $.assets.remove(_asset);
        require(removed, AccountERC20Tracker__RemoveAsset__NotAdded());

        emit AssetRemoved(_asset);
    }

    //==================================================================================================================
    // Position value
    //==================================================================================================================

    /// @inheritdoc IPositionTracker
    function getPositionValue() external view override returns (int256 value_) {
        // Validates that `account` has been set.
        // Since address(0) has token holdings, it could result in unintended valuation behavior.
        require(__isInitialized(), AccountERC20Tracker__GetPositionValue__NotInitialized());

        address valuationHandler = Shares(__getShares()).getValuationHandler();
        address[] memory assets = getAssets();
        uint256 valueUint;
        for (uint256 i; i < assets.length; i++) {
            valueUint += __calcAssetValue({
                _account: getAccount(), _valuationHandler: valuationHandler, _asset: assets[i]
            });
        }

        return valueUint.toInt256();
    }

    function __calcAssetValue(address _account, address _valuationHandler, address _asset)
        internal
        view
        returns (uint256 value_)
    {
        uint256 assetAmount = IERC20(_asset).balanceOf(_account);
        return
            IValuationHandler(_valuationHandler).convertAssetAmountToValue({_asset: _asset, _assetAmount: assetAmount});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    function getAccount() public view returns (address) {
        return __getAccountERC20TrackerStorage().account;
    }

    function getAssets() public view returns (address[] memory) {
        return __getAccountERC20TrackerStorage().assets.values();
    }

    function isAsset(address _asset) public view returns (bool) {
        return __getAccountERC20TrackerStorage().assets.contains(_asset);
    }
}
