// SPDX-License-Identifier: BUSL-1.1

/*
    This file is part of the Onyx Protocol.

    (c) Enzyme Foundation <foundation@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {LimitedAccessLimitedCallForwarder} from "src/components/roles/LimitedAccessLimitedCallForwarder.sol";
import {OpenAccessLimitedCallForwarder} from "src/components/roles/OpenAccessLimitedCallForwarder.sol";
import {ComponentHelpersMixin} from "src/components/utils/ComponentHelpersMixin.sol";
import {IReceiver} from "src/components/automations/chainlink-cre/IReceiver.sol";
import {CreWorkflowConsumer} from "src/components/automations/chainlink-cre/CreWorkflowConsumer.sol";
import {Shares} from "src/shares/Shares.sol";

import {LimitedAccessLimitedCallForwarderHarness} from "test/harnesses/LimitedAccessLimitedCallForwarderHarness.sol";
import {CreWorkflowConsumerHarness} from "test/harnesses/CreWorkflowConsumerHarness.sol";
import {IChainlinkKeystoneForwarder} from "test/interfaces/IChainlinkKeystoneForwarder.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

address constant ETHEREUM_CHAINLINK_FORWARDER = 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885;

abstract contract CreWorkflowConsumerTestBase is TestHelpers {
    Shares shares;
    address owner;

    CreWorkflowConsumerHarness workflowConsumer;
    LimitedAccessLimitedCallForwarderHarness limitedAccessForwarder;

    IChainlinkKeystoneForwarder chainlinkKeystoneForwarder;

    address constant ALLOWED_WORKFLOW_OWNER = address(0x3); // mocked workflow owner
    bytes32 constant ALLOWED_WORKFLOW_ID = keccak256("workflowId");
    bytes10 constant ALLOWED_WORKFLOW_NAME = bytes10("workflow");

    function __initialize(address _chainlinkKeystoneForwarder) internal {
        shares = createShares();
        owner = shares.owner();

        chainlinkKeystoneForwarder = IChainlinkKeystoneForwarder(_chainlinkKeystoneForwarder);

        workflowConsumer = new CreWorkflowConsumerHarness({
            _shares: address(shares),
            _chainlinkKeystoneForwarder: address(chainlinkKeystoneForwarder),
            _allowedWorkflowOwner: ALLOWED_WORKFLOW_OWNER
        });

        limitedAccessForwarder = new LimitedAccessLimitedCallForwarderHarness({_shares: address(shares)});

        // Configure the workflow consumer
        workflowConsumer.init({
            _allowedWorkflowName: ALLOWED_WORKFLOW_NAME, _limitedAccessLimitedCallForwarder: limitedAccessForwarder
        });

        vm.prank(owner);
        workflowConsumer.setAllowedWorkflowId(ALLOWED_WORKFLOW_ID);
    }

    //==================================================================================================================
    // Helpers
    //==================================================================================================================

    function __encodeMetadata(bytes32 _workflowId, bytes10 _workflowName, address _workflowOwner)
        internal
        pure
        returns (bytes memory metadata_)
    {
        // Metadata structure:
        // - Offset 0, size 32: workflow_id (bytes32)
        // - Offset 32, size 10: workflow_name (bytes10)
        // - Offset 42, size 20: workflow_owner (address)
        metadata_ = abi.encodePacked(_workflowId, _workflowName, _workflowOwner);
    }

    //==================================================================================================================
    // supportsInterface
    //==================================================================================================================

    function test_supportsInterface_success_IReceiver() public view {
        bytes4 receiverInterfaceId = 0x805f2132;
        assertTrue(workflowConsumer.supportsInterface(receiverInterfaceId), "IReceiver not supported");
    }

    function test_supportsInterface_success_IERC165() public view {
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(workflowConsumer.supportsInterface(erc165InterfaceId), "IERC165 not supported");
    }

    function test_supportsInterface_success_unsupportedInterface() public view {
        bytes4 unsupportedInterfaceId = bytes4(keccak256("unsupported"));
        assertFalse(
            workflowConsumer.supportsInterface(unsupportedInterfaceId), "unsupported interface incorrectly supported"
        );
    }

    //==================================================================================================================
    // onReport
    //==================================================================================================================

    function test_onReport_fail_invalidSender() public {
        bytes memory metadata = __encodeMetadata(ALLOWED_WORKFLOW_ID, ALLOWED_WORKFLOW_NAME, ALLOWED_WORKFLOW_OWNER);
        bytes memory report = abi.encode(new OpenAccessLimitedCallForwarder.Call[](0));

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__OnReport__InvalidOnReportSender.selector);

        // Call from non-forwarder address
        workflowConsumer.onReport(metadata, report);
    }

    function test_onReport_fail_invalidWorkflowId() public {
        bytes32 wrongWorkflowId = keccak256("wrongWorkflowId");
        bytes memory metadata = __encodeMetadata(wrongWorkflowId, ALLOWED_WORKFLOW_NAME, ALLOWED_WORKFLOW_OWNER);
        bytes memory report = abi.encode(new OpenAccessLimitedCallForwarder.Call[](0));

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__OnReport__InvalidWorkflowId.selector);

        vm.prank(address(chainlinkKeystoneForwarder));
        workflowConsumer.onReport(metadata, report);
    }

    function test_onReport_fail_invalidWorkflowName() public {
        bytes10 wrongWorkflowName = bytes10("wrongName");
        bytes memory metadata = __encodeMetadata(ALLOWED_WORKFLOW_ID, wrongWorkflowName, ALLOWED_WORKFLOW_OWNER);
        bytes memory report = abi.encode(new OpenAccessLimitedCallForwarder.Call[](0));

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__OnReport__InvalidWorkflowName.selector);

        vm.prank(address(chainlinkKeystoneForwarder));
        workflowConsumer.onReport(metadata, report);
    }

    function test_onReport_fail_invalidWorkflowOwner() public {
        address wrongWorkflowOwner = makeAddr("wrongWorkflowOwner");
        bytes memory metadata = __encodeMetadata(ALLOWED_WORKFLOW_ID, ALLOWED_WORKFLOW_NAME, wrongWorkflowOwner);
        bytes memory report = abi.encode(new OpenAccessLimitedCallForwarder.Call[](0));

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__OnReport__InvalidWorkflowOwner.selector);

        vm.prank(address(chainlinkKeystoneForwarder));
        workflowConsumer.onReport(metadata, report);
    }

    function test_onReport_success_executesCalls() public {
        CallTarget callTarget = new CallTarget();

        // Configure the limited access forwarder
        vm.startPrank(owner);
        limitedAccessForwarder.addUser(address(workflowConsumer));
        limitedAccessForwarder.addCall({_target: address(callTarget), _selector: CallTarget.foo.selector});
        vm.stopPrank();

        assertEq(callTarget.value(), 0, "call target value incorrectly set before onReport");
        assertEq(callTarget.caller(), address(0), "call target caller incorrectly set before onReport");

        uint256 expectedValue = 42;

        // Prepare calls
        OpenAccessLimitedCallForwarder.Call[] memory calls = new OpenAccessLimitedCallForwarder.Call[](1);
        calls[0] = OpenAccessLimitedCallForwarder.Call({
            target: address(callTarget), data: abi.encodeWithSelector(CallTarget.foo.selector, expectedValue), value: 0
        });

        bytes memory metadata = __encodeMetadata(ALLOWED_WORKFLOW_ID, ALLOWED_WORKFLOW_NAME, ALLOWED_WORKFLOW_OWNER);
        bytes memory report = abi.encode(calls);

        // Add a mock forwarder address to the KeystoneForwarder's authorized forwarders list
        address mockForwarder = makeAddr("mockForwarder");
        address keystoneOwner = chainlinkKeystoneForwarder.owner();
        vm.prank(keystoneOwner);
        chainlinkKeystoneForwarder.addForwarder(mockForwarder);

        bytes32 transmissionId = keccak256("transmissionId");
        address transmitter = makeAddr("transmitter");

        // Call route from the authorized mock forwarder
        vm.prank(mockForwarder);
        bool success =
            chainlinkKeystoneForwarder.route(transmissionId, transmitter, address(workflowConsumer), metadata, report);

        assertTrue(success, "route call failed");
        assertEq(callTarget.value(), expectedValue, "call target value not set after onReport");
        assertEq(callTarget.caller(), address(limitedAccessForwarder), "call target caller not set after onReport");
    }

    //==================================================================================================================
    // setAllowedWorkflowId (access: admin or owner)
    //==================================================================================================================

    function test_setAllowedWorkflowId_fail_unauthorized() public {
        address randomUser = makeAddr("randomUser");

        vm.expectRevert(ComponentHelpersMixin.ComponentHelpersMixin__OnlyAdminOrOwner__Unauthorized.selector);

        vm.prank(randomUser);
        workflowConsumer.setAllowedWorkflowId(keccak256("newWorkflowId"));
    }

    function test_setAllowedWorkflowId_success() public {
        bytes32 newWorkflowId = keccak256("newWorkflowId");

        vm.expectEmit(address(workflowConsumer));
        emit CreWorkflowConsumer.AllowedWorkflowIdSet(newWorkflowId);

        vm.prank(owner);
        workflowConsumer.setAllowedWorkflowId(newWorkflowId);

        assertEq(workflowConsumer.getAllowedWorkflowId(), newWorkflowId, "allowed workflow id not set");
    }

    //==================================================================================================================
    // init
    //==================================================================================================================

    function test_init_fail_alreadyInitialized() public {
        LimitedAccessLimitedCallForwarderHarness newForwarder =
            new LimitedAccessLimitedCallForwarderHarness({_shares: address(shares)});

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__Init__AlreadyInitialized.selector);

        workflowConsumer.init({
            _allowedWorkflowName: bytes10("newName"), _limitedAccessLimitedCallForwarder: newForwarder
        });
    }

    function test_init_fail_emptyLimitedAccessLimitedCallForwarder() public {
        // Create a new uninitialized workflow consumer
        CreWorkflowConsumerHarness uninitializedWorkflowConsumer = new CreWorkflowConsumerHarness({
            _shares: address(shares),
            _chainlinkKeystoneForwarder: address(chainlinkKeystoneForwarder),
            _allowedWorkflowOwner: ALLOWED_WORKFLOW_OWNER
        });

        vm.expectRevert(CreWorkflowConsumer.CreWorkflowConsumer__Init__EmptyLimitedAccessLimitedCallForwarder.selector);

        uninitializedWorkflowConsumer.init({
            _allowedWorkflowName: ALLOWED_WORKFLOW_NAME,
            _limitedAccessLimitedCallForwarder: LimitedAccessLimitedCallForwarder(address(0))
        });
    }

    function test_init_success() public {
        // Create a new uninitialized workflow consumer
        CreWorkflowConsumerHarness uninitializedWorkflowConsumer = new CreWorkflowConsumerHarness({
            _shares: address(shares),
            _chainlinkKeystoneForwarder: address(chainlinkKeystoneForwarder),
            _allowedWorkflowOwner: ALLOWED_WORKFLOW_OWNER
        });

        LimitedAccessLimitedCallForwarderHarness newForwarder =
            new LimitedAccessLimitedCallForwarderHarness({_shares: address(shares)});
        bytes10 newWorkflowName = bytes10("newName");

        vm.expectEmit(address(uninitializedWorkflowConsumer));
        emit CreWorkflowConsumer.AllowedWorkflowNameSet(newWorkflowName);

        vm.expectEmit(address(uninitializedWorkflowConsumer));
        emit CreWorkflowConsumer.LimitedAccessLimitedCallForwarderSet(newForwarder);

        uninitializedWorkflowConsumer.init({
            _allowedWorkflowName: newWorkflowName, _limitedAccessLimitedCallForwarder: newForwarder
        });

        assertEq(
            uninitializedWorkflowConsumer.getAllowedWorkflowName(), newWorkflowName, "allowed workflow name not set"
        );
        assertEq(
            address(uninitializedWorkflowConsumer.getLimitedAccessLimitedCallForwarder()),
            address(newForwarder),
            "limited access limited call forwarder not set"
        );
    }
}

contract CreWorkflowConsumerTestEthereum is CreWorkflowConsumerTestBase {
    function setUp() public {
        createSelectEthereumFork();
        __initialize(ETHEREUM_CHAINLINK_FORWARDER);
    }
}

contract CallTarget {
    uint256 public value;
    address public caller;

    function foo(uint256 _value) external {
        value = _value;
        caller = msg.sender;
    }
}
