// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {IAddressList} from "src/infra/lists/address-list/IAddressList.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title SyncDepositHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A synchronous deposit handler where users deposit an ERC20 asset and immediately receive pro-rated shares
/// @dev Considerations and limitations:
/// - may not support irregular asset behaviors (e.g., fee-on-transfer)
contract SyncDepositHandler is Initializable, ComponentHelpersMixin {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Constants
    //==================================================================================================================

    uint24 internal constant MAX_SHARE_PRICE_STALENESS_DISABLED = type(uint24).max;

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant SYNC_DEPOSIT_HANDLER_STORAGE_LOCATION =
        0x8a1bf4b6fe0f19db4139bc2fd041277dc03c6329c0bfe0e30c929d0ea93ecb00;
    string private constant SYNC_DEPOSIT_HANDLER_STORAGE_LOCATION_ID = "SyncDepositHandler";

    /// @custom:storage-location erc7201:enzyme.SyncDepositHandler
    /// @param asset The ERC20 asset accepted for deposits
    /// @param depositorAllowlist IAddressList contract for depositor allowlist validation (`address(0)` allows any depositor)
    /// @param maxSharePriceStaleness Maximum allowed age of the share price in seconds
    struct SyncDepositHandlerStorage {
        address asset;
        address depositorAllowlist;
        uint24 maxSharePriceStaleness;
    }

    function __getSyncDepositHandlerStorage() private pure returns (SyncDepositHandlerStorage storage $) {
        bytes32 location = SYNC_DEPOSIT_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event AssetSet(address asset);

    event Deposit(address depositor, uint256 assetAmount, uint256 sharesAmount, bytes32 referrer);

    event DepositorAllowlistSet(address list);

    event MaxSharePriceStalenessSet(uint24 maxStaleness);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error SyncDepositHandler__Deposit__ZeroAssets();

    error SyncDepositHandler__Deposit__ZeroShares();

    error SyncDepositHandler__ValidateDepositor__DepositorNotAllowed();

    error SyncDepositHandler__ValidateSharePriceTimestamp__SharePriceStale();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: SYNC_DEPOSIT_HANDLER_STORAGE_LOCATION, _id: SYNC_DEPOSIT_HANDLER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Init
    //==================================================================================================================

    /// @notice Initializer
    /// @param _asset The ERC20 asset to accept for deposits
    function init(address _asset) external initializer {
        SyncDepositHandlerStorage storage $ = __getSyncDepositHandlerStorage();
        $.asset = _asset;

        emit AssetSet({asset: _asset});
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    /// @notice Sets the maximum allowed staleness of the share price
    /// @param _maxStaleness Maximum age in seconds (MAX_SHARE_PRICE_STALENESS_DISABLED = no check)
    function setMaxSharePriceStaleness(uint24 _maxStaleness) external onlyAdminOrOwner {
        __getSyncDepositHandlerStorage().maxSharePriceStaleness = _maxStaleness;

        emit MaxSharePriceStalenessSet({maxStaleness: _maxStaleness});
    }

    /// @notice Sets the depositor allowlist
    /// @param _list IAddressList contract for depositor allowlist validation (`address(0)` = all depositors allowed)
    function setDepositorAllowlist(address _list) external onlyAdminOrOwner {
        __getSyncDepositHandlerStorage().depositorAllowlist = _list;

        emit DepositorAllowlistSet({list: _list});
    }

    //==================================================================================================================
    // Deposits (access: public)
    //==================================================================================================================

    /// @notice Deposits assets and mints shares to the depositor
    /// @param _assetAmount The amount of the deposit asset
    /// @return sharesAmount_ The amount of shares minted to the depositor
    function deposit(uint256 _assetAmount) external returns (uint256 sharesAmount_) {
        return __deposit({_depositor: msg.sender, _assetAmount: _assetAmount, _referrer: bytes32(0)});
    }

    /// @notice Deposits assets and mints shares to the depositor, with a referral code
    /// @param _assetAmount The amount of the deposit asset
    /// @param _referrer The referral identifier
    /// @return sharesAmount_ The amount of shares minted to the depositor
    function depositReferred(uint256 _assetAmount, bytes32 _referrer) external returns (uint256 sharesAmount_) {
        return __deposit({_depositor: msg.sender, _assetAmount: _assetAmount, _referrer: _referrer});
    }

    function __deposit(address _depositor, uint256 _assetAmount, bytes32 _referrer)
        internal
        returns (uint256 sharesAmount_)
    {
        require(_assetAmount > 0, SyncDepositHandler__Deposit__ZeroAssets());

        __validateDepositor({_depositor: _depositor});

        Shares shares = Shares(__getShares());
        ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());

        // Get and validate share price
        (uint256 sharePriceInValueAsset, uint256 sharePriceTimestamp) = valuationHandler.getSharePrice();
        __validateSharePriceTimestamp({_sharePriceTimestamp: sharePriceTimestamp});

        // Calculate gross shares
        uint256 value = valuationHandler.convertAssetAmountToValue({_asset: getAsset(), _assetAmount: _assetAmount});
        uint256 grossSharesAmount =
            ValueHelpersLib.calcSharesAmountForValue({_valuePerShare: sharePriceInValueAsset, _value: value});

        // Settle any entrance fee
        IFeeHandler feeHandler = IFeeHandler(shares.getFeeHandler());
        uint256 feeSharesAmount = address(feeHandler) == address(0)
            ? 0
            : feeHandler.settleEntranceFeeGivenGrossShares({_grossSharesAmount: grossSharesAmount});

        // Calculate net shares
        sharesAmount_ = grossSharesAmount - feeSharesAmount;
        require(sharesAmount_ > 0, SyncDepositHandler__Deposit__ZeroShares());

        // Mint net shares to depositor
        shares.mintFor({_to: _depositor, _sharesAmount: sharesAmount_});

        // Transfer asset from depositor directly to Shares
        IERC20(getAsset()).safeTransferFrom(_depositor, address(shares), _assetAmount);

        emit Deposit({
            depositor: _depositor, assetAmount: _assetAmount, sharesAmount: sharesAmount_, referrer: _referrer
        });
    }

    //==================================================================================================================
    // Internal helpers
    //==================================================================================================================

    /// @dev Validates that the depositor is allowed
    function __validateDepositor(address _depositor) internal view {
        address allowlist = getDepositorAllowlist();
        require(
            allowlist == address(0) || IAddressList(allowlist).isInList(_depositor),
            SyncDepositHandler__ValidateDepositor__DepositorNotAllowed()
        );
    }

    /// @dev Validates that the share price is not stale
    function __validateSharePriceTimestamp(uint256 _sharePriceTimestamp) internal view {
        uint24 maxStaleness = getMaxSharePriceStaleness();
        if (maxStaleness == MAX_SHARE_PRICE_STALENESS_DISABLED) return;

        require(
            block.timestamp - _sharePriceTimestamp <= maxStaleness,
            SyncDepositHandler__ValidateSharePriceTimestamp__SharePriceStale()
        );
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the deposit asset
    function getAsset() public view returns (address) {
        return __getSyncDepositHandlerStorage().asset;
    }

    /// @notice Returns the depositor address allowlist
    function getDepositorAllowlist() public view returns (address) {
        return __getSyncDepositHandlerStorage().depositorAllowlist;
    }

    /// @notice Returns the maximum allowed share price staleness in seconds
    function getMaxSharePriceStaleness() public view returns (uint24) {
        return __getSyncDepositHandlerStorage().maxSharePriceStaleness;
    }
}
