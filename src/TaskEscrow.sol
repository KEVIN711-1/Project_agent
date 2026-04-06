// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReputationRegistry} from "./ReputationRegistry.sol";

interface IAgentRegistry {
    function ownerOf(uint256 tokenId) external view returns (address);
    function active(uint256 agentId) external view returns (bool);
}

/// @title TaskEscrow
/// @notice 任务托管：锁赏金 → Agent 提交结果哈希 → Client 用 EIP-712 授权完成与评分 → 打款并记信誉；超时 Client 可退款。
contract TaskEscrow is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAgentRegistry public immutable agentRegistry;
    ReputationRegistry public immutable reputationRegistry;

    /// @dev EIP-712 类型哈希：字段顺序与类型必须与链下钱包 `signTypedData` 完全一致，否则验签失败。
    ///      绑定 taskId / agentId / resultHash / client / score / nonce，防止跨任务、跨链、篡改内容或签名重放。
    bytes32 private constant COMPLETE_TYPEHASH =
        keccak256("CompleteTask(uint256 taskId,uint256 agentId,bytes32 resultHash,address client,uint256 score,uint256 nonce)");

    /// @dev 任务状态机（只允许向前迁移，不可逆）：
    ///      None → Funded（创建并锁仓）→ ResultSubmitted（Agent 提交 hash）→ Completed（验签打款）
    ///      或：Funded / ResultSubmitted 在超时后 → Refunded（仅 Client，且未完成结算）。
    enum TaskStatus {
        None,
        Funded,
        ResultSubmitted,
        Completed,
        Refunded
    }

    struct Task {
        uint256 taskId;
        uint256 agentId;
        address client;
        address rewardToken;
        uint256 rewardAmount;
        uint256 deadline;
        bytes32 resultHash;
        TaskStatus status;
    }

    uint256 public nextTaskId;
    mapping(uint256 taskId => Task) public tasks;

    /// @dev 每个 Client 的 EIP-712 签名 nonce：每成功 completeTask 一次 +1。
    ///      同一 Client 多笔任务共用计数，使旧签名无法在新任务上复用（还与 struct 里的 taskId 等字段共同防重放）。
    mapping(address client => uint256) public nonces;
    //创建任务
    event TaskCreated(
        uint256 indexed taskId,
        uint256 indexed agentId,
        address indexed client,
        address rewardToken,
        uint256 rewardAmount,
        uint256 deadline
    );
    //提交结果
    event ResultSubmitted(uint256 indexed taskId, bytes32 resultHash);
    //完成任务
    event TaskCompleted(uint256 indexed taskId, address indexed agent, uint256 score);
    //任务已退款
    event TaskRefunded(uint256 indexed taskId, address indexed client);

    constructor(address agentRegistry_, address reputationRegistry_)
        EIP712("TrustlessAgentTask", "1")
    {
        require(agentRegistry_ != address(0) && reputationRegistry_ != address(0), "TaskEscrow: zero address");
        agentRegistry = IAgentRegistry(agentRegistry_);
        reputationRegistry = ReputationRegistry(reputationRegistry_);
    }

    /// @notice 供前端/脚本计算当前链上状态下 Client 应对哪个 digest 做 EIP-712 签名（与 completeTask 内一致）。
    /// @dev 仅在 ResultSubmitted 时可调用：避免在 Agent 未提交结果前生成错误签名。
    function digestForCompleteTask(uint256 taskId, uint256 score) external view returns (bytes32) {
        Task storage t = tasks[taskId];
        require(t.status != TaskStatus.None, "TaskEscrow: no task");
        require(t.status == TaskStatus.ResultSubmitted, "TaskEscrow: not ready to sign");
        uint256 nonce = nonces[t.client];
        bytes32 structHash = keccak256(
            abi.encode(COMPLETE_TYPEHASH, taskId, t.agentId, t.resultHash, t.client, score, nonce)
        );
        // 拼接 EIP712Domain（本合约地址、chainId、name/version），得到钱包实际签名的 32 字节 digest
        return _hashTypedDataV4(structHash);
    }

    /// @notice Client 创建任务并锁定赏金；`rewardToken == address(0)` 表示原生币，否则为 ERC20（需事先 approve）。
    function createTask(uint256 agentId, address rewardToken, uint256 rewardAmount, uint256 deadline)
        external
        payable
        nonReentrant
        returns (uint256 taskId)
    {
        require(deadline > block.timestamp, "TaskEscrow: bad deadline");
        require(rewardAmount > 0, "TaskEscrow: zero reward");

        // 目标 Agent 必须已注册且处于营业状态（由 AgentRegistry 维护）
        address agentOwner = agentRegistry.ownerOf(agentId);
        require(agentOwner != address(0), "TaskEscrow: no agent");
        require(agentRegistry.active(agentId), "TaskEscrow: inactive agent");

        taskId = ++nextTaskId;

        if (rewardToken == address(0)) {
            // 原生币：赏金必须当笔随交易转入本合约
            require(msg.value == rewardAmount, "TaskEscrow: bad eth amount");
        } else {
            // ERC20：禁止误附 ETH；从 Client 拉取代币锁在本合约
            require(msg.value == 0, "TaskEscrow: no native with erc20");
            IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), rewardAmount);
        }

        tasks[taskId] = Task({
            taskId: taskId,
            agentId: agentId,
            client: msg.sender,
            rewardToken: rewardToken,
            rewardAmount: rewardAmount,
            deadline: deadline,
            resultHash: bytes32(0),
            status: TaskStatus.Funded
        });

        emit TaskCreated(taskId, agentId, msg.sender, rewardToken, rewardAmount, deadline);
    }

    /// @notice 当前任务的 Agent（NFT owner）提交链下交付物的承诺哈希；进入 ResultSubmitted 后 Client 才可签「完成」。
    function submitResult(uint256 taskId, bytes32 resultHash) external {
        require(resultHash != bytes32(0), "TaskEscrow: empty result hash");
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.Funded, "TaskEscrow: bad status for submit");
        require(block.timestamp <= t.deadline, "TaskEscrow: past deadline");
        // 仅该 agentId 对应 NFT 的 owner 可提交，防止他人冒充 Agent
        require(agentRegistry.ownerOf(t.agentId) == msg.sender, "TaskEscrow: not agent owner");

        t.resultHash = resultHash;
        t.status = TaskStatus.ResultSubmitted;
        emit ResultSubmitted(taskId, resultHash);
    }

    /// @notice 任意地址可代提交：携带 Client 对结构化数据的 EIP-712 签名；验签通过后向 Agent 支付并记信誉。
    /// @dev 安全顺序：先改状态并递增 client nonce，再外部转账（Checks-Effects-Interactions），配合 nonReentrant 降低重入风险。
    function completeTask(uint256 taskId, uint256 score, bytes calldata signature) external nonReentrant {
        require(score <= 100, "TaskEscrow: bad score");
        Task storage t = tasks[taskId];
        require(t.status == TaskStatus.ResultSubmitted, "TaskEscrow: bad status for complete");
        require(block.timestamp <= t.deadline, "TaskEscrow: past deadline");

        address client = t.client;
        uint256 nonce = nonces[client];
        // 与钱包侧相同的 struct 编码，再套 EIP-712 domain 得到 digest
        bytes32 structHash = keccak256(
            abi.encode(COMPLETE_TYPEHASH, taskId, t.agentId, t.resultHash, client, score, nonce)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        // EOA：ECDSA 恢复地址需等于 client；合约钱包：走 EIP-1271 isValidSignature(client, digest, sig)
        require(SignatureChecker.isValidSignatureNow(client, digest, signature), "TaskEscrow: bad signature");

        t.status = TaskStatus.Completed;
        nonces[client] = nonce + 1;

        address agent = agentRegistry.ownerOf(t.agentId);
        _payout(t.rewardToken, agent, t.rewardAmount);

        // Score is bounded by `require(score <= 100)` above; uint8 fits 0–100.
        // forge-lint: disable-next-line(unsafe-typecast)
        reputationRegistry.recordCompletion(t.agentId, taskId, uint8(score));

        emit TaskCompleted(taskId, agent, score);
    }

    /// @notice 超时后 Client 取回锁仓资金；若 Agent 已提交结果但 Client 未确认，仍可退款（产品层可另议）。
    function refund(uint256 taskId) external nonReentrant {
        Task storage t = tasks[taskId];
        require(msg.sender == t.client, "TaskEscrow: not client");
        require(block.timestamp > t.deadline, "TaskEscrow: not expired");
        require(
            t.status == TaskStatus.Funded || t.status == TaskStatus.ResultSubmitted,
            "TaskEscrow: bad status for refund"
        );

        uint256 amount = t.rewardAmount;
        address token = t.rewardToken;
        t.status = TaskStatus.Refunded;

        _payout(token, t.client, amount);
        emit TaskRefunded(taskId, t.client);
    }

    /// @dev 统一出口：原生币用 call 转账；ERC20 用 SafeERC20。
    function _payout(address token, address to, uint256 amount) internal {
        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            require(ok, "TaskEscrow: eth transfer failed");
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    receive() external payable {}
}
