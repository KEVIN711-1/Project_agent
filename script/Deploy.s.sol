// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {AgentRegistry} from "../src/AgentRegistry.sol";
import {ReputationRegistry} from "../src/ReputationRegistry.sol";
import {TaskEscrow} from "../src/TaskEscrow.sol";

/// @notice 部署顺序：AgentRegistry → ReputationRegistry → TaskEscrow → setSettlement(escrow)。
contract DeployScript is Script {
    function run() external {
        vm.startBroadcast();

        AgentRegistry registry = new AgentRegistry();
        ReputationRegistry reputation = new ReputationRegistry();
        TaskEscrow escrow = new TaskEscrow(address(registry), address(reputation));
        reputation.setSettlement(address(escrow));

        vm.stopBroadcast();

        console2.log("AgentRegistry:", address(registry));
        console2.log("ReputationRegistry:", address(reputation));
        console2.log("TaskEscrow:", address(escrow));

        //AgentRegistry: 0x5FbDB2315678afecb367f032d93F642f64180aa3
        //ReputationRegistry: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
        //TaskEscrow: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
    }
}
