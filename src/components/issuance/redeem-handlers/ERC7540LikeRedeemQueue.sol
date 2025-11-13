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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC7540LikeRedeemHandler} from "src/components/issuance/redeem-handlers/IERC7540LikeRedeemHandler.sol";
import {ERC7540LikeIssuanceBase} from "src/components/issuance/utils/ERC7540LikeIssuanceBase.sol";
import {ValuationHandler} from "src/components/value/ValuationHandler.sol";
import {IFeeHandler} from "src/interfaces/IFeeHandler.sol";
import {Shares} from "src/shares/Shares.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";
import {ValueHelpersLib} from "src/utils/ValueHelpersLib.sol";

/// @title ERC7540LikeRedeemQueue Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice A IERC7540LikeRedeemHandler implementation that manages requests as an ordered queue
/// @dev Does not enforce request execution in any particular order. If desired, this must be done peripherally.
/// Does not validate the sharePrice() timestamp.
contract ERC7540LikeRedeemQueue is IERC7540LikeRedeemHandler, ERC7540LikeIssuanceBase {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    /// @param controller The user who owns the request
    /// @param canCancelTime The time when the request can be canceled
    /// @param sharesAmount The amount of shares to redeem
    struct RedeemRequestInfo {
        address controller;
        uint40 canCancelTime;
        uint256 sharesAmount;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant REDEEM_QUEUE_STORAGE_LOCATION =
        0xbcb8ceea77a33ab0dcb8ebabd3acc0fa58368db4873ac11edccba71ee8fdbb00;
    string private constant REDEEM_QUEUE_STORAGE_LOCATION_ID = "RedeemQueue";

    /// @custom:storage-location erc7201:enzyme.RedeemQueue
    /// @param lastId Incrementing id for the most recent request (starts from `1`)
    /// @param minRequestDuration The minimum time between a request and the ability to cancel it
    /// @param idToRequest Mapping of request id to RedeemRequestInfo
    struct RedeemQueueStorage {
        uint128 lastId;
        uint24 minRequestDuration;
        mapping(uint256 => RedeemRequestInfo) idToRequest;
    }

    function __getRedeemQueueStorage() private pure returns (RedeemQueueStorage storage $) {
        bytes32 location = REDEEM_QUEUE_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event RedeemMinRequestDurationSet(uint24 minRequestDuration);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error ERC7540LikeRedeemQueue__CancelRequest__MinRequestDurationNotElapsed();

    error ERC7540LikeRedeemQueue__CancelRequest__Unauthorized();

    error ERC7540LikeRedeemQueue__ExecuteRedeemRequests__ZeroAssets();

    error ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotController();

    error ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotSender();

    error ERC7540LikeRedeemQueue__RequestRedeem__ZeroShares();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor() {
        StorageHelpersLib.verifyErc7201LocationForId({
            _location: REDEEM_QUEUE_STORAGE_LOCATION, _id: REDEEM_QUEUE_STORAGE_LOCATION_ID
        });
    }

    //==================================================================================================================
    // Config (access: admin or owner)
    //==================================================================================================================

    function setRedeemMinRequestDuration(uint24 _minRequestDuration) external onlyAdminOrOwner {
        __getRedeemQueueStorage().minRequestDuration = _minRequestDuration;

        emit RedeemMinRequestDurationSet({minRequestDuration: _minRequestDuration});
    }

    //==================================================================================================================
    // Required: IERC7540LikeRedeemHandler
    //==================================================================================================================

    /// @inheritdoc IERC7540LikeRedeemHandler
    function cancelRedeem(uint256 _requestId) external returns (uint256 shares_) {
        RedeemRequestInfo memory request = getRedeemRequest({_requestId: _requestId});

        require(msg.sender == request.controller, ERC7540LikeRedeemQueue__CancelRequest__Unauthorized());
        require(
            block.timestamp >= request.canCancelTime,
            ERC7540LikeRedeemQueue__CancelRequest__MinRequestDurationNotElapsed()
        );

        // Get shares amount to refund
        shares_ = request.sharesAmount;

        // Remove request
        __removeRedeemRequest(_requestId);

        // Refund shares to the controller
        Shares(__getShares()).authTransfer({_to: request.controller, _amount: shares_});

        emit RedeemRequestCanceled({requestId: _requestId});
    }

    /// @inheritdoc IERC7540LikeRedeemHandler
    /// @dev _controller, _owner, and msg.sender must all be the same. Support for distinct values may be added later.
    /// This helps prevent situations like unauthorized share transfers via request cancellation.
    function requestRedeem(uint256 _shares, address _controller, address _owner) external returns (uint256 requestId_) {
        require(_owner == msg.sender, ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotSender());
        require(_owner == _controller, ERC7540LikeRedeemQueue__RequestRedeem__OwnerNotController());
        require(_shares > 0, ERC7540LikeRedeemQueue__RequestRedeem__ZeroShares());

        uint40 canCancelTime = uint40(block.timestamp + getRedeemMinRequestDuration());

        // Increment id counter and add request to queue
        RedeemQueueStorage storage $ = __getRedeemQueueStorage();
        requestId_ = ++$.lastId; // Starts from 1
        $.idToRequest[requestId_] =
            RedeemRequestInfo({controller: _controller, sharesAmount: _shares, canCancelTime: canCancelTime});

        // Take shares from owner
        Shares(__getShares()).authTransferFrom(_owner, address(this), _shares);

        // Required event for ERC7540Like
        emit RedeemRequest({
            controller: _controller, owner: _owner, requestId: requestId_, sender: msg.sender, shares: _shares
        });
    }

    //==================================================================================================================
    // Request fulfillment
    //==================================================================================================================

    /// @notice Executes a list of requests, resulting in redeemed assets being transferred to each request's controller
    /// @param _requestIds The ids of the requests to execute
    function executeRedeemRequests(uint256[] memory _requestIds) external onlyAdminOrOwner {
        Shares shares = Shares(__getShares());
        IFeeHandler feeHandler = IFeeHandler(shares.getFeeHandler());
        ValuationHandler valuationHandler = ValuationHandler(shares.getValuationHandler());
        (uint256 sharePriceInValueAsset,) = valuationHandler.getSharePrice();

        // Fulfill requests
        for (uint256 i; i < _requestIds.length; i++) {
            uint128 requestId = _requestIds[i].toUint128();
            RedeemRequestInfo memory request = getRedeemRequest({_requestId: requestId});

            // Remove request
            __removeRedeemRequest({_requestId: requestId});

            // Settle any exit fee
            uint256 feeSharesAmount = address(feeHandler) == address(0)
                ? 0
                : feeHandler.settleExitFeeGivenGrossShares({_grossSharesAmount: request.sharesAmount});

            // Calculate the asset amount due for remaining shares post-fee
            uint256 valueDue = ValueHelpersLib.calcValueOfSharesAmount({
                _valuePerShare: sharePriceInValueAsset, _sharesAmount: request.sharesAmount - feeSharesAmount
            });
            uint256 userAssets = valuationHandler.convertValueToAssetAmount({_value: valueDue, _asset: asset()});
            require(userAssets > 0, ERC7540LikeRedeemQueue__ExecuteRedeemRequests__ZeroAssets());

            // Burn gross shares held by this contract
            shares.burnFor({_from: address(this), _sharesAmount: request.sharesAmount});

            // Send asset to the user
            shares.withdrawAssetTo({_asset: asset(), _to: request.controller, _amount: userAssets});

            // Required event for ERC7540
            emit Withdraw({
                sender: msg.sender,
                receiver: request.controller,
                owner: request.controller,
                assets: userAssets,
                shares: request.sharesAmount
            });

            emit RedeemRequestExecuted({requestId: requestId, assetAmount: userAssets});
        }
    }

    //==================================================================================================================
    // Misc helpers
    //==================================================================================================================

    /// @dev Helper to remove (zero-out) a redeem request
    function __removeRedeemRequest(uint256 _requestId) internal {
        RedeemQueueStorage storage $ = __getRedeemQueueStorage();
        delete $.idToRequest[_requestId];
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the id of the most recently-created redeem request
    function getRedeemLastId() public view returns (uint128) {
        return __getRedeemQueueStorage().lastId;
    }

    /// @notice Returns the minimum time duration before a redeem request is cancelable
    function getRedeemMinRequestDuration() public view returns (uint24) {
        return __getRedeemQueueStorage().minRequestDuration;
    }

    /// @notice Returns the redeem request for a given id
    function getRedeemRequest(uint256 _requestId) public view returns (RedeemRequestInfo memory) {
        return __getRedeemQueueStorage().idToRequest[_requestId];
    }
}
