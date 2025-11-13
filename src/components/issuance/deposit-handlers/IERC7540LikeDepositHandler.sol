// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity ^0.8.0;

/// @title IERC7540LikeDepositHandler Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IERC7540LikeDepositHandler {
    //==================================================================================================================
    // ERC7540
    //==================================================================================================================

    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /// @notice Creates a new deposit request
    /// @param _assets The amount of assets to deposit
    /// @param _controller The account that will own the request
    /// @param _owner The account that owns the assets to be used in the deposit request
    /// @return requestId_ The id of the request
    function requestDeposit(uint256 _assets, address _controller, address _owner) external returns (uint256 requestId_);

    //==================================================================================================================
    // ERC4626
    //==================================================================================================================

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    //==================================================================================================================
    // Extensions
    //==================================================================================================================

    event DepositRequestCanceled(uint256 requestId);

    event DepositRequestExecuted(uint256 requestId, uint256 sharesAmount);

    event DepositRequestReferred(uint256 requestId, bytes32 referrer);

    /// @notice Cancels a deposit request
    /// @param _requestId The id of the request to cancel
    /// @return assets_ The amount of assets that were returned
    function cancelDeposit(uint256 _requestId) external returns (uint256 assets_);

    /// @notice Creates a new deposit request with a referrer
    /// @param _assets The amount of assets to deposit
    /// @param _controller The account that will own the request
    /// @param _owner The account that owns the assets to be used in the deposit request
    /// @param _referrer The referrer of the deposit request
    /// @return requestId_ The id of the request
    function requestDepositReferred(uint256 _assets, address _controller, address _owner, bytes32 _referrer)
        external
        returns (uint256 requestId_);
}
