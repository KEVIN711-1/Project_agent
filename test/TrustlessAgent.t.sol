// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationRegistry} from "../src/ReputationRegistry.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev 测试用 ERC20，任意地址可 mint，便于模拟客户持有赏金代币。
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TrustlessAgentTest is Test {
    AgentRegistry internal registry;
    ReputationRegistry internal reputation;
    TaskEscrow internal escrow;
    MockERC20 internal token;

    uint256 internal agentOwnerKey = 0xA11CE;
    uint256 internal clientKey = 0xB0B;
    address internal agentOwner;
    address internal client;

    /// @dev 每个测试前：部署 AgentRegistry、ReputationRegistry、TaskEscrow，并把信誉的 settlement 设为 escrow。
    function setUp() public {
        agentOwner = vm.addr(agentOwnerKey);
        client = vm.addr(clientKey);

        registry = new AgentRegistry();
        reputation = new ReputationRegistry();
        escrow = new TaskEscrow(address(registry), address(reputation));
        reputation.setSettlement(address(escrow));

        token = new MockERC20();
    }

    /// @notice AgentRegistry：注册 NFT、owner 与 active；owner 可改 metadataURI；可停用再恢复；非 owner 不能改 URI。
    function test_registerAndMetadataAndActive() public {
        vm.startPrank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://a");
        assertEq(registry.ownerOf(agentId), agentOwner);
        assertTrue(registry.active(agentId));

        registry.setMetadataURI(agentId, "ipfs://b");
        assertEq(registry.tokenURI(agentId), "ipfs://b");

        registry.setActive(agentId, false);
        assertFalse(registry.active(agentId));
        registry.setActive(agentId, true);
        assertTrue(registry.active(agentId));
        vm.stopPrank();

        vm.expectRevert();
        registry.setMetadataURI(agentId, "x");
    }

    /// @notice 主路径（原生币）：注册 Agent → 客户 createTask 锁 ETH → Agent submitResult → 客户 EIP-712 digest 签名
    ///         → completeTask（由第三方地址代发也可）→ 状态 Completed、Agent 收款、信誉 +1 且 taskScored。
    function test_createTaskEth_submit_complete_reputation() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://agent");

        uint256 reward = 1 ether;
        uint256 deadline = block.timestamp + 1 days;

        vm.deal(client, reward);
        vm.prank(client);
        uint256 taskId = escrow.createTask{value: reward}(agentId, address(0), reward, deadline);

        bytes32 resultHash = keccak256("deliverable");
        vm.prank(agentOwner);
        escrow.submitResult(taskId, resultHash);

        uint256 score = 88;
        bytes32 digest = escrow.digestForCompleteTask(taskId, score);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 agentBalBefore = agentOwner.balance;
        vm.prank(address(0x1234));
        escrow.completeTask(taskId, score, sig);

        (, , , , , , , TaskEscrow.TaskStatus st) = escrow.tasks(taskId);
        assertEq(uint8(st), uint8(TaskEscrow.TaskStatus.Completed));
        assertEq(agentOwner.balance, agentBalBefore + reward);

        (uint64 completed, uint128 totalScore,) = reputation.stats(agentId);
        assertEq(completed, 1);
        assertEq(totalScore, score);
        assertTrue(reputation.taskScored(taskId));
    }

    /// @notice 防签名滥用：两笔任务各自 submitResult 后，对任务 1 的签名只能结任务 1；把同一 signature 用于任务 2 必须 revert。
    function test_replay_same_signature_rejected() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://agent");

        uint256 reward = 1 ether;
        vm.deal(client, reward * 2);
        vm.startPrank(client);
        uint256 t1 = escrow.createTask{value: reward}(agentId, address(0), reward, block.timestamp + 1 days);
        uint256 t2 = escrow.createTask{value: reward}(agentId, address(0), reward, block.timestamp + 1 days);
        vm.stopPrank();

        bytes32 h = keccak256("r1");
        vm.prank(agentOwner);
        escrow.submitResult(t1, h);
        vm.prank(agentOwner);
        escrow.submitResult(t2, h);

        uint256 score = 50;
        bytes32 digest1 = escrow.digestForCompleteTask(t1, score);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientKey, digest1);
        bytes memory sig1 = abi.encodePacked(r, s, v);
        escrow.completeTask(t1, score, sig1);

        bytes32 digest2 = escrow.digestForCompleteTask(t2, score);
        assertTrue(digest1 != digest2, "digests should differ (nonce or task fields)");

        vm.expectRevert(bytes("TaskEscrow: bad signature"));
        escrow.completeTask(t2, score, sig1);
    }

    /// @notice 超时退款：Funded 状态下超过 deadline 后客户 refund，赏金退回且状态变为 Refunded。
    function test_timeout_refund() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://agent");

        uint256 reward = 0.5 ether;
        vm.deal(client, reward);
        vm.prank(client);
        uint256 taskId = escrow.createTask{value: reward}(agentId, address(0), reward, block.timestamp + 1 hours);

        vm.warp(block.timestamp + 2 hours);
        uint256 beforeBal = client.balance;
        vm.prank(client);
        escrow.refund(taskId);
        assertEq(client.balance, beforeBal + reward);
        (, , , , , , , TaskEscrow.TaskStatus stRefund) = escrow.tasks(taskId);
        assertEq(uint8(stRefund), uint8(TaskEscrow.TaskStatus.Refunded));
    }

    /// @notice ERC20 赏金：approve + createTask（无 msg.value）→ submitResult → 签名 completeTask → Agent 收到代币。
    function test_erc20_flow() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://agent");

        uint256 reward = 100 ether;
        token.mint(client, reward);
        vm.startPrank(client);
        token.approve(address(escrow), reward);
        uint256 taskId =
            escrow.createTask(agentId, address(token), reward, block.timestamp + 1 days);
        vm.stopPrank();

        vm.prank(agentOwner);
        escrow.submitResult(taskId, keccak256("doc"));

        uint256 score = 10;
        bytes32 digest = escrow.digestForCompleteTask(taskId, score);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        escrow.completeTask(taskId, score, sig);
        assertEq(token.balanceOf(agentOwner), reward);
    }

    /// @notice 客户为合约钱包（MockERC1271Wallet）：createTask 的 client 为合约地址；由合约认可的 EOA 私钥签名 digest，completeTask 走 EIP-1271 验签成功。
    function test_eip1271_contract_wallet_client() public {
        vm.prank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://agent");

        address walletSigner = vm.addr(clientKey);
        MockERC1271Wallet wallet = new MockERC1271Wallet(walletSigner);
        address contractClient = address(wallet);

        uint256 reward = 2 ether;
        vm.deal(contractClient, reward);
        vm.prank(contractClient);
        uint256 taskId = escrow.createTask{value: reward}(agentId, address(0), reward, block.timestamp + 1 days);

        vm.prank(agentOwner);
        escrow.submitResult(taskId, keccak256("cw"));

        uint256 score = 77;
        bytes32 digest = escrow.digestForCompleteTask(taskId, score);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(clientKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        escrow.completeTask(taskId, score, sig);
        assertEq(agentOwner.balance, reward);
    }

    /// @notice Agent 已 deactivate 时，客户 createTask 应 revert（inactive agent）。
    function test_inactive_agent_cannot_create_task() public {
        vm.startPrank(agentOwner);
        uint256 agentId = registry.registerAgent("ipfs://a");
        registry.setActive(agentId, false);
        vm.stopPrank();

        vm.deal(client, 1 ether);
        vm.prank(client);
        vm.expectRevert(bytes("TaskEscrow: inactive agent"));
        escrow.createTask{value: 1 ether}(agentId, address(0), 1 ether, block.timestamp + 1 days);
    }
}
