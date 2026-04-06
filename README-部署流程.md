# 部署流程（分步完成）

与 [`README-项目流程.md`](./README-项目流程.md) 中的合约依赖一致：先 **AgentRegistry**、**ReputationRegistry**、**TaskEscrow**，再 **`ReputationRegistry.setSettlement(TaskEscrow)`**。

仓库已提供脚本：[`script/Deploy.s.sol`](./script/Deploy.s.sol)。

---

## 阶段 A：本地 Anvil（推荐先做）

### 步骤 1：启动链

新开终端，在项目根目录外也可：

```powershell
anvil
```

保持运行，默认 RPC：`http://127.0.0.1:8545`，链 ID 通常为 `31337`。

### 步骤 2：准备部署私钥（Anvil 默认账户）

Anvil 启动时会打印 10 个测试账户及私钥。任选**第一个**私钥即可（本地假钱），例如：

```text
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

（以你终端里 `anvil` 输出为准。）

### 步骤 3：编译

```powershell
cd D:\Project_cursor\Project_agent
forge build
```

### 步骤 4：广播部署脚本

另开终端（Anvil 仍在跑）：

```powershell
cd D:\Project_cursor\Project_agent

forge script script/Deploy.s.sol:DeployScript `
  --rpc-url http://127.0.0.1:8545 `
  --broadcast `
  --private-key <你的Anvil测试私钥>
```

成功后终端会打印三行地址：`AgentRegistry`、`ReputationRegistry`、`TaskEscrow`。

### 步骤 5：核对（可选）

```powershell
cast call <TaskEscrow地址> "agentRegistry()(address)" --rpc-url http://127.0.0.1:8545
cast call <ReputationRegistry地址> "settlement()(address)" --rpc-url http://127.0.0.1:8545
```

`settlement` 应等于 `TaskEscrow` 地址。

---

## 阶段 B：Sepolia 等测试网

### 步骤 1：准备

- 测试网 **RPC URL**（Infura、Alchemy 等）  
- 有测试 **ETH** 的部署账户私钥（**不要提交仓库**）

### 步骤 2：部署

```powershell
forge script script/Deploy.s.sol:DeployScript `
  --rpc-url https://sepolia.infura.io/v3/<YOUR_KEY> `
  --broadcast `
  --private-key <部署私钥>
```

若需估算 gas，可先加 `--slow` 或去掉 `--broadcast` 做 dry run（视 forge 版本而定）。

### 步骤 3：浏览器验证（可选）

在 Sepolia Etherscan 上对三个合约做 **Verify**，便于读写合约：

```powershell
forge verify-contract <地址> src/AgentRegistry.sol:AgentRegistry --chain sepolia --etherscan-api-key <KEY>
```

（`ReputationRegistry`、`TaskEscrow` 同理；具体参数以 `forge verify-contract --help` 为准。）

---

## 我们「一步一步」建议顺序

| 步 | 做什么 | 完成标志 |
|----|--------|----------|
| 1 | 本机 `forge test` 全绿 | 7 tests passed |
| 2 | `anvil` + `forge script ... --broadcast` | 终端打出三个地址 |
| 3 | `cast call` 核对 `settlement` | 等于 TaskEscrow |
| 4 | （可选）写 `DESIGN.md` | 满足题目设计说明要求 |
| 5 | （可选）Sepolia 再部署一遍 | 测试网可查地址 |
| 6 | （可选）合约 Verify | 浏览器可读源码 |

---

## 安全提醒

- **永远不要**把真实私钥写进 git 或发给他人。  
- 本地 Anvil 私钥仅用于开发；测试网/主网用独立密钥与 `.env`（并已加入 `.gitignore`）。
