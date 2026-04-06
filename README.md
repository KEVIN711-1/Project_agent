# Trustless Agent System

基于题目要求的最小链上 Agent 信任系统：**ERC721 Agent 身份**、**任务托管与结算**、**EIP-712 验收**、**EOA + EIP-1271 合约钱包验签**、**信誉累计**、**超时退款**。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [**README-项目流程.md**](./README-项目流程.md) | **运行周期、用户/前后端交互、签名与验收流程**（单独成篇） |
| [题目-候选人版.md](./题目-候选人版.md) | 题目原文与交付要求 |
| [README-搭建步骤.md](./README-搭建步骤.md) | Foundry 工程分阶段搭建 |
| [README-部署流程.md](./README-部署流程.md) | **Anvil / 测试网分步部署与 `forge script`** |
| [DESIGN.md](./DESIGN.md) | **设计说明**（状态机、防重放、信誉） |

---

## 一句话流程

**Agent 链上注册 → 客户创建任务并锁赏金 → Agent 提交 `resultHash` → 客户 EIP-712 签名（含评分）→ `completeTask` 验签后打款并记信誉；超时客户可 `refund`。**

---

## 开发与测试（Foundry）

```bash
forge build
forge test -vv
```

**部署顺序：** `AgentRegistry` → `ReputationRegistry` → `TaskEscrow` → `ReputationRegistry.setSettlement(escrow)`。

**源码：** `src/AgentRegistry.sol`、`src/TaskEscrow.sol`、`src/ReputationRegistry.sol`。

---

## 说明

链上提供可验证身份与资金结算规则；链下 Agent 行为与交付展示由产品与链下系统配合完成。
