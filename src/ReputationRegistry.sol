// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Per-agent reputation; only the settlement contract (`TaskEscrow`) may record completions.
contract ReputationRegistry {
    address public immutable deployer;
    address public settlement;

    struct Stats {
        uint64 completedTasks;
        uint128 totalScore;
        uint64 lastUpdated;
    }

    mapping(uint256 agentId => Stats) public stats;
    mapping(uint256 taskId => bool) public taskScored;

    event ReputationUpdated(
        uint256 indexed agentId, uint256 indexed taskId, uint8 score, uint64 completedTasks, uint128 totalScore
    );

    constructor() {
        deployer = msg.sender;
    }

    function setSettlement(address settlement_) external {
        require(msg.sender == deployer, "Reputation: not deployer");
        require(settlement == address(0), "Reputation: already set");
        require(settlement_ != address(0), "Reputation: zero settlement");
        settlement = settlement_;
    }

    function recordCompletion(uint256 agentId, uint256 taskId, uint8 score) external {
        require(msg.sender == settlement, "Reputation: only settlement");
        require(score <= 100, "Reputation: bad score");
        require(!taskScored[taskId], "Reputation: duplicate task score");
        taskScored[taskId] = true;

        Stats storage s = stats[agentId];
        s.completedTasks += 1;
        s.totalScore += uint128(score);
        s.lastUpdated = uint64(block.timestamp);

        emit ReputationUpdated(agentId, taskId, score, s.completedTasks, s.totalScore);
    }
}
