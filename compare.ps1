# ============================================================
#  compare.ps1 —— PowerShell 环境提示词「未注入 vs 注入」本机实测
#
#  针对本机实测：把每个用例的「错误命令（Bash 味）」和
#  「正确命令（纯 PowerShell）」都在本机真实跑一遍，
#  输出真实报错 / 真实输出，形成对照表。
#
#  用法：
#    powershell -NoProfile -ExecutionPolicy Bypass -File compare.ps1
# ============================================================

$ErrorActionPreference = 'Continue'

# ---------- 1. 本机环境探测 ----------
$psVer     = $PSVersionTable.PSVersion.ToString()
$isWinPS51 = ($PSVersionTable.PSVersion.Major -le 5)
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$rgCmd     = Get-Command rg     -ErrorAction SilentlyContinue

$myShell = 'powershell.exe'
try { $myShell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch {}
$psPath = $myShell
try { $psPath = (Get-Command powershell).Source } catch {}

$pythonDesc = '(未安装)'; if ($pythonCmd) { $pythonDesc = $pythonCmd.Source }
$rgDesc     = '(未安装)'; if ($rgCmd)     { $rgDesc     = $rgCmd.Source }

Write-Host ''
Write-Host '==================== 本机环境 ====================' -ForegroundColor Cyan
Write-Host ("  PowerShell 版本 : {0}" -f $psVer)
Write-Host ("  Shell 绝对路径  : {0}" -f $psPath)
Write-Host ("  python          : {0}" -f $pythonDesc)
Write-Host ("  rg              : {0}" -f $rgDesc)
Write-Host ''

# ---------- 2. 子进程执行器 ----------
# 命令用 Invoke-Expression 在子进程里运行：解析/运行错误都能捕获成纯文本，
# 并强制 UTF-8 输出，保证 PowerShell 报错与 rg 等原生工具的报错编码一致
function Invoke-InChild {
    param([string]$Code)
    $scriptFile = Join-Path $env:TEMP ('p4ps-case-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Code))

    $wrapperLines = @(
        "`$ProgressPreference = 'SilentlyContinue'"
        "try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}"
        "`$code = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))"
        "try {"
        "    Invoke-Expression `$code"
        "    if (`$LASTEXITCODE -ne `$null -and `$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }"
        "    exit 0"
        "} catch {"
        "    [Console]::Error.WriteLine(`$_.Exception.Message)"
        "    exit 1"
        "}"
    )
    $wrapper = $wrapperLines -join "`r`n"
    [System.IO.File]::WriteAllText($scriptFile, $wrapper, (New-Object System.Text.UTF8Encoding $true))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $myShell
    $psi.Arguments = '-NoProfile -NonInteractive -File "' + $scriptFile + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $env:TEMP
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    Remove-Item $scriptFile -ErrorAction SilentlyContinue

    $text = ((($out + "`n" + $err) -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) -join "`n"
    if ($text.Length -gt 600) { $text = $text.Substring(0, 600) + "`n  ...（已截断）" }
    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        Text     = $text.Trim()
        HasErr   = ($err.Trim().Length -gt 0)
    }
}

function Get-Verdict {
    param($Res)
    if ($Res.ExitCode -ne 0 -or $Res.HasErr) { return ('报错（退出码 {0}）' -f $Res.ExitCode) }
    return '执行成功（退出码 0）'
}

function Indent {
    param([string]$Text, [string]$Pad = '      ')
    return (($Text -split "`r?`n") | ForEach-Object { $Pad + $_ }) -join "`n"
}

# ---------- 3. 用例定义 ----------
$cases = @()

$cases += [PSCustomObject]@{
    Id = 1; Title = '链式执行 &&'; Only51 = $true; Need = ''; SilentWrong = $false
    Task = '进入目录，构建成功后跑测试'
    Wrong = @'
Set-Location $env:TEMP; Write-Output build-ok && Write-Output test-ok
'@
    Right = @'
Set-Location $env:TEMP; Write-Output build-ok; if ($?) { Write-Output test-ok }
'@
}

$cases += [PSCustomObject]@{
    Id = 2; Title = '多行 Python（heredoc）'; Only51 = $false; Need = 'python'; SilentWrong = $false
    Task = '用 Python 打印一段 JSON'
    Wrong = @'
python - <<EOF
import json
print(json.dumps({"a": 1}))
EOF
'@
    Right = @'
@"
import json
print(json.dumps({"a": 1}))
"@ | python -
'@
}

$cases += [PSCustomObject]@{
    Id = 3; Title = '设置环境变量 export'; Only51 = $false; Need = ''; SilentWrong = $false
    Task = '往 PATH 里追加一个目录'
    Wrong = @'
export PATH=$PATH:/opt/tools
'@
    Right = @'
$env:PATH = "$env:PATH;C:\tools"; $env:PATH.Split(';')[-1]
'@
}

$cases += [PSCustomObject]@{
    Id = 4; Title = 'foreach 语句块进管道'; Only51 = $false; Need = ''; SilentWrong = $false
    Task = '遍历进程，只保留名字含 win 的'
    Wrong = @'
foreach ($p in Get-Process) { $p.Name } | Where-Object { $_ -like '*win*' }
'@
    Right = @'
$names = foreach ($p in Get-Process) { $p.Name }; $names | Where-Object { $_ -like '*win*' } | Select-Object -First 3
'@
}

$cases += [PSCustomObject]@{
    Id = 5; Title = '三元运算符'; Only51 = $true; Need = ''; SilentWrong = $false
    Task = '根据计数是否大于 0 输出 yes/no'
    Wrong = @'
$count = 5; $result = $count -gt 0 ? 'yes' : 'no'; $result
'@
    Right = @'
$count = 5; if ($count -gt 0) { $result = 'yes' } else { $result = 'no' }; $result
'@
}

$cases += [PSCustomObject]@{
    Id = 6; Title = '$PATH 变量（静默）'; Only51 = $false; Need = ''; SilentWrong = $true
    Task = '查看 PATH 环境变量'
    Wrong = @'
Write-Output $PATH
'@
    Right = @'
$p = @($env:PATH -split ';' | Where-Object { $_ -ne '' })
Write-Output ("count=" + $p.Count)
'@
}

$cases += [PSCustomObject]@{
    Id = 7; Title = 'rg 通配目录 **'; Only51 = $false; Need = 'rg'; SilentWrong = $false
    Task = '在 src 下递归搜索所有 .ts 文件里的 TODO（src\a.ts 和 src\sub\b.ts 都含 TODO）'
    Wrong = @'
$d = Join-Path $env:TEMP ('rgdemo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\sub') | Out-Null
Set-Content -Path (Join-Path $d 'src\a.ts') -Value 'TODO here' -Encoding UTF8
Set-Content -Path (Join-Path $d 'src\sub\b.ts') -Value 'TODO nested' -Encoding UTF8
Set-Location $d
rg 'TODO' src/**/*.ts
'@
    Right = @'
$d = Join-Path $env:TEMP ('rgdemo-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\sub') | Out-Null
Set-Content -Path (Join-Path $d 'src\a.ts') -Value 'TODO here' -Encoding UTF8
Set-Content -Path (Join-Path $d 'src\sub\b.ts') -Value 'TODO nested' -Encoding UTF8
Set-Location $d
rg 'TODO' (Get-ChildItem -Path src -Filter *.ts -Recurse).FullName
'@
}

# ---------- 4. 逐条实测 ----------
$summary = @()

foreach ($c in $cases) {
    $skipMsg = $null
    if ($c.Only51 -and -not $isWinPS51) {
        $skipMsg = ("[跳过] 用例 {0}「{1}」：本机是 PowerShell 7，&& / 三元是合法语法，无对比意义" -f $c.Id, $c.Title)
    } elseif ($c.Need -eq 'python' -and -not $pythonCmd) {
        $skipMsg = ("[跳过] 用例 {0}「{1}」：本机未安装 python" -f $c.Id, $c.Title)
    } elseif ($c.Need -eq 'rg' -and -not $rgCmd) {
        $skipMsg = ("[跳过] 用例 {0}「{1}」：本机未安装 rg" -f $c.Id, $c.Title)
    }
    if ($skipMsg) {
        Write-Host $skipMsg -ForegroundColor DarkGray
        Write-Host ''
        continue
    }

    Write-Host ("────────── 用例 {0}：{1} ──────────" -f $c.Id, $c.Title) -ForegroundColor Cyan
    Write-Host ("任务：{0}" -f $c.Task)
    Write-Host ''

    $w = Invoke-InChild $c.Wrong
    $r = Invoke-InChild $c.Right

    # ---- 错误命令 ----
    Write-Host '  × 未注入提示词：' -ForegroundColor Red
    Write-Host (Indent $c.Wrong.Trim())
    $wVerdict = Get-Verdict $w
    if ($c.SilentWrong -and $w.ExitCode -eq 0 -and -not $w.HasErr) {
        $wVerdict = '静默出错（无报错，但结果不对）'
    }
    Write-Host ("      [判定] {0}" -f $wVerdict) -ForegroundColor Red
    if ($w.Text) {
        Write-Host '      [实测输出]' -ForegroundColor Red
        Write-Host (Indent $w.Text) -ForegroundColor DarkGray
    } else {
        Write-Host '      [实测输出] （空 —— 什么都不输出，还不报错）' -ForegroundColor Red
    }
    Write-Host ''

    # ---- 正确命令 ----
    Write-Host '  √ 注入提示词后：' -ForegroundColor Green
    Write-Host (Indent $c.Right.Trim())
    Write-Host ("      [判定] {0}" -f (Get-Verdict $r)) -ForegroundColor Green
    if ($r.Text) {
        Write-Host '      [实测输出]' -ForegroundColor Green
        Write-Host (Indent $r.Text) -ForegroundColor DarkGray
    }
    Write-Host ''

    # ---- 汇总 ----
    $wMark = '√ 正常'
    if ($w.ExitCode -ne 0 -or $w.HasErr) { $wMark = '× 报错' } elseif ($c.SilentWrong) { $wMark = '× 静默错' }
    $rMark = '√ 正确'
    if ($r.ExitCode -ne 0 -or $r.HasErr) { $rMark = '× 报错' }

    $summary += [PSCustomObject]@{
        '用例'   = ('{0} {1}' -f $c.Id, $c.Title)
        '未注入' = $wMark
        '注入后' = $rMark
    }
}

# ---------- 5. 汇总对照表 ----------
Write-Host '==================== 对照表 ====================' -ForegroundColor Cyan
$summary | Format-Table -AutoSize
Write-Host ''

Read-Host '按回车键退出...' | Out-Null
