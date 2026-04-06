# 项目搭建步骤（按题目交付）

本文说明如何从零把题目要求的 **Solidity 合约 + 单元测试 + 设计说明** 搭起来。可与根目录 [`README.md`](./README.md)（业务流程概括）对照阅读。

---

## 阶段 0：环境与工具

1. **选定工具链**（二选一即可）  
   - **Foundry**：`forge init`，测试用 Solidity 或 Rust 风格，迭代快。  
   - **Hardhat**：`npm init` + hardhat，常用 TypeScript 写测例。  

2. **固定版本**  
   - Solidity 版本与编译器在 `foundry.toml` / `hardhat.config` 里写死，避免与 OpenZeppelin 要求冲突。  

3. **依赖**  
   - 引入 **OpenZeppelin**（`ERC721`、`EIP712`、`ECDSA`、`ReentrancyGuard`、`IERC1271` 等），减少手写错误。  

4. **可选**  
   - `forge fmt` / Prettier 统一格式；`.env` 仅放私钥用于部署演示，**不要提交仓库**。

---

## 阶段 1：初始化仓库结构

1. 建立合约目录，例如：  
   `src/` 或 `contracts/`：`AgentRegistry.sol`、`TaskEscrow.sol`、（可选）`ReputationRegistry.sol`。  
2. 建立测试目录：`test/` 或 `test/` + mocks。  
3. 预留 **Mock**：`MockERC1271Wallet.sol`（返回 `0x1626ba7e...` 或按 digest 可控），用于合约钱包验签场景。  

**本阶段完成标志**：空合约能 `forge build` / `npx hardhat compile` 通过。

---

## 阶段 2：实现 Agent Registry（ERC721）

1. 继承 `ERC721`，`tokenId` 与题目中的 `agentId` 对齐（或显式字段映射）。  
2. 字段：`owner`（由 NFT 表达）、`metadataURI`、`active`；可选 `validator`、`endpointHash`。  
3. 函数：`mint`/`register`、`setTokenURI` 或自定义 `setMetadataURI`（**仅 owner**）、`setActive` 停用与恢复。  
4. **错误处理**：不存在 token、非 owner 更新、无效输入；**事件**：注册、元数据更新、状态变更。  
5. **测试**：注册、改 metadata、停用/恢复、越权失败。

---

## 阶段 3：实现 Task Escrow（先不接签名）

1. **数据结构**：`Task` 含 `taskId`、`agentId`、`client`、`rewardToken`（0 表示原生币）、`rewardAmount`、`deadline`、`resultHash`、`status`。  
2. **状态机**（建议）：`Funded` → `ResultSubmitted` → `Completed`；以及 `Refunded`；明确禁止重复结算、重复退款。  
3. **`createTask`**：校验 `agentId` 存在且 `active`；ERC20 `transferFrom` 或 `msg.value` 锁仓。  
4. **`submitResult`**：仅 **AgentRegistry.ownerOf(agentId)** 可调；仅允许状态从 `Funded` 进入 `ResultSubmitted`；写入 `resultHash`。  
5. **测试**：创建并锁仓、Agent 提交结果、非 Agent 失败、重复提交失败。

---

## 阶段 4：EIP-712 验收与打款

1. 在 `TaskEscrow` 中继承/使用 **EIP712**，定义 **domain** 与 **struct hash**（类型字符串与字段顺序固定）。  
2. 签名消息建议绑定：`taskId`、`agentId`、`resultHash`、`client`、`score`、`nonce`、`deadline`（或与链上存储一致的最小集合），防止跨任务/跨合约重放。  
3. **`nonce`**：按 `client` 递增，或按 `taskId` 单次消费；设计说明里写清一种即可。  
4. **`completeTask`**：  
   - 状态必须为 `ResultSubmitted`；  
   - 恢复/校验签名者与任务的 `client` 一致；  
   - 验签通过后：状态 → `Completed`，**再**转账给 Agent（Checks-Effects-Interactions）；  
   - 使用 `nonReentrant` 保护外部转账。  
5. **测试**：EOA 签名成功、错误 task/错误 hash 失败、**同一签名二次调用失败**。

---

## 阶段 5：EIP-1271（合约钱包 Client）

1. 在 `completeTask` 中：`client.code.length == 0` 走 **ECDSA**；否则调 **`isValidSignature(hash, sig)`**，比对魔法值 `0x1626ba7e...`。  
2. 用 **MockERC1271Wallet** 模拟通过/拒绝。  
3. **测试**：合约钱包签名结算成功、非法签名失败。

---

## 阶段 6：信誉（二选一）

**方案 A — 独立 `ReputationRegistry`**  
1. 构造或一次性设置 **仅 `TaskEscrow` 可写**。  
2. `recordCompletion(agentId, score)`：`score` 限制 0–100；内部或 Escrow 侧保证 **每 `taskId` 只记一次**。  
3. 在 `completeTask` 成功路径末尾调用。  

**方案 B — 写入 `TaskEscrow` 内**  
1. 同字段：`completedCount`、`totalScore`、`lastUpdated`。  
2. `mapping(taskId => bool) reputationRecorded` 防重复记分。  

**测试**：结算后数值正确、重复结算不重复加分、非授权地址不能写信誉。

---

## 阶段 7：超时退款

1. **`refund(taskId)`**：仅 `client`、`block.timestamp > deadline`、状态允许（如 `Funded` 或你允许的结果已提交但未完成）。  
2. 状态 → `Refunded`，资金退回 `client`。  
3. **测试**：超时成功、未超时失败、已完成后退款失败、重复退款失败。

---

## 阶段 8：事件、边界与自检

1. 补全题目要求的 **事件**（任务创建、结果提交、完成、退款、信誉更新等）。  
2. 过一遍：**零地址、零金额、不存在 agent、inactive agent、错误状态迁移**。  
3. 本地跑全量测试：`forge test -vv` 或 `npx hardhat test`。

---

## 阶段 9：设计说明（短文）

单独一份 `DESIGN.md` 或写在 README 附录，**至少**说明：  

1. **任务状态机**图或表（状态、允许迁移、谁触发）。  
2. **防重放**：EIP-712 域与消息字段、`nonce` 或 `taskId` 消费策略。  
3. **如何避免**：重复结算、重复退款、重复评分、签名重放。  

---

## 阶段 10：交付检查清单

对照 [`题目-候选人版.md`](./题目-候选人版.md)：  

- [ ] Solidity 源码（2～4 个合约，或 2 合约 + 库）  
- [ ] 单元测试覆盖建议场景（注册、metadata、停用、创建任务、提交结果、EIP-712 完成、EOA、EIP-1271、签名重放、超时退款、重复评分）  
- [ ] 设计说明（状态机 + 防重放 + 防重复）  
- [ ] 根目录 `README.md` 可保留为产品/流程说明（可选补充「如何编译测试」一条命令）

---

## 建议执行顺序（速记）

`环境初始化` → `AgentRegistry` → `TaskEscrow`（无签名）→ `EIP-712 + complete` → `EIP-1271` → `信誉` → `退款` → `事件与边界` → `设计说明` → `对照题目自检`

按上述顺序做，每一步都有可运行的测试，便于面试演示与迭代。
