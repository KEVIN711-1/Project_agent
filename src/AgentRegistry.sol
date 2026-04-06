// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/// @notice ERC-721 based Agent identity: metadataURI, active flag, owner-only updates.
contract AgentRegistry is ERC721URIStorage {
    uint256 private _nextAgentId;

    mapping(uint256 agentId => bool) public active;

    event AgentRegistered(uint256 indexed agentId, address indexed owner, string metadataURI);
    event MetadataUpdated(uint256 indexed agentId, string newURI);
    event AgentStatusChanged(uint256 indexed agentId, bool active);

    constructor() ERC721("TrustlessAgent", "TAGENT") {}

    function registerAgent(string calldata metadataURI_) external returns (uint256 agentId) {
        agentId = ++_nextAgentId;
        _safeMint(msg.sender, agentId);
        _setTokenURI(agentId, metadataURI_);
        active[agentId] = true;
        emit AgentRegistered(agentId, msg.sender, metadataURI_);
    }

    function setMetadataURI(uint256 agentId, string calldata newURI) external {
        require(_ownerOf(agentId) != address(0), "AgentRegistry: nonexistent agent");
        require(ownerOf(agentId) == msg.sender, "AgentRegistry: not agent owner");
        _setTokenURI(agentId, newURI);
        emit MetadataUpdated(agentId, newURI);
    }

    function setActive(uint256 agentId, bool active_) external {
        require(_ownerOf(agentId) != address(0), "AgentRegistry: nonexistent agent");
        require(ownerOf(agentId) == msg.sender, "AgentRegistry: not agent owner");
        active[agentId] = active_;
        emit AgentStatusChanged(agentId, active_);
    }
}
