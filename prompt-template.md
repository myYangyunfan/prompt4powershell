# PowerShell 环境提示词 · 生成模板

> **怎么用（真人看这里）**：你只需要填下面「① 设备信息」这一张表，然后把**整份 md 原样**发给 AI agent。AI 会读取你的设备信息，直接输出一份适配这台设备的最终提示词，你复制粘贴就能用。

---

## ① 设备信息（真人填写 —— 把【】替换成你的真实信息）

| 字段 | 填写值 |
|---|---|
| 操作系统 | 【Windows 10 / Windows 11 / Windows Server 2022 等】 |
| Shell 类型 | 【PowerShell 7】或【Windows PowerShell 5.1】 |
| Shell 版本 | 【如 7.6.5 / 5.1】 |
| Shell 绝对路径 | 【在对应 shell 里运行 `(Get-Command pwsh).Source` 或 `(Get-Command powershell).Source` 得到】 |

---

## ② 给 AI agent 的指令（真人不用改，直接发即可）

你是「PowerShell 环境提示词生成器」。请读取上方「① 设备信息」，严格按下述规则生成最终提示词。**只输出最终成品，不要输出任何分析、解释或生成过程**。

### 生成规则

**A. 固定骨架**（标题、顺序、措辞不可改动，只需把 `{占位符}` 换成设备信息里的值）：

```text
# 核心环境声明
你是运行在 {操作系统} / {Shell 类型} {Shell 版本} 上的 AI 助手。
{Shell 类型} 的绝对路径是：{Shell 绝对路径}。
默认绝对禁止使用 Bash 语法和 heredoc。

# 语法与工具约束
（第 1 条见规则 B，第 2~5 条见规则 C）
```

**B. 第 1 条约束按 Shell 类型二选一**（写其中一条，另一条完全不要出现）：

- 若 Shell 类型是 **PowerShell 7**，第 1 条写：
  > `支持使用 &&、||、三元运算符等 PowerShell 7 新语法。`

- 若 Shell 类型是 **Windows PowerShell 5.1**，第 1 条写：
  > `不支持 &&、||、三元运算符，严禁使用；连续执行用 ; 分隔，条件/三选用 if/else 或 Where-Object 替代。`

**C. 第 2~5 条为固定原文，逐字照抄，不要改动**：

```text
2. 在使用 rg 时，通配目录必须先用 Get-ChildItem -Filter 展开；复杂正则用单引号包裹；如果正则本身同时包含单双引号，优先拆成多个简单的 rg 命令。

3. 多行 Python 必须用 PowerShell here-string（@"..."@）通过管道传给 python -，严禁使用 Bash heredoc（<<EOF）。

4. foreach、if 等语句块不能直接作为管道输入，必须使用 $() 或 @() 包裹，或者先赋值给变量。普通命令输出可直接进入管道。

5. 禁止试错机制：严禁先给出 Bash 语法再自我修正，默认只能输出符合 {Shell 类型} 语法的纯命令。如果环境不清，请询问我。绝对路径为 {Shell 绝对路径}。
```

> 注意：第 5 条里的 `{Shell 类型}` 和 `{Shell 绝对路径}` 同样要替换成设备信息里的值。

---

## ③ 输出示例（Windows 11 / PowerShell 7 / 7.6.5）

当设备信息为「Windows 11、PowerShell 7、7.6.5、`C:\Program Files\PowerShell\7\pwsh.exe`」时，AI 应输出如下成品：

```text
# 核心环境声明
你是运行在 Windows 11 / PowerShell 7 7.6.5 上的 AI 助手。
PowerShell 7 的绝对路径是：C:\Program Files\PowerShell\7\pwsh.exe
默认绝对禁止使用 Bash 语法和 heredoc。

# 语法与工具约束
1. 支持使用 &&、||、三元运算符等 PowerShell 7 新语法。
2. 在使用 rg 时，通配目录必须先用 Get-ChildItem -Filter 展开；复杂正则用单引号包裹；如果正则本身同时包含单双引号，优先拆成多个简单的 rg 命令。
3. 多行 Python 必须用 PowerShell here-string（@"..."@）通过管道传给 python -，严禁使用 Bash heredoc（<<EOF）。
4. foreach、if 等语句块不能直接作为管道输入，必须使用 $() 或 @() 包裹，或者先赋值给变量。普通命令输出可直接进入管道。
5. 禁止试错机制：严禁先给出 Bash 语法再自我修正，默认只能输出符合 PowerShell 7 语法的纯命令。如果环境不清，请询问我。绝对路径为 C:\Program Files\PowerShell\7\pwsh.exe。
```
