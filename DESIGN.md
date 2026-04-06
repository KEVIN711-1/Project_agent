# 设计说明（场景与合约分工）

## 业务场景

链上 **Agent 市场** 的最小闭环：Agent 以 NFT 注册身份并挂牌；客户针对某 Agent 创建任务并**托管赏金**；Agent 提交交付物的链上摘要（`resultHash`）；客户通过钱包对结构化数据签名表示**验收与评分**；合约验证后向 Agent 释放赏金并更新信誉；若超时未结算，客户可取回赏金。客户可为 EOA 或智能合约钱包。

---

## 合约分工

| 合约 | 设计角色 |
|------|----------|
| **AgentRegistry** | **身份目录**：每个 Agent 对应一枚 ERC-721；链上可验证 `owner`、`agentId`、对外说明（`metadataURI`）及是否接单（`active`）。任务创建时校验目标 Agent 存在且营业。 |
| **TaskEscrow** | **任务与资金托管**：创建任务即锁定 ERC20 或原生币；仅对应 Agent 可提交 `resultHash`；客户签名驱动结算与打款；超时由客户发起退款。与 Agent 身份合约只读交互。 |
| **ReputationRegistry** | **信誉台账**：按 Agent 汇总「完成次数、累计评分、最近更新时间」。仅由托管合约在**一次任务成功结算**时写入，与单笔任务解耦，便于单独阅读或替换实现。 |

---

## 部署与依赖

先部署 **AgentRegistry**、**ReputationRegistry**，再部署 **TaskEscrow**（构造注入前两者的地址），最后由部署账户调用 **ReputationRegistry.setSettlement(TaskEscrow)**，将信誉写入权限唯一绑定到托管合约。

---

## 与链下系统的关系

交付物正文在链下传递与展示；链上仅锚定 `resultHash` 与客户签名授权，前端与索引器依赖合约事件与只读接口同步任务状态。
