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

## 效果对比（测试用例）

下面的用例都在 **Windows PowerShell 5.1（中文系统）** 上实测过，每个都贴出**真实输出**：同一个任务，未注入提示词时 AI 给什么、跑成什么样，注入后给什么、跑成什么样。差距一眼可见、可复现。

### ① 直接报错型 —— 一眼看出跑不了

#### 用例 1：链式执行 `&&`（Windows PowerShell 5.1）

**任务**：进入 `project` 目录，构建成功后跑测试。

**❌ 未注入** —— AI 默认给 Bash 链式语法：

```bash
cd project && npm run build && npm test
```

**💥 实测结果**（5.1 直接报错，命令根本没执行）：

```text
所在位置 行:1 字符: 12
+ cd project && npm run build && npm test
+            ~~
标记“&&”不是此版本中的有效语句分隔符。
```

**✅ 注入后** —— 用 `;` 分隔，`if` 判断退出码：

```powershell
cd project; npm run build; if ($LASTEXITCODE -eq 0) { npm test }
```

#### 用例 2：多行 Python 脚本

**任务**：用 Python 打印一段 JSON。

**❌ 未注入** —— AI 默认给 Bash heredoc：

```bash
python3 <<EOF
import json
print(json.dumps({"a": 1}))
EOF
```

**💥 实测结果**：

```text
重定向运算符后面缺少文件规范。
“<”运算符是为将来使用而保留的。
```

**✅ 注入后** —— PowerShell here-string 管道传给 `python -`：

```powershell
@"
import json
print(json.dumps({"a": 1}))
"@ | python -
```

**✅ 实测结果**：

```text
{"a": 1}
```

#### 用例 3：设置环境变量 `export`

**任务**：往 `PATH` 里追加一个目录。

**❌ 未注入** —— AI 默认给 Bash 的 `export`：

```bash
export PATH=$PATH:/opt/tools
```

**💥 实测结果**：

```text
变量引用无效。':' 后面的变量名称字符无效。请考虑使用 ${} 分隔名称。
```

**✅ 注入后** —— PowerShell 变量语法：

```powershell
$env:PATH = "$env:PATH;C:\tools"
```

#### 用例 4：`foreach` 语句块进管道

**任务**：遍历进程，只保留名字含 `win` 的。

**❌ 未注入** —— AI 把 `foreach` 块直接接到管道：

```powershell
foreach ($p in Get-Process) { $p.Name } | Where-Object { $_ -like "*win*" }
```

**💥 实测结果**：

```text
所在位置 行:1 字符: 41
+ foreach ($p in Get-Process) { $p.Name } | Where-Object { $_ -like "*w ...
+                                         ~
不允许使用空管道元素。
```

**✅ 注入后** —— 先赋值给变量再进管道：

```powershell
$names = foreach ($p in Get-Process) { $p.Name }
$names | Where-Object { $_ -like "*win*" }
```

#### 用例 5：三元运算符（Windows PowerShell 5.1）

**任务**：根据计数是否大于 0 输出 `yes` / `no`。

**❌ 未注入** —— AI 默认用三元运算符：

```powershell
$result = $count -gt 0 ? "yes" : "no"
```

**💥 实测结果**：

```text
所在位置 行:1 字符: 34
+ $result = $count -gt 0 ? "yes" : "no"
+                                  ~
表达式或语句中包含意外的标记“?”。
```

**✅ 注入后** —— 用 `if` / `else` 替代：

```powershell
if ($count -gt 0) { $result = "yes" } else { $result = "no" }
```

#### 用例 6：`rg` 通配目录 `**`

**任务**：在 `src` 下递归搜索所有 `.ts` 文件里的 `TODO`。目录结构：

```text
src/
├── a.ts          # 含 TODO
└── sub/
    └── b.ts      # 含 TODO
```

**❌ 未注入** —— AI 默认写 Bash 风格的 `**` 通配：

```bash
rg "TODO" src/**/*.ts
```

**💥 实测结果**：PowerShell 不做通配展开，`src/**/*.ts` 被原样传给 rg，直接报错：

```text
src/**/*.ts: 文件名、目录名或卷标语法不正确。 (os error 123)
```

**✅ 注入后** —— 先用 `Get-ChildItem -Filter` 展开，再把文件列表交给 rg：

```powershell
rg "TODO" (Get-ChildItem -Path src -Filter *.ts -Recurse).FullName
```

**✅ 实测结果**：搜到 **2 条**，一个不落：

```text
src\sub\b.ts:TODO
src\a.ts:TODO
```

### ② 静默出错型 —— 能跑、不报错，但结果悄悄错了（最危险）

#### 用例 7：`$PATH` 变量不存在

**任务**：查看 `PATH` 环境变量。

**❌ 未注入** —— AI 按 Bash 习惯写 `$PATH`：

```powershell
echo $PATH
```

**💥 实测结果**：**什么都不输出**。PowerShell 里 `$PATH` 是未定义变量，静默吞掉，不报任何错——你以为命令正常执行了。

**✅ 注入后** —— 用 `$env:` 作用域：

```powershell
echo $env:PATH
```

**✅ 实测结果**：输出真实路径，如 `C:\Windows\system32;C:\Windows;...`

### ③ 试错成本型 —— 同样的活，多花好几轮

#### 用例 8：一次到位 vs 反复试错

**任务**：让 AI 用 Python 打印一段 JSON。

**❌ 未注入** —— 典型对话，来回 3~4 轮才出正确命令：

```text
用户：用 Python 打印一段 JSON
AI  ：python3 <<EOF
      import json; print(json.dumps({"a": 1}))
      EOF
用户：报错了
AI  ：抱歉，PowerShell 里应该用 here-string：@"..."@ | python -
用户：这回对了
```

**✅ 注入后** —— 一次到位：

```text
用户：用 Python 打印一段 JSON
AI  ：@"
      import json
      print(json.dumps({"a": 1}))
      "@ | python -
```

## 一键实测（compare.ps1）

仓库自带脚本 `compare.ps1`，会在本机真实跑完上面全部用例，自动输出 ×/√ 对照表，并贴出真实报错 / 真实输出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File compare.ps1
```

脚本会自动探测本机的 PowerShell 版本、`python`、`rg`；缺失依赖或不适用的用例（例如本机是 PowerShell 7 时跳过 `&&` / 三元用例）会自动跳过。

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
├── compare.ps1          # 一键实测脚本（本机跑完所有用例输出对照表）
├── README.md            # 本说明
├── LICENSE              # MIT 开源协议
└── AGENTS.md            # 面向 AI agent 的仓库说明
```

## License

[MIT](./LICENSE)
