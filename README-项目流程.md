# 项目流程说明（README）

本文单独描述 **Trustless Agent System** 的**运行周期**、**用户/前后端交互**与 **EIP-712 签名验收流程**。实现细节见 `src/`；题目原文见 [`题目-候选人版.md`](./题目-候选人版.md)。

---

## 1. 三合约在流程中的位置

| 合约 | 在流程里做什么 |
|------|----------------|
| `AgentRegistry` | 先有 `agentId`（NFT），任务创建时校验存在且 `active`。 |
| `TaskEscrow` | 整条任务线：锁赏金 → `resultHash` → 客户验签 → 打款 / 超时退款。 |
| `ReputationRegistry` | 仅在 `completeTask` 成功路径被调用，写入该任务的评分与累计统计。 |

**部署顺序（一次）：** `AgentRegistry` → `ReputationRegistry` → `TaskEscrow` → `ReputationRegistry.setSettlement(escrow)`。

---

## 2. 任务状态机（周期）

```
（未创建）None
    ↓
Funded           —— 客户：createTask（锁 ERC20 或原生币）
    ↓
ResultSubmitted  —— Agent：submitResult(resultHash)
    ↓
Completed        —— 任意方：completeTask(score, signature)，验客户签名通过后打款 + 记信誉
```

**超时分支：** `block.timestamp > deadline`，且状态仍为 `Funded` 或 `ResultSubmitted`（从未成功 `completeTask`）时，**仅客户**可调 **`refund`** → `Refunded`，取回赏金。

---

## 3. 链上调用顺序与角色

| 步骤 | 合约函数 | 谁发交易 | 说明 |
|------|----------|----------|------|
| 0 | `AgentRegistry.registerAgent` 等 | Agent owner | 挂牌接单（题目要求的前置能力）。 |
| 1 | `TaskEscrow.createTask` | **客户**（`msg.sender` 记为 `client`） | 赏金进入托管。 |
| 2 | `TaskEscrow.submitResult` | **Agent**（须为该任务 `agentId` 的 NFT owner） | 上链交付承诺哈希，**不是** `completeTask`。 |
| 3 | 见 §5「签名流程」 | **客户**在钱包内操作 | 无结算交易，仅产生 `signature`。 |
| 4 | `TaskEscrow.completeTask` | **任意地址**（客户或 relayer） | 验签、改状态、打款、记信誉。 |
| 备选 | `TaskEscrow.refund` | **仅客户** | 超时退出。 |

要点：**`completeTask` 不由 Agent 调用**；Agent 只负责提交 `resultHash`。

---

## 4. 链上数据 vs 用户「看到结果」

- 链上只存 **`resultHash`（bytes32）** 与状态；**不存**报告/文件正文。
- **交付物内容**由 Agent **链下**交给客户；Dapp 展示、客户核对后，再进入验收签名。
- 可选：客户本地哈希交付物，与链上 **`resultHash`** 比对，再签名。
- 前端可监听 **`ResultSubmitted`**，将 UI 置为「待验收」。

---

## 5. 签名与验收流程（EIP-712）

### 5.1 三个概念

| 名称 | 含义 | 产生 / 使用位置 |
|------|------|-----------------|
| **digest** | EIP-712 最终 32 字节哈希（待签名消息） | 签名前由 `digestForCompleteTask` 或同逻辑本地算出；**`completeTask` 内会重算**同一 digest 做验证 |
| **signature** | 对 digest 的签名字节 | **仅链下**钱包生成；作为 **`completeTask(taskId, score, signature)`** 的入参 |
| **score** | 0–100，绑定进结构化消息 | 须在签名前确定；**`digestForCompleteTask` 与 `completeTask` 的 `score` 必须一致** |

合约**不能也不会「签名」**；只做 **验签**（`SignatureChecker`：EOA 用 ECDSA，合约钱包用 EIP-1271）。

### 5.2 `digest` 会不会作为 `completeTask` 入参？

**不会。** 入参只有 **`taskId`、`score`、`signature`**。链上根据存储中的 `resultHash`、`client`、`nonce` 等与 **`score`** 重算 **digest**，再验证 **`signature`**。这样以**链上状态为权威**，避免 digest 被恶意替换。

### 5.3 推荐前端交互顺序

1. 任务状态为 **`ResultSubmitted`**；客户已在页面查看链下交付物，并选定 **score**。
2. **`eth_call` `digestForCompleteTask(taskId, score)`**（或前端用与合约一致的 EIP-712 编码本地算 digest）。
3. **`signTypedData` / `eth_signTypedData_v4`**：钱包展示结构化字段，**客户确认** → 得到 **`signature`**。
4. 发送交易 **`completeTask(taskId, score, signature)`**。

### 5.4 `digestForCompleteTask` 与 `completeTask` 分工

| 函数 | 类型 | 作用 |
|------|------|------|
| `digestForCompleteTask` | `view` | 返回当前链上状态下、给定 **score** 时应对齐的 **digest**；**不验签、不打款** |
| `completeTask` | 状态更新 | 重算 digest，验 **signature**，通过后结算并记信誉 |

---

## 6. 事件（列表 / 通知 / 索引）

| 事件 | 用途 |
|------|------|
| `TaskCreated` | 新任务与锁仓信息 |
| `ResultSubmitted` | 可触发「待客户验收」 |
| `TaskCompleted` | 结算与信誉已写入 |
| `TaskRefunded` | 超时退款完成 |

---

## 7. 边界说明（流程认知）

链上保证：**身份与营业状态、托管与状态迁移、客户授权签名与打款、信誉写入规则**。链下 Agent 是否严格符合 metadata 描述，依赖产品与信誉等链外机制，**不单靠**链上文案强制执行。

---

## 相关链接

- [`README.md`](./README.md) — 仓库总览与开发命令  
- [`README-搭建步骤.md`](./README-搭建步骤.md) — 从零搭建工程步骤  
- [`题目-候选人版.md`](./题目-候选人版.md) — 题目与交付物要求  
