// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeRedeemHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IERC7540LikeRedeemHandler {
    //==================================================================================================================
    // ERC7540
    //==================================================================================================================

    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /// @notice Creates a new redeem request
    /// @param _shares The amount of shares to redeem
    /// @param _controller The account that will own the request
    /// @param _owner The account that owns the shares to be used in the redeem request
    /// @return requestId_ The id of the request
    function requestRedeem(uint256 _shares, address _controller, address _owner) external returns (uint256 requestId_);

    //==================================================================================================================
    // ERC4626
    //==================================================================================================================

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    //==================================================================================================================
    // Extensions
    //==================================================================================================================

    event RedeemRequestCanceled(uint256 requestId);

    event RedeemRequestExecuted(uint256 requestId, uint256 assetAmount);

    /// @notice Cancels a redeem request
    /// @param _requestId The id of the request to cancel
    /// @return shares_ The amount of shares that were returned
    function cancelRedeem(uint256 _requestId) external returns (uint256 shares_);
}
