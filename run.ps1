# ============================================================
#  我的简历 - 一键启动 (PowerShell 版)
#  自动检测 Python → 自动安装 Python → 安装依赖 → 启动服务
#  全程无需手动操作
# ============================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$ErrorActionPreference = "SilentlyContinue"
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Log($msg) { Write-Host $msg }

# 校验 Python 版本是否满足最低要求
# 最低支持 3.8（fastapi/pydantic 要求）
$MIN_MAJOR = 3
$MIN_MINOR = 8
function Test-PythonVersion {
    param([string]$versionString)
    # 提取形如 "Python 3.7.9" 中的版本号
    $m = [regex]::Match($versionString, '(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $false }
    $maj = [int]$m.Groups[1].Value
    $min = [int]$m.Groups[2].Value
    if ($maj -gt $MIN_MAJOR) { return $true }
    if ($maj -eq $MIN_MAJOR -and $min -ge $MIN_MINOR) { return $true }
    return $false
}

function Get-PythonVersionString {
    param([string]$exe, [string[]]$preArgs)
    $out = & $exe $preArgs --version 2>&1
    return ($out -join " ").Trim()
}

# 执行 Python 命令的辅助函数（兼容 py -3 这种带参数形式）
# $pythonExe: 可执行路径，如 "python" 或 "py"
# $pythonArgs: 额外前置参数，如 @("-3") 或 @()
function Invoke-Python {
    param([string]$exe, [string[]]$preArgs, [string[]]$cmdArgs)
    $all = $preArgs + $cmdArgs
    return & $exe $all 2>&1
}

# 带进度条的问件下载（直接打印到控制台，不依赖 Write-Progress）
function Download-File {
    param([string]$url, [string]$dest, [string]$description)
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Timeout = 30000
        # 必须设置 User-Agent，否则镜像源会返回 403
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        $req.Accept = "*/*"
        $resp = $req.GetResponse()
        # 校验响应：如果是 HTML 错误页，直接当失败处理
        $ct = $resp.ContentType
        if ($ct -like "text/html*") {
            $resp.Close()
            throw "服务器返回了 HTML 页面而非可执行文件 (Content-Type: $ct)"
        }
        $totalBytes = $resp.ContentLength
        if ($totalBytes -gt 0 -and $totalBytes -lt 1000000) {
            $resp.Close()
            throw "文件过小 ($totalBytes bytes)，疑似错误页面"
        }
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($dest)
        $buf = New-Object byte[] 65536
        $totalRead = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $lastPct = -1

        while ($true) {
            $n = $stream.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $fs.Write($buf, 0, $n)
            $totalRead += $n

            if ($totalBytes -gt 0) {
                $pct   = [math]::Round(($totalRead / $totalBytes) * 100)
                # 每 2% 刷新一次，避免刷屏过快
                if ($pct -ge $lastPct + 2 -or $pct -eq 100) {
                    $speed = if ($sw.Elapsed.TotalSeconds -gt 0.1) {
                        [math]::Round(($totalRead / 1MB) / $sw.Elapsed.TotalSeconds, 1)
                    } else { 0 }
                    $done  = [math]::Round($totalRead / 1MB, 1)
                    $total = [math]::Round($totalBytes / 1MB, 1)
                    $barLen = 30
                    $filled = [math]::Round($barLen * $pct / 100)
                    $bar = ('#' * $filled) + ('-' * ($barLen - $filled))
                    # `r 回到行首，覆盖当前行（不换行）
                    Write-Host ("`r  [..] {0} : [{1}] {2}%  {3}/{4} MB  {5} MB/s" -f $description, $bar, $pct, $done, $total, $speed) -NoNewline
                    $lastPct = $pct
                }
            }
        }

        $fs.Close(); $stream.Close(); $resp.Close()
        Write-Host ""  # 换行
        # 下载完成后二次校验：防止连接中断只下了几 KB 就误报成功
        if ($totalRead -lt 1000000) {
            throw "下载不完整，实际仅收到 $totalRead bytes（预期约 25 MB）"
        }
        Write-Host "  [OK] $description 下载完成"
        return $true
    } catch {
        Write-Host ""  # 换行
        Write-Host "  [FAIL] $description 下载失败: $($_.Exception.Message)"
        if ($fs) { try { $fs.Close() } catch {} }
        return $false
    }
}

# winget 安装时的旋转等待动画（用 .NET Timer 在主线程打印，确保可见）
$script:spinnerTimer = $null
function Start-Spinner {
    param([string]$label)
    $script:spinnerIdx = 0
    $script:spinnerStart = Get-Date
    $script:spinnerLabel = $label
    $script:spinnerTimer = New-Object System.Timers.Timer
    $script:spinnerTimer.Interval = 200
    $script:spinnerTimer.AutoReset = $true
    $spinChars = @('|', '/', '-', '\')
    $script:spinnerTimer.add_Elapsed({
        $elapsed = [math]::Round(((Get-Date) - $script:spinnerStart).TotalSeconds)
        $ch = $spinChars[$script:spinnerIdx % 4]
        Write-Host ("`r  {0} {1} ... {2} 秒" -f $ch, $script:spinnerLabel, $elapsed) -NoNewline
        $script:spinnerIdx++
    })
    $script:spinnerTimer.Start()
}

function Stop-Spinner {
    if ($script:spinnerTimer) {
        $script:spinnerTimer.Stop()
        $script:spinnerTimer.Dispose()
        $script:spinnerTimer = $null
    }
    Write-Host ""  # 换行
}

# ============================================================

# ============================================================
# [1/6] 检测 Python
# ============================================================
Log ""
Log "============================================================"
Log "  [1/6] 检测 Python 环境..."
Log "============================================================"

$pyExe  = $null
$pyPre  = @()
$pyTooOld = $false   # 记录是否有版本太旧的 Python

# 尝试 python
$testOut = & python --version 2>&1
if ($LASTEXITCODE -eq 0) {
    $vs = ($testOut -join ' ').Trim()
    if (Test-PythonVersion $vs) {
        $pyExe = "python"; $pyPre = @()
        Log "  [OK] 找到 python: $vs"
    } else {
        Log "  [WARN] python 版本过低: $vs (最低要求 3.8，将尝试其他方式...)"
        $pyTooOld = $true
    }
}

# 尝试 python3
if (-not $pyExe) {
    $testOut = & python3 --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $vs = ($testOut -join ' ').Trim()
        if (Test-PythonVersion $vs) {
            $pyExe = "python3"; $pyPre = @()
            Log "  [OK] 找到 python3: $vs"
        } else {
            Log "  [WARN] python3 版本过低: $vs (最低要求 3.8，将尝试其他方式...)"
            $pyTooOld = $true
        }
    }
}

# 尝试 py -3
if (-not $pyExe) {
    $testOut = & py -3 --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $vs = ($testOut -join ' ').Trim()
        if (Test-PythonVersion $vs) {
            $pyExe = "py"; $pyPre = @("-3")
            Log "  [OK] 找到 py -3: $vs"
        } else {
            Log "  [WARN] py -3 版本过低: $vs (最低要求 3.8，将尝试其他方式...)"
            $pyTooOld = $true
        }
    }
}

# ============================================================
# 自动安装 Python（如果未检测到）
# ============================================================
if (-not $pyExe) {
    if ($pyTooOld) {
        Log "  [WARN] 已找到的 Python 版本过低（依赖包要求 >= 3.8）"
        Log "  [..] 准备自动安装 Python 3.12 ..."
    } else {
        Log "  [..] 未检测到 Python，准备自动安装 ..."
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installed = $false

    # ================================================================
    # 方案 A: 直接下载 + 进度条 + /quiet 静默安装（优先，有进度反馈）
    # ================================================================
    # 版本列表：从新到旧，依次尝试（某版本下架时自动降级）
    # 经实测确认各镜像源均有效的最新 4 个版本（3.12.11+ 下载链接不稳定）
    $pyVers = @("3.12.10", "3.12.9", "3.12.8", "3.12.7")
    # 镜像源模板（用 {0} 占位版本号）：华为云实测最稳定，清华/官方为备选
    $mirrorTpls = @(
        "https://mirrors.huaweicloud.com/python/{0}/python-{0}-amd64.exe",
        "https://mirrors.tuna.tsinghua.edu.cn/python/{0}/python-{0}-amd64.exe",
        "https://www.python.org/ftp/python/{0}/python-{0}-amd64.exe"
    )

    $downloaded    = $false
    $usedVer       = $null
    $usedInstaller = $null

    foreach ($v in $pyVers) {
        $installerPath = "$env:TEMP\python-$v-installer.exe"
        Remove-Item $installerPath -ErrorAction SilentlyContinue

        foreach ($tpl in $mirrorTpls) {
            $url = $tpl -f $v
            Log "  [..] 尝试 Python $v : $url"
            $ok = Download-File -url $url -dest $installerPath -description "Python $v"
            if ($ok -and (Test-Path $installerPath) -and ((Get-Item $installerPath).Length -gt 1000000)) {
                $downloaded    = $true
                $usedVer       = $v
                $usedInstaller = $installerPath
                break
            }
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            Log "  [..] 该源不可用，切换下一个..."
        }
        if ($downloaded) { break }
        Log "  [WARN] Python $v 所有源均不可用，尝试下一个版本..."
    }

    if ($downloaded) {
        Log "  [..] 正在后台静默安装 Python $usedVer (约 30 秒) ..."
        Log "      安装期间请勿关闭此窗口，否则安装将中断，请耐心等待"
        Start-Spinner -label "Python $usedVer 正在安装中"
        $proc = Start-Process -FilePath $usedInstaller `
            -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_test=0" `
            -Wait -PassThru
        Stop-Spinner
        Remove-Item $usedInstaller -ErrorAction SilentlyContinue

        # 刷新 PATH
        $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                     [System.Environment]::GetEnvironmentVariable("Path","User"))

        $v = & python --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pyExe = "python"; $pyPre = @()
            $installed = $true
            Log "  [OK] Python 安装成功: $(($v -join ' ').Trim())"
        }
    }

    # ================================================================
    # 方案 B: winget（直接下载全部失败后的保底，无进度条但有时更可靠）
    # ================================================================
    if (-not $installed) {
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Log "  [..] 直接下载均失败，尝试通过 winget 安装 Python 3.12 ..."
            Log "        (winget 在后台工作，请耐心等待...)"
            Start-Spinner -label "winget 正在下载并安装 Python 3.12"
            winget install Python.Python.3.12 --silent --scope user --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Stop-Spinner

            $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                         [System.Environment]::GetEnvironmentVariable("Path","User"))

            $v = & python --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $pyExe = "python"; $pyPre = @()
                $installed = $true
                Log "  [OK] winget 安装成功: $(($v -join ' ').Trim())"
            }
        }
    }

    # ================================================================
    # 全部失败
    # ================================================================
    if (-not $installed) {
        Log "  [FAIL] Python 自动安装失败"
        Log "         请手动安装: https://www.python.org/downloads/"
        Log "         安装时务必勾选 'Add Python to PATH'"
        Read-Host "  按回车键退出..."
        exit 1
    }
}

# ============================================================
# [2/6] 检测 pip
# ============================================================
Log ""
Log "============================================================"
Log "  [2/6] 检测 pip ..."
Log "============================================================"

$pipOk = $false

$pipOut = Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "pip", "--version")
if ($LASTEXITCODE -eq 0 -and ($pipOut -join "").Trim()) {
    $pipOk = $true
    Log "  [OK] pip 可用: $(($pipOut -join ' ').Trim())"
}

if (-not $pipOk) {
    Log "  [..] pip 不可用，尝试 ensurepip 修复..."
    Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "ensurepip", "--upgrade") | Out-Null
    $pipOut = Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "pip", "--version")
    if ($LASTEXITCODE -eq 0) {
        $pipOk = $true
        Log "  [OK] ensurepip 修复成功"
    }
}

if (-not $pipOk) {
    Log "  [..] ensurepip 失败，尝试下载 get-pip.py ..."
    $getPipPath = "$scriptDir\_get_pip.py"
    $ok2 = Download-File -url "https://bootstrap.pypa.io/get-pip.py" -dest $getPipPath -description "get-pip.py"
    if ($ok2) {
        Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @($getPipPath) | Out-Null
        Remove-Item $getPipPath -ErrorAction SilentlyContinue
        $pipOut = Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "pip", "--version")
        if ($LASTEXITCODE -eq 0) {
            $pipOk = $true
            Log "  [OK] get-pip.py 修复成功"
        }
    }
    Remove-Item $getPipPath -ErrorAction SilentlyContinue
}

if (-not $pipOk) {
    Log "  [FAIL] pip 无法修复，请重新安装 Python"
    Read-Host "  按回车键退出..."
    exit 1
}

# ============================================================
# [3/6] 安装后端依赖
# ============================================================
Log ""
Log "============================================================"
Log "  [3/6] 安装后端依赖 ..."
Log "============================================================"

$reqFile = Join-Path $scriptDir "back\requirements.txt"
$depsOk  = $true

if (-not (Test-Path $reqFile)) {
    Log "  [WARN] 未找到 requirements.txt，跳过依赖安装"
} else {
    # ---- 预检查：已安装则跳过，避免重复安装 ----
    $allInstalled = $true
    $requiredPackages = @("fastapi", "uvicorn", "pydantic")
    foreach ($pkg in $requiredPackages) {
        Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-c", "import $pkg") | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $allInstalled = $false
            break
        }
    }

    if ($allInstalled) {
        Log "  [OK] 所有依赖已就绪，跳过安装"
    } else {
        Log "  [..] 部分依赖缺失，开始安装 ..."

        $mirrors = @(
            @("清华镜像", "https://pypi.tuna.tsinghua.edu.cn/simple"),
            @("阿里云镜像", "https://mirrors.aliyun.com/pypi/simple"),
            @("中科大镜像", "https://pypi.mirrors.ustc.edu.cn/simple")
        )

        $mirrorOk = $false
        foreach ($m in $mirrors) {
            $mName = $m[0]; $mUrl = $m[1]
            Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "pip", "install", "-r", $reqFile, "-i", $mUrl) | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $mirrorOk = $true
                Log "  [OK] 依赖安装成功 ($mName)"
                break
            }
            Log "  [..] $mName 失败，尝试下一个..."
        }

        if (-not $mirrorOk) {
            Log "  [..] 镜像源均失败，尝试官方源..."
            Invoke-Python -exe $pyExe -preArgs $pyPre -cmdArgs @("-m", "pip", "install", "-r", $reqFile) | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $mirrorOk = $true
                Log "  [OK] 依赖安装成功 (官方源)"
            }
        }

        if (-not $mirrorOk) {
            Log "  [FAIL] 所有源均无法安装依赖，请检查网络"
            $depsOk = $false
        }
    }
}

if (-not $depsOk) {
    Read-Host "  按回车键退出..."
    exit 1
}

# ============================================================
# [4/6] 检查端口冲突
# ============================================================
Log ""
Log "============================================================"
Log "  [4/6] 检查端口冲突 ..."
Log "============================================================"

foreach ($port in @(3000, 8080)) {
    $procs = netstat -ano 2>&1 | Select-String ":$port\s+.*LISTEN"
    if ($procs) {
        Log "  [..] 端口 $port 被占用，尝试释放..."
        foreach ($line in $procs) {
            $parts  = ($line.ToString() -split '\s+')
            $pidVal = $parts[-1]
            Stop-Process -Id $pidVal -Force -ErrorAction SilentlyContinue
            Log "  [OK] 已释放端口 $port (PID: $pidVal)"
        }
    } else {
        Log "  [OK] 端口 $port 可用"
    }
}

# ============================================================
# 进程清理函数（确保无论怎么退出都能杀掉子进程）
# ============================================================
$cleanupDone = $false
$backendProc  = $null
$frontendProc = $null

function Stop-AllServices {
    if ($cleanupDone) { return }
    $cleanupDone = $true
    if ($backendProc) {
        # /T 杀掉整个进程树（uvicorn 子进程也能被清理）
        Start-Process "taskkill.exe" -ArgumentList "/PID $($backendProc.Id) /T /F" -WindowStyle Hidden -Wait
    }
    if ($frontendProc) {
        Start-Process "taskkill.exe" -ArgumentList "/PID $($frontendProc.Id) /T /F" -WindowStyle Hidden -Wait
    }
    Write-Host "  服务已停止，再见！"
}

try {
    # ============================================================
    # [5/6] 启动后端服务
    # ============================================================
    Log ""
    Log "============================================================"
    Log "  [5/6] 启动后端服务 (FastAPI, 端口 8080) ..."
    Log "============================================================"

    $backendDir = Join-Path $scriptDir "back"
    $backendProc = Start-Process -FilePath $pyExe `
        -ArgumentList ($pyPre + @("-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080")) `
        -WorkingDirectory $backendDir -PassThru -WindowStyle Hidden

    if ($backendProc) {
        Log "  [OK] 后端服务已启动 (PID: $($backendProc.Id))"
    } else {
        Log "  [WARN] 后端服务启动异常，请检查 back/main.py"
    }

    # ============================================================
    # [6/6] 启动前端服务
    # ============================================================
    Log ""
    Log "============================================================"
    Log "  [6/6] 启动前端服务 (HTTP Server, 端口 3000) ..."
    Log "============================================================"

    $frontendProc = Start-Process -FilePath $pyExe `
        -ArgumentList ($pyPre + @("server.py")) `
        -WorkingDirectory $scriptDir -PassThru -WindowStyle Hidden

    if ($frontendProc) {
        Log "  [OK] 前端服务已启动 (PID: $($frontendProc.Id))"
    } else {
        Log "  [WARN] 前端服务启动异常，请检查 server.py"
    }

    # ============================================================
    # 完成
    # ============================================================
    Log ""
    Log "============================================================"
    Log "  全部启动完成！"
    Log "============================================================"
    Log ""
    Log "  前端地址   : http://localhost:3000"
    Log "  后端地址   : http://localhost:8080"
    Log "  简历编辑器 : http://localhost:3000/resume-editor.html"
    Log ""
    Log "  正在打开浏览器..."
    Start-Process "http://localhost:3000"

    Log ""
    Log "  按任意键停止所有服务并退出..."
    [void][System.Console]::ReadKey($true)

} finally {
    # try/finally 确保叉掉窗口、Ctrl+C、正常按键三种退出方式都走清理
    Stop-AllServices
}

# 清理完成后暂停，防止控制台窗口闪退
Read-Host "  按回车键关闭窗口..."
