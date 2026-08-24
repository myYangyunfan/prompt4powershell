# prompt4powershell

生成「PowerShell 环境提示词」的模板。填好设备信息、发给 AI agent，即可得到一份适配你设备的 PowerShell 专属提示词，可直接复制粘贴使用。

## 解决什么问题

很多 AI agent 在 Windows 上默认输出 Bash 语法，命令在 PowerShell 里跑不起来。这份模板让 AI 在读取你的设备信息后，输出一份**严格遵循 PowerShell 语法、默认禁用 Bash 和 heredoc** 的提示词。

## 快速上手

1. 打开 [`prompt-template.md`](./prompt-template.md)
2. 只填「① 设备信息」表格里的 4 个字段：
   - 操作系统（Windows 10 / 11 / Server 2022 等）
   - Shell 类型（PowerShell 7 或 Windows PowerShell 5.1）
   - Shell 版本（如 7.6.5 / 5.1）
   - Shell 绝对路径 —— 在对应 shell 里运行 `(Get-Command pwsh).Source` 或 `(Get-Command powershell).Source` 获取
3. 把**整份 md 原样**发给 AI agent
4. 复制 AI 输出的最终提示词，粘贴到你的 agent 环境声明里即可

## 生成规则要点

模板会按设备信息动态生成提示词，核心约束包括：

- **Shell 类型二选一**：PowerShell 7 支持 `&&`、`||`、三元运算符；Windows PowerShell 5.1 不支持，需用 `;` / `if` / `else` 替代
- **默认禁止 Bash 语法和 heredoc**
- `rg` 通配目录需先 `Get-ChildItem -Filter` 展开，复杂正则用单引号包裹
- 多行 Python 用 PowerShell here-string（`@"..."@`）管道传给 `python -`，严禁 `<<EOF`
- `foreach`、`if` 等语句块不能直接作为管道输入，需用 `$()` / `@()` 包裹或先赋给变量
- 禁止试错机制：只输出符合当前 Shell 语法的纯命令

## 输出示例（Windows 11 / PowerShell 7 / 7.6.5）

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

## 目录结构

```
prompt4powershell/
├── prompt-template.md   # 核心模板（唯一需要编辑的文件）
├── README.md            # 本说明
└── AGENTS.md            # 面向 AI agent 的仓库说明
```
