// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title ERC7540LikeIssuanceBase Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A base contract for the common functions of ERC7540-like deposit and redeem handlers
contract ERC7540LikeIssuanceBase is ComponentHelpersMixin {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant ERC7540_LIKE_ISSUANCE_BASE_STORAGE_LOCATION =
        0xb6d07fd6f3a90998edd8cc9d24642317ef35db10e62ed4dbf526ac2cdd3b8d00;
    string private constant ERC7540_LIKE_ISSUANCE_BASE_STORAGE_LOCATION_ID = "ERC7540LikeIssuanceBase";

    /// @custom:storage-location erc7201:enzyme.ERC7540LikeIssuanceBase
    /// @param asset The asset used for deposit/redeem/value
    struct ERC7540LikeIssuanceBaseStorage {
        address asset;
    }

    function __getERC7540LikeIssuanceBaseStorage() private pure returns (ERC7540LikeIssuanceBaseStorage storage $) {
        bytes32 location = ERC7540_LIKE_ISSUANCE_BASE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AssetSet(address asset);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ERC7540LikeIssuanceBase__SetAsset__AlreadySet();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: ERC7540_LIKE_ISSUANCE_BASE_STORAGE_LOCATION, _id: ERC7540_LIKE_ISSUANCE_BASE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @dev Can only be set once
    function setAsset(address _asset) external onlyAdminOrOwner {
        require(asset() == address(0), ERC7540LikeIssuanceBase__SetAsset__AlreadySet());

        ERC7540LikeIssuanceBaseStorage storage $ = __getERC7540LikeIssuanceBaseStorage();
        $.asset = _asset;

        emit AssetSet({asset: _asset});
    }

    //==================================================================================================================
    // IERC4626
    //==================================================================================================================

    function asset() public view returns (address asset_) {
        return __getERC7540LikeIssuanceBaseStorage().asset;
    }

    //==================================================================================================================
    // IERC7575
    //==================================================================================================================

    function share() public view returns (address share_) {
        return __getShares();
    }
}
