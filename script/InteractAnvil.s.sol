// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";
import {ReputationRegistry} from "../src/ReputationRegistry.sol";

/// @notice 在已部署的合约上跑通一条最小任务流（Anvil 默认账户 #0=Agent owner，#1=Client）。
/// @dev 需设置环境变量：REGISTRY_ADDRESS、ESCROW_ADDRESS、REPUTATION_ADDRESS（部署日志里的三个地址）。
contract InteractAnvil is Script {
    uint256 internal constant AGENT_PK =
        uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
    uint256 internal constant CLIENT_PK =
        uint256(0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d);

    function run() external {
        AgentRegistry registry = AgentRegistry(vm.envAddress("REGISTRY_ADDRESS"));
        TaskEscrow escrow = TaskEscrow(payable(vm.envAddress("ESCROW_ADDRESS")));
        ReputationRegistry reputation = ReputationRegistry(vm.envAddress("REPUTATION_ADDRESS"));

        vm.startBroadcast(AGENT_PK);
        uint256 agentId = registry.registerAgent("ipfs://interact-demo");
        vm.stopBroadcast();
        console2.log("agentId", agentId);

        uint256 deadline = block.timestamp + 1 days;
        vm.startBroadcast(CLIENT_PK);
        uint256 taskId = escrow.createTask{value: 1 ether}(agentId, address(0), 1 ether, deadline);
        vm.stopBroadcast();
        console2.log("taskId", taskId);

        vm.startBroadcast(AGENT_PK);
        escrow.submitResult(taskId, keccak256("demo-deliverable"));
        vm.stopBroadcast();

        bytes32 digest = escrow.digestForCompleteTask(taskId, 90);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(CLIENT_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.startBroadcast(CLIENT_PK);
        escrow.completeTask(taskId, 90, sig);
        vm.stopBroadcast();

        (, , , , , , , TaskEscrow.TaskStatus st) = escrow.tasks(taskId);
        (uint64 completed, uint128 totalScore,) = reputation.stats(agentId);
        console2.log("taskStatus (3=Completed)", uint256(st));
        console2.log("reputation.completedTasks", completed);
        console2.log("reputation.totalScore", totalScore);
    }
}
