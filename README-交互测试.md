# 部署成功后的交互测试

前提：**Anvil 仍在运行**，且你已记下部署输出的三个地址（`AgentRegistry`、`ReputationRegistry`、`TaskEscrow`）。

---

## 方式一：一键脚本（推荐）

脚本使用 **Anvil 默认账户**：  
- **#0**（私钥 `0xac09...`）= Agent owner  
- **#1**（私钥 `0x59c6...`）= Client  

若你部署时用的不是 #0，请改 `script/InteractAnvil.s.sol` 里的 `AGENT_PK` / `CLIENT_PK` 与部署账户一致。

### PowerShell 设置地址（换成你自己的）

```powershell
cd D:\Project_cursor\Project_agent

$env:REGISTRY_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3"
$env:ESCROW_ADDRESS = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
$env:REPUTATION_ADDRESS = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
```

> 上面三个地址是 **全新 Anvil + 默认 Deploy 顺序** 下常见的确定性地址；若你链上已有其它交易，**以你 `forge script` 部署日志为准**。

### 执行

```powershell
forge script script/InteractAnvil.s.sol:InteractAnvil `
  --rpc-url http://127.0.0.1:8545 `
  --broadcast `
  -vvv
```

预期日志：`agentId`、`taskId`、`taskStatus = 3`（Completed）、信誉累计更新。

---

## 方式二：用 `cast` 手动调（理解每一步）

设变量（地址改成你的）：

```powershell
$REG = "0x..."
$ESC = "0x..."
$AGENT = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
$CLIENT = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
```

1. **注册 Agent**（第一笔 mint 通常 `agentId = 1`）

```powershell
cast send $REG "registerAgent(string)(uint256)" "ipfs://manual" --private-key $AGENT --rpc-url http://127.0.0.1:8545
```

2. **创建任务并锁 1 ETH**（`deadline` 用未来时间戳）

```powershell
$deadline = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400)
cast send $ESC "createTask(uint256,address,uint256,uint256)" 1 0x0000000000000000000000000000000000000000 1000000000000000000 $deadline --private-key $CLIENT --value 1ether --rpc-url http://127.0.0.1:8545
```

3. **Agent 提交 resultHash**（`taskId` 一般为 1）

```powershell
cast send $ESC "submitResult(uint256,bytes32)" 1 0x1234567890123456789012345678901234567890123456789012345678901234 --private-key $AGENT --rpc-url http://127.0.0.1:8545
```

4. **读 digest**（`score` 与下一步签名一致，例如 90）

```powershell
cast call $ESC "digestForCompleteTask(uint256,uint256)(bytes32)" 1 90 --rpc-url http://127.0.0.1:8545
```

5. **Client 对 digest 签名**（`--no-hash`：对 32 字节 digest 直接 ECDSA，与合约一致）

```powershell
$digest = "<上一步输出的 0x...>"
cast wallet sign --private-key $CLIENT --no-hash $digest
```

6. **completeTask**（把签名编成 `bytes`：常见为 `r||s||v` 共 65 字节，`cast wallet sign` 输出按版本可能是单行 hex，需拼成 `0x` + 130 hex 字符）

若手动拼 `bytes` 易错，**优先用方式一脚本**完成 `completeTask`。

---

## 方式三：前端 / MetaMask

- 把链加到钱包：**RPC** `http://127.0.0.1:8545`，**链 ID** `31337`（Anvil 默认）。  
- 导入 Anvil 私钥到 MetaMask（仅本地）。  
- 在 Dapp 里填合约地址，调 `registerAgent`、`createTask` 等；**验收**需按 [`README-项目流程.md`](./README-项目流程.md) 做 EIP-712 签名再 `completeTask`。

---

## 小结

| 方式 | 适合 |
|------|------|
| **InteractAnvil 脚本** | 快速验证全链路 |
| **cast** | 单步调试、学 calldata |
| **钱包 + 前端** | 真实产品形态 |

更多部署步骤见 [`README-部署流程.md`](./README-部署流程.md)。
