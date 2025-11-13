// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IManagementFeeTracker} from "src/components/fees/interfaces/IManagementFeeTracker.sol";
import {IPerformanceFeeTracker} from "src/components/fees/interfaces/IPerformanceFeeTracker.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {Shares} from "src/shares/Shares.sol";
import {ONE_HUNDRED_PERCENT_BPS} from "src/utils/Constants.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title FeeHandler Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Manages fees for a Shares contract
contract FeeHandler is IFeeHandler, ComponentHelpersMixin {
    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant FEE_HANDLER_STORAGE_LOCATION =
        0xf4d55ff99bda85c3aa25c0487eafd29734b8b8c0e94e473480bb8c25cf2aa300;
    string private constant FEE_HANDLER_STORAGE_LOCATION_ID = "FeeHandler";

    /// @custom:storage-location erc7201:enzyme.FeeHandler
    /// @param managementFeeTracker IManagementFeeTracker contract address
    /// @param performanceFeeTracker IPerformanceFeeTracker contract address
    /// @param managementFeeRecipient Recipient of management fees
    /// @param performanceFeeRecipient Recipient of performance fees
    /// @param entranceFeeRecipient Recipient of entrance fees (burned if `address(0)`)
    /// @param entranceFeeBps Entrance fee percentage
    /// @param exitFeeRecipient Recipient of exit fees (burned if `address(0)`)
    /// @param exitFeeBps Exit fee percentage
    /// @param feeAsset ERC20 asset used to pay out fees
    /// @param totalFeesOwed Total fees owed, in Shares value asset (18-decimal precision)
    /// @param userFeesOwed Fees owed per user, in Shares value asset (18-decimal precision)
    struct FeeHandlerStorage {
        address managementFeeTracker;
        address performanceFeeTracker;
        address managementFeeRecipient;
        address performanceFeeRecipient;
        address entranceFeeRecipient;
        uint16 entranceFeeBps;
        address exitFeeRecipient;
        uint16 exitFeeBps;
        address feeAsset;
        uint256 totalFeesOwed;
        mapping(address => uint256) userFeesOwed;
    }

    function __getFeeHandlerStorage() private pure returns (FeeHandlerStorage storage $) {
        bytes32 location = FEE_HANDLER_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event EntranceFeeSet(uint16 feeBps, address recipient);

    event EntranceFeeSettled(address recipient, uint256 value);

    event ExitFeeSet(uint16 feeBps, address recipient);

    event ExitFeeSettled(address recipient, uint256 value);

    event FeeAssetSet(address asset);

    event FeesClaimed(address onBehalf, uint256 value, address feeAsset, uint256 feeAssetAmount);

    event ManagementFeeSet(address managementFeeTracker, address recipient);

    event ManagementFeeSettled(address recipient, uint256 value);

    event PerformanceFeeSet(address performanceFeeTracker, address recipient);

    event PerformanceFeeSettled(address recipient, uint256 value);

    event TotalValueOwedUpdated(uint256 value);

    event UserValueOwedUpdated(address user, uint256 value);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error FeeHandler__ClaimFees__ZeroFeeAsset();

    error FeeHandler__SetEntranceFee__ExceedsMax();

    error FeeHandler__SetExitFee__ExceedsMax();

    error FeeHandler__SetManagementFee__RecipientZeroAddress();

    error FeeHandler__SetPerformanceFee__RecipientZeroAddress();

    error FeeHandler__SettleDynamicFeesGivenPositionsValue__Unauthorized();

    error FeeHandler__SettleEntranceFeeGivenGrossShares__Unauthorized();

    error FeeHandler__SettleExitFeeGivenGrossShares__Unauthorized();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: FEE_HANDLER_STORAGE_LOCATION, _id: FEE_HANDLER_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: Shares admin or owner)
    //==================================================================================================================

    function setEntranceFee(uint16 _feeBps, address _recipient) external onlyAdminOrOwner {
        require(_feeBps < ONE_HUNDRED_PERCENT_BPS, FeeHandler__SetEntranceFee__ExceedsMax());

        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.entranceFeeBps = _feeBps;
        $.entranceFeeRecipient = _recipient;

        emit EntranceFeeSet({feeBps: _feeBps, recipient: _recipient});
    }

    function setExitFee(uint16 _feeBps, address _recipient) external onlyAdminOrOwner {
        require(_feeBps < ONE_HUNDRED_PERCENT_BPS, FeeHandler__SetExitFee__ExceedsMax());

        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.exitFeeBps = _feeBps;
        $.exitFeeRecipient = _recipient;

        emit ExitFeeSet({feeBps: _feeBps, recipient: _recipient});
    }

    function setFeeAsset(address _asset) external onlyAdminOrOwner {
        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.feeAsset = _asset;

        emit FeeAssetSet({asset: _asset});
    }

    /// @dev _managementFeeTracker can be empty (to disable)
    /// _recipient cannot be empty (unused if disabled)
    function setManagementFee(address _managementFeeTracker, address _recipient) external onlyAdminOrOwner {
        require(_recipient != address(0), FeeHandler__SetManagementFee__RecipientZeroAddress());

        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.managementFeeTracker = _managementFeeTracker;
        $.managementFeeRecipient = _recipient;

        emit ManagementFeeSet({managementFeeTracker: address(_managementFeeTracker), recipient: _recipient});
    }

    /// @dev _performanceFeeTracker can be empty (to disable)
    /// _recipient cannot be empty (unused if disabled)
    function setPerformanceFee(address _performanceFeeTracker, address _recipient) external onlyAdminOrOwner {
        require(_recipient != address(0), FeeHandler__SetPerformanceFee__RecipientZeroAddress());

        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.performanceFeeTracker = _performanceFeeTracker;
        $.performanceFeeRecipient = _recipient;

        emit PerformanceFeeSet({performanceFeeTracker: address(_performanceFeeTracker), recipient: _recipient});
    }

    //==================================================================================================================
    // Claim Fees
    //==================================================================================================================

    /// @notice Claims fees owed to a given user
    /// @param _onBehalf The account for which to claim fees
    /// @param _value The value of fees owed to claim, in the Shares value asset (18-decimal precision)
    /// @return feeAssetAmount_ The amount of the fee asset transferred to _onBehalf
    /// @dev Only callable by admin, in order to give discretion on when fees are paid out.
    /// Fees are paid in the current fee asset set in this contract.
    function claimFees(address _onBehalf, uint256 _value) external onlyAdminOrOwner returns (uint256 feeAssetAmount_) {
        // `_value > owed` reverts in __decreaseValueOwed()

        Shares shares = Shares(__getShares());
        ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());
        address feeAsset = getFeeAsset();

        feeAssetAmount_ = valuationHandler.convertValueToAssetAmount({_value: _value, _asset: feeAsset});
        require(feeAssetAmount_ > 0, FeeHandler__ClaimFees__ZeroFeeAsset());

        __decreaseValueOwed({_user: _onBehalf, _delta: _value});

        shares.withdrawAssetTo({_asset: feeAsset, _to: _onBehalf, _amount: feeAssetAmount_});

        emit FeesClaimed({onBehalf: _onBehalf, value: _value, feeAsset: feeAsset, feeAssetAmount: feeAssetAmount_});
    }

    //==================================================================================================================
    // Settle Fees
    //==================================================================================================================

    /// @notice Settles dynamic fees (management and performance fees), updating fees owed
    /// @param _totalPositionsValue Total value of all Shares' positions, in the Shares value asset (18-decimal precision)
    /// @dev Callable by: ValuationHandler.
    /// `_totalPositionsValue` must not include any unclaimed fees from this contract
    function settleDynamicFeesGivenPositionsValue(uint256 _totalPositionsValue) external override {
        require(
            msg.sender == Shares(__getShares()).getValuationHandler(),
            FeeHandler__SettleDynamicFeesGivenPositionsValue__Unauthorized()
        );

        // Deduct unclaimed fees
        uint256 netValue = _totalPositionsValue - getTotalValueOwed();

        uint256 managementFeeAmount;
        if (getManagementFeeTracker() != address(0)) {
            managementFeeAmount =
                IManagementFeeTracker(getManagementFeeTracker()).settleManagementFee({_netValue: netValue});

            __increaseValueOwed({_user: getManagementFeeRecipient(), _delta: managementFeeAmount});

            emit ManagementFeeSettled({recipient: getManagementFeeRecipient(), value: managementFeeAmount});
        }

        uint256 performanceFeeAmount;
        if (getPerformanceFeeTracker() != address(0)) {
            // Deduct management fee
            netValue -= managementFeeAmount;

            performanceFeeAmount =
                IPerformanceFeeTracker(getPerformanceFeeTracker()).settlePerformanceFee({_netValue: netValue});

            __increaseValueOwed({_user: getPerformanceFeeRecipient(), _delta: performanceFeeAmount});

            emit PerformanceFeeSettled({recipient: getPerformanceFeeRecipient(), value: performanceFeeAmount});
        }
    }

    /// @notice Settles entrance fee, updating fees owed
    /// @param _grossSharesAmount The gross shares amount on which to calculate the fee
    /// @return feeSharesAmount_ The settled fee amount, in shares
    /// @dev Callable by: DepositHandler
    function settleEntranceFeeGivenGrossShares(uint256 _grossSharesAmount)
        external
        override
        returns (uint256 feeSharesAmount_)
    {
        require(
            Shares(__getShares()).isDepositHandler(msg.sender),
            FeeHandler__SettleEntranceFeeGivenGrossShares__Unauthorized()
        );

        return __settleEntranceExitFee({_grossSharesAmount: _grossSharesAmount, _isEntrance: true});
    }

    /// @notice Settles exit fee, updating fees owed
    /// @param _grossSharesAmount The gross shares amount on which to calculate the fee
    /// @return feeSharesAmount_ The settled fee amount, in shares
    /// @dev Callable by: RedeemHandler
    function settleExitFeeGivenGrossShares(uint256 _grossSharesAmount)
        external
        override
        returns (uint256 feeSharesAmount_)
    {
        require(
            Shares(__getShares()).isRedeemHandler(msg.sender), FeeHandler__SettleExitFeeGivenGrossShares__Unauthorized()
        );

        return __settleEntranceExitFee({_grossSharesAmount: _grossSharesAmount, _isEntrance: false});
    }

    // INTERNAL

    function __calcEntranceExitFee(uint256 _grossSharesAmount, uint16 _feeBps)
        internal
        pure
        returns (uint256 feeShares_)
    {
        return (_grossSharesAmount * _feeBps) / ONE_HUNDRED_PERCENT_BPS;
    }

    function __settleEntranceExitFee(uint256 _grossSharesAmount, bool _isEntrance)
        internal
        returns (uint256 feeSharesAmount_)
    {
        (uint16 feeBps, address recipient) = _isEntrance
            ? (getEntranceFeeBps(), getEntranceFeeRecipient())
            : (getExitFeeBps(), getExitFeeRecipient());
        if (feeBps == 0) return 0;

        feeSharesAmount_ = __calcEntranceExitFee({_grossSharesAmount: _grossSharesAmount, _feeBps: feeBps});
        if (feeSharesAmount_ == 0) return 0;

        // Query "share price" rather than "share value", for case of no shares supply on mint
        (uint256 sharePrice,) = Shares(__getShares()).sharePrice();
        uint256 value =
            ValueHelpersLib.calcValueOfSharesAmount({_valuePerShare: sharePrice, _sharesAmount: feeSharesAmount_});

        if (recipient != address(0)) {
            __increaseValueOwed({_user: recipient, _delta: value});
        }
        // Effectively "burn" the fee if no recipient, as shares will be destroyed but no value owed

        if (_isEntrance) {
            emit EntranceFeeSettled({recipient: recipient, value: value});
        } else {
            emit ExitFeeSettled({recipient: recipient, value: value});
        }
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __decreaseValueOwed(address _user, uint256 _delta) internal {
        uint256 userValueOwed = getValueOwedToUser(_user) - _delta;
        uint256 totalValueOwed = getTotalValueOwed() - _delta;

        __updateValueOwed({_user: _user, _userValueOwed: userValueOwed, _totalValueOwed: totalValueOwed});
    }

    function __increaseValueOwed(address _user, uint256 _delta) internal {
        uint256 userValueOwed = getValueOwedToUser(_user) + _delta;
        uint256 totalValueOwed = getTotalValueOwed() + _delta;

        __updateValueOwed({_user: _user, _userValueOwed: userValueOwed, _totalValueOwed: totalValueOwed});
    }

    function __updateValueOwed(address _user, uint256 _userValueOwed, uint256 _totalValueOwed) internal {
        FeeHandlerStorage storage $ = __getFeeHandlerStorage();
        $.userFeesOwed[_user] = _userValueOwed;
        $.totalFeesOwed = _totalValueOwed;

        emit UserValueOwedUpdated({user: _user, value: _userValueOwed});
        emit TotalValueOwedUpdated({value: _totalValueOwed});
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the entrance fee percentage
    function getEntranceFeeBps() public view returns (uint16 entranceFeeBps_) {
        return __getFeeHandlerStorage().entranceFeeBps;
    }

    /// @notice Returns the entrance fee recipient
    function getEntranceFeeRecipient() public view returns (address entranceFeeRecipient_) {
        return __getFeeHandlerStorage().entranceFeeRecipient;
    }

    /// @notice Returns the exit fee percentage
    function getExitFeeBps() public view returns (uint16 exitFeeBps_) {
        return __getFeeHandlerStorage().exitFeeBps;
    }

    /// @notice Returns the exit fee recipient
    function getExitFeeRecipient() public view returns (address exitFeeRecipient_) {
        return __getFeeHandlerStorage().exitFeeRecipient;
    }

    /// @notice Returns the asset used to pay out fee claims
    function getFeeAsset() public view returns (address feeAsset_) {
        return __getFeeHandlerStorage().feeAsset;
    }

    /// @notice Returns the management fee recipient
    function getManagementFeeRecipient() public view returns (address managementFeeRecipient_) {
        return __getFeeHandlerStorage().managementFeeRecipient;
    }

    /// @notice Returns the ManagementFeeTracker instance (no management fee if empty)
    function getManagementFeeTracker() public view returns (address managementFeeTracker_) {
        return __getFeeHandlerStorage().managementFeeTracker;
    }

    /// @notice Returns the performance fee recipient
    function getPerformanceFeeRecipient() public view returns (address performanceFeeRecipient_) {
        return __getFeeHandlerStorage().performanceFeeRecipient;
    }

    /// @notice Returns the PerformanceFeeTracker instance (no performance fee if empty)
    function getPerformanceFeeTracker() public view returns (address performanceFeeTracker_) {
        return __getFeeHandlerStorage().performanceFeeTracker;
    }

    /// @notice Returns the total value of fees owed (in Shares value asset)
    function getTotalValueOwed() public view override returns (uint256 totalValueOwed_) {
        return __getFeeHandlerStorage().totalFeesOwed;
    }

    /// @notice Returns the value of fees owed per user (in Shares value asset)
    function getValueOwedToUser(address _user) public view returns (uint256 valueOwed_) {
        return __getFeeHandlerStorage().userFeesOwed[_user];
    }
}
