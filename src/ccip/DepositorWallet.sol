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
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Client} from "@chainlink-ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink-ccip/interfaces/IRouterClient.sol";
import {StorageHelpersLib} from "src/utils/StorageHelpersLib.sol";

/// @title DepositorWallet Contract
/// @author Enzyme Foundation <security@enzyme.finance>
/// @notice Beacon proxy implementation for per-user wallet managed by WalletsManager
contract DepositorWallet is Initializable {
    using SafeERC20 for IERC20;

    //==================================================================================================================
    // Types
    //==================================================================================================================

    struct Call {
        address target;
        bytes data;
        uint256 value;
    }

    //==================================================================================================================
    // Storage
    //==================================================================================================================

    bytes32 private constant DEPOSITOR_WALLET_STORAGE_LOCATION =
        0xd45c63f1239e63c52aa6ab9a8e220e3763d69c34b1c0170e1ec31ad0f1375800;
    string private constant DEPOSITOR_WALLET_STORAGE_LOCATION_ID = "DepositorWallet";

    address public immutable CCIP_ROUTER;

    /// @custom:storage-location erc7201:enzyme.DepositorWallet
    struct DepositorWalletStorage {
        address walletsManager;
        uint64 chainSelector;
        bytes user;
    }

    function __getDepositorWalletStorage() private pure returns (DepositorWalletStorage storage $) {
        bytes32 location = DEPOSITOR_WALLET_STORAGE_LOCATION;
        assembly {
            $.slot := location
        }
    }

    //==================================================================================================================
    // Events
    //==================================================================================================================

    event CallExecuted(address target, bytes data, uint256 value);

    event CCIPMessageSent(bytes32 messageId, uint64 chainSelector, Client.EVM2AnyMessage message);

    event ChainSelectorSet(uint64 chainSelector);

    event UserSet(bytes user);

    event WalletsManagerSet(address walletsManager);

    //==================================================================================================================
    // Errors
    //==================================================================================================================

    error DepositorWallet__OnlyWalletsManager__Unauthorized();

    //==================================================================================================================
    // Modifiers
    //==================================================================================================================

    modifier onlyWalletsManager() {
        require(msg.sender == getWalletsManager(), DepositorWallet__OnlyWalletsManager__Unauthorized());

        _;
    }

    //==================================================================================================================
    // Constructor
    //==================================================================================================================

    constructor(address _ccipRouter) {
        CCIP_ROUTER = _ccipRouter;

        StorageHelpersLib.verifyErc7201LocationForId({
            _location: DEPOSITOR_WALLET_STORAGE_LOCATION, _id: DEPOSITOR_WALLET_STORAGE_LOCATION_ID
        });

        _disableInitializers();
    }

    //==================================================================================================================
    // Receive
    //==================================================================================================================

    receive() external payable {}

    //==================================================================================================================
    // Initialize
    //==================================================================================================================

    /// @notice Initializer for the contract
    /// @param _walletsManager The WalletsManager contract that manages this wallet
    /// @param _user The encoded user address on the source chain
    /// @param _chainSelector The CCIP chain selector for the user's source chain
    function init(address _walletsManager, bytes memory _user, uint64 _chainSelector) external initializer {
        __setWalletsManager(_walletsManager);
        __setUser(_user);
        __setChainSelector(_chainSelector);
    }

    //==================================================================================================================
    // Actions
    //==================================================================================================================

    /// @notice Approves tokens and sends a CCIP message to the user's source chain
    /// @param _message The CCIP message to send
    /// @param _feeValue The native currency value to send for CCIP fees
    function sendCCIPMessage(Client.EVM2AnyMessage memory _message, uint256 _feeValue)
        external
        payable
        onlyWalletsManager
    {
        for (uint256 i; i < _message.tokenAmounts.length; i++) {
            IERC20(_message.tokenAmounts[i].token)
                .forceApprove({spender: CCIP_ROUTER, value: _message.tokenAmounts[i].amount});
        }

        bool hasNativeFee = _message.feeToken == address(0);

        if (!hasNativeFee) {
            IERC20(_message.feeToken).safeIncreaseAllowance({spender: CCIP_ROUTER, value: _feeValue});
        }

        uint64 chainSelector = getChainSelector();

        bytes32 messageId = IRouterClient(CCIP_ROUTER).ccipSend{value: hasNativeFee ? _feeValue : 0}({
            destinationChainSelector: chainSelector, message: _message
        });

        emit CCIPMessageSent({messageId: messageId, chainSelector: chainSelector, message: _message});
    }

    /// @notice Builds a CCIP message with full token balances and computes the fee
    /// @param _tokens The token addresses (full balance of each)
    /// @param _extraArgs Extra args for CCIP message
    /// @param _feeToken The token to pay CCIP fees with (address(0) for native)
    /// @return message_ The built CCIP message
    /// @return fee_ The CCIP fee
    function buildTokenReturnMessage(address[] calldata _tokens, bytes calldata _extraArgs, address _feeToken)
        external
        view
        returns (Client.EVM2AnyMessage memory message_, uint256 fee_)
    {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](_tokens.length);
        for (uint256 i; i < _tokens.length; i++) {
            tokenAmounts[i] =
                Client.EVMTokenAmount({token: _tokens[i], amount: IERC20(_tokens[i]).balanceOf(address(this))});
        }

        message_ = Client.EVM2AnyMessage({
            receiver: getUser(), data: "", tokenAmounts: tokenAmounts, feeToken: _feeToken, extraArgs: _extraArgs
        });

        fee_ = IRouterClient(CCIP_ROUTER).getFee({destinationChainSelector: getChainSelector(), message: message_});

        return (message_, fee_);
    }

    /// @notice Executes a batch of calls from this wallet
    /// @param _calls The calls to execute
    function executeCalls(Call[] calldata _calls) external onlyWalletsManager {
        for (uint256 i; i < _calls.length; i++) {
            Address.functionCallWithValue({target: _calls[i].target, data: _calls[i].data, value: _calls[i].value});
            emit CallExecuted({target: _calls[i].target, data: _calls[i].data, value: _calls[i].value});
        }
    }

    //==================================================================================================================
    // Config
    //==================================================================================================================

    // HELPERS

    function __setWalletsManager(address _walletsManager) internal {
        __getDepositorWalletStorage().walletsManager = _walletsManager;

        emit WalletsManagerSet(_walletsManager);
    }

    function __setUser(bytes memory _user) internal {
        __getDepositorWalletStorage().user = _user;

        emit UserSet(_user);
    }

    function __setChainSelector(uint64 _chainSelector) internal {
        __getDepositorWalletStorage().chainSelector = _chainSelector;

        emit ChainSelectorSet(_chainSelector);
    }

    //==================================================================================================================
    // State getters
    //==================================================================================================================

    /// @notice Returns the WalletsManager contract address
    function getWalletsManager() public view returns (address) {
        return __getDepositorWalletStorage().walletsManager;
    }

    /// @notice Returns the encoded user address on the source chain
    function getUser() public view returns (bytes memory) {
        return __getDepositorWalletStorage().user;
    }

    /// @notice Returns the CCIP chain selector for the user's source chain
    function getChainSelector() public view returns (uint64) {
        return __getDepositorWalletStorage().chainSelector;
    }
}
