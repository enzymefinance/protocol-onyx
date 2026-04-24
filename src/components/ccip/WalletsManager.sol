// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {CCIPReceiver} from "@chainlink-ccip/applications/CCIPReceiver.sol";
import {Client} from "@chainlink-ccip/libraries/Client.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {DeterministicBeaconFactory} from "src/factories/DeterministicBeaconFactory.sol";
import {DepositorWallet} from "src/ccip/DepositorWallet.sol";

/// @title WalletsManager Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Receives cross-chain CCIP messages and manages per-user DepositorWallet instances
contract WalletsManager is ComponentHelpersMixin, CCIPReceiver {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    struct BatchSendParams {
        address wallet;
        address[] tokens;
        bytes extraArgs;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    DeterministicBeaconFactory public immutable DEPOSITOR_WALLETS_FACTORY;

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event CCIPMessageProcessed(
        bytes32 messageId, uint64 sourceChainSelector, address wallet, Client.Any2EVMMessage message
    );

    event MessageDataProcessingFailed(bytes32 messageId, address wallet, bytes reason);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error WalletsManager__ProcessMessageData__OnlySelfCallAllowed();

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(address _ccipRouter, address _depositorWalletsFactory) CCIPReceiver(_ccipRouter) {
        DEPOSITOR_WALLETS_FACTORY = DeterministicBeaconFactory(_depositorWalletsFactory);
    }

    //==================================================================================================================
    // Actions
    //==================================================================================================================

    /// @dev Handles incoming CCIP messages: deploys wallet if needed, transfers tokens, executes calls,
    ///      and optionally returns tokens back to the source chain
    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        bytes memory user = _message.sender;
        uint64 sourceChainSelector = _message.sourceChainSelector;
        address wallet = __getOrDeployWallet({_sourceChainSelector: sourceChainSelector, _user: user});

        // Transfer received tokens to the user's wallet
        Client.EVMTokenAmount[] memory tokenAmounts = _message.destTokenAmounts;
        for (uint256 i; i < tokenAmounts.length; i++) {
            IERC20(tokenAmounts[i].token).safeTransfer({to: wallet, value: tokenAmounts[i].amount});
        }

        // Decode and process message data in a try-catch so failures do not revert token transfers
        if (_message.data.length > 0) {
            try this.processMessageData({_wallet: wallet, _data: _message.data}) {}
            catch (bytes memory reason) {
                emit MessageDataProcessingFailed({messageId: _message.messageId, wallet: wallet, reason: reason});
            }
        }

        emit CCIPMessageProcessed({
            messageId: _message.messageId, sourceChainSelector: sourceChainSelector, wallet: wallet, message: _message
        });
    }

    /// @dev Decodes and processes message data: executes calls and optionally returns tokens.
    ///      External so it can be used with try-catch; restricted to self-calls only.
    function processMessageData(address _wallet, bytes calldata _data) external {
        require(msg.sender == address(this), WalletsManager__ProcessMessageData__OnlySelfCallAllowed());

        (
            DepositorWallet.Call[] memory calls,
            address[] memory tokensToReturn,
            bytes memory extraArgs,
            address feeTokenForReturn
        ) = abi.decode(_data, (DepositorWallet.Call[], address[], bytes, address));

        if (calls.length > 0) {
            DepositorWallet(payable(_wallet)).executeCalls(calls);
        }

        if (tokensToReturn.length > 0) {
            (Client.EVM2AnyMessage memory message, uint256 fee) = DepositorWallet(payable(_wallet))
                .buildTokenReturnMessage({_tokens: tokensToReturn, _extraArgs: extraArgs, _feeToken: feeTokenForReturn});

            // deduct fee from that token's amount
            for (uint256 i; i < message.tokenAmounts.length; i++) {
                if (message.tokenAmounts[i].token == feeTokenForReturn) {
                    message.tokenAmounts[i].amount -= fee;
                    break;
                }
            }

            DepositorWallet(payable(_wallet)).sendCCIPMessage({_message: message, _feeValue: fee});
        }
    }

    /// @notice Sends tokens via CCIP from multiple wallets in a batch
    /// @param _params Array of batch send parameters
    function batchSendTokensViaCCIP(BatchSendParams[] calldata _params) external payable onlyAdminOrOwner {
        for (uint256 i; i < _params.length; i++) {
            DepositorWallet wallet = DepositorWallet(payable(_params[i].wallet));

            (Client.EVM2AnyMessage memory message, uint256 fee) = wallet.buildTokenReturnMessage({
                _tokens: _params[i].tokens, _extraArgs: _params[i].extraArgs, _feeToken: address(0)
            });

            wallet.sendCCIPMessage{value: fee}({_message: message, _feeValue: fee});
        }

        uint256 remaining = address(this).balance;
        if (remaining > 0) {
            Address.sendValue({recipient: payable(msg.sender), amount: remaining});
        }
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Computes the deterministic wallet address for a user without deploying
    /// @param _sourceChainSelector The source chain selector
    /// @param _user The user identifier (bytes)
    /// @return wallet_ The deterministic wallet address
    function computeWalletAddress(uint64 _sourceChainSelector, bytes memory _user)
        external
        view
        returns (address wallet_)
    {
        bytes32 walletHash = __getWalletHash(_sourceChainSelector, _user);

        return DEPOSITOR_WALLETS_FACTORY.computeProxyAddress({
            _deployer: address(this),
            _salt: walletHash,
            _initData: __encodeWalletInitData({_user: _user, _sourceChainSelector: _sourceChainSelector})
        });
    }

    //==================================================================================================================
    // Internal
    //==================================================================================================================

    /// @dev Computes a unique hash for a wallet from chain selector and user
    function __getWalletHash(uint64 _sourceChainSelector, bytes memory _user)
        internal
        pure
        returns (bytes32 walletHash_)
    {
        return keccak256(abi.encode(_sourceChainSelector, _user));
    }

    /// @dev Returns an existing wallet or deploys a new one for the user
    function __getOrDeployWallet(uint64 _sourceChainSelector, bytes memory _user) internal returns (address wallet_) {
        bytes32 walletHash = __getWalletHash(_sourceChainSelector, _user);
        bytes memory initData = __encodeWalletInitData({_user: _user, _sourceChainSelector: _sourceChainSelector});

        wallet_ = DEPOSITOR_WALLETS_FACTORY.computeProxyAddress({
            _deployer: address(this), _salt: walletHash, _initData: initData
        });

        if (wallet_.code.length == 0) {
            wallet_ = DEPOSITOR_WALLETS_FACTORY.deployProxy({_salt: walletHash, _initData: initData});
        }
    }

    /// @dev Encodes the init calldata for a new DepositorWallet proxy
    function __encodeWalletInitData(bytes memory _user, uint64 _sourceChainSelector)
        internal
        view
        returns (bytes memory initData_)
    {
        return abi.encodeWithSelector(DepositorWallet.init.selector, address(this), _user, _sourceChainSelector);
    }
}
