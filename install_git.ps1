# ============================================================
#  Git 自动安装脚本 - 一键安装 Git + 克隆仓库
#  自动检测 Git → 下载安装 Git → 验证安装 → 执行 Git 命令
#  全程无需手动操作
# ============================================================

param(
    [string]$RepoUrl = "https://github.com/yanxu18712287096-rgb/resume-editor.git",
    [string]$CloneDir  = "$env:USERPROFILE\Desktop\jianli",
    [string]$GitCommand = ""   # 留空则默认执行 git clone
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($scriptDir) { Set-Location $scriptDir }

$ErrorActionPreference = "SilentlyContinue"
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
#  工具函数
# ============================================================
function Log($msg) { Write-Host $msg }

# 校验 Git 版本是否满足最低要求（最低 2.30）
$MIN_MAJOR = 2
$MIN_MINOR = 30
function Test-GitVersion {
    param([string]$versionString)
    $m = [regex]::Match($versionString, '(\d+)\.(\d+)')
    if (-not $m.Success) { return $false }
    $maj = [int]$m.Groups[1].Value
    $min = [int]$m.Groups[2].Value
    if ($maj -gt $MIN_MAJOR) { return $true }
    if ($maj -eq $MIN_MAJOR -and $min -ge $MIN_MINOR) { return $true }
    return $false
}

# 带进度条的文件下载
function Download-File {
    param([string]$url, [string]$dest, [string]$description)
    $ErrorActionPreference = "SilentlyContinue"
    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Timeout = 30000
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        $req.Accept = "*/*"
        $resp = $req.GetResponse()
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
                $pct = [math]::Round(($totalRead / $totalBytes) * 100)
                if ($pct -ge $lastPct + 2 -or $pct -eq 100) {
                    $speed = if ($sw.Elapsed.TotalSeconds -gt 0.1) {
                        [math]::Round(($totalRead / 1MB) / $sw.Elapsed.TotalSeconds, 1)
                    } else { 0 }
                    $done  = [math]::Round($totalRead / 1MB, 1)
                    $total = [math]::Round($totalBytes / 1MB, 1)
                    $barLen = 30
                    $filled = [math]::Round($barLen * $pct / 100)
                    $bar = ('#' * $filled) + ('-' * ($barLen - $filled))
                    Write-Host ("`r  [..] {0} : [{1}] {2}%  {3}/{4} MB  {5} MB/s" -f $description, $bar, $pct, $done, $total, $speed) -NoNewline
                    $lastPct = $pct
                }
            }
        }

        $fs.Close(); $stream.Close(); $resp.Close()
        Write-Host ""
        if ($totalRead -lt 1000000) {
            throw "下载不完整，实际仅收到 $totalRead bytes"
        }
        Write-Host "  [OK] $description 下载完成"
        return $true
    } catch {
        Write-Host ""
        Write-Host "  [FAIL] $description 下载失败: $($_.Exception.Message)"
        if ($fs) { try { $fs.Close() } catch {} }
        return $false
    }
}

# 旋转等待动画
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
    Write-Host ""
}

function Show-Banner {
    Log ""
    Log "╔════════════════════════════════════════════════════════╗"
    Log "║        Git 自动安装工具  v1.0                         ║"
    Log "║        一键安装 Git + 克隆仓库                        ║"
    Log "╚════════════════════════════════════════════════════════╝"
}

function Show-Usage {
    Log ""
    Log "  用法:"
    Log "    .\install_git.ps1"
    Log "    .\install_git.ps1 -RepoUrl ""https://xxx.git"" -CloneDir ""C:\目标路径"""
    Log "    .\install_git.ps1 -GitCommand ""git status"""
    Log ""
    Log "  参数说明:"
    Log "    -RepoUrl     要克隆的仓库地址（默认: github.com/yanxu18712287096-rgb/resume-editor）"
    Log "    -CloneDir    克隆目标目录（默认: 桌面\jianli）"
    Log "    -GitCommand  自定义 Git 命令（留空则自动 clone）"
    Log ""
}

# ============================================================
# [1/5] 显示横幅
# ============================================================
Show-Banner

# ============================================================
# [2/5] 检测现有 Git 安装
# ============================================================
Log ""
Log "============================================================"
Log "  [1/4] 检测 Git 环境..."
Log "============================================================"

$gitExe   = $null
$gitFound = $false
$gitTooOld = $false

# 尝试 git
$testOut = & git --version 2>&1
if ($LASTEXITCODE -eq 0) {
    $vs = ($testOut -join ' ').Trim()
    if (Test-GitVersion $vs) {
        $gitExe = "git"
        $gitFound = $true
        Log "  [OK] 已安装 Git: $vs"
    } else {
        Log "  [WARN] Git 版本过低: $vs (最低要求 2.30)"
        $gitTooOld = $true
    }
}

# 检查常见安装路径
if (-not $gitFound) {
    $commonPaths = @(
        "$env:ProgramFiles\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\bin\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\git.exe",
        "C:\Git\bin\git.exe"
    )
    foreach ($p in $commonPaths) {
        if (Test-Path $p) {
            $testOut = & $p --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $vs = ($testOut -join ' ').Trim()
                if (Test-GitVersion $vs) {
                    $gitExe = $p
                    $gitFound = $true
                    Log "  [OK] 找到 Git ($p): $vs"
                    break
                }
            }
        }
    }
}

# ============================================================
# [3/5] 自动安装 Git（如果未检测到）
# ============================================================
if (-not $gitFound) {
    if ($gitTooOld) {
        Log "  [WARN] 已找到的 Git 版本过低（要求 >= 2.30）"
        Log "  [..] 准备自动安装最新版 Git ..."
    } else {
        Log "  [..] 未检测到 Git，准备自动安装 ..."
    }

    Log ""
    Log "============================================================"
    Log "  [2/4] 安装 Git for Windows ..."
    Log "============================================================"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installed = $false

    # ================================================================
    # 方案 A: 直接下载 Git 安装包 + 静默安装（优先，有进度条反馈）
    # ================================================================
    $gitVersions = @(
        @{ver="2.54.0"; pkg="v2.54.0.windows.1/Git-2.54.0-64-bit.exe"},
        @{ver="2.53.0"; pkg="v2.53.0.windows.1/Git-2.53.0-64-bit.exe"},
        @{ver="2.52.0"; pkg="v2.52.0.windows.1/Git-2.52.0-64-bit.exe"}
    )

    # 下载源（国内高速镜像优先，GitHub 官方兜底）
    $gitMirrors = @(
        # 1. 华为云镜像 —— 国内速度最快之一
        "https://mirrors.huaweicloud.com/git-for-windows/{0}",
        # 2. 腾讯云镜像
        "https://mirrors.cloud.tencent.com/git-for-windows/{0}",
        # 3. 淘宝 NPM 镜像
        "https://registry.npmmirror.com/-/binary/git-for-windows/{0}",
        # 4. GitHub 官方（海外直连兜底）
        "https://github.com/git-for-windows/git/releases/download/{0}",
        # 5. ghproxy GitHub 代理（最后的兜底）
        "https://ghproxy.com/https://github.com/git-for-windows/git/releases/download/{0}"
    )

    $downloaded = $false
    $usedVer    = $null
    $usedPkg    = $null
    $usedInstaller = $null

    foreach ($gv in $gitVersions) {
        $v   = $gv.ver
        $pkg = $gv.pkg
        $installerPath = "$env:TEMP\Git-$v-64-bit.exe"
        Remove-Item $installerPath -ErrorAction SilentlyContinue

        foreach ($tpl in $gitMirrors) {
            $url = $tpl -f $pkg
            Log "  [..] 尝试 Git $v : $url"
            $ok = Download-File -url $url -dest $installerPath -description "Git $v"
            if ($ok -and (Test-Path $installerPath) -and ((Get-Item $installerPath).Length -gt 1000000)) {
                $downloaded    = $true
                $usedVer       = $v
                $usedPkg       = $pkg
                $usedInstaller = $installerPath
                break
            }
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            Log "  [..] 该源不可用，切换下一个..."
        }
        if ($downloaded) { break }
        Log "  [WARN] Git $v 所有源均不可用，尝试下一个版本..."
    }

    if ($downloaded) {
        Log "  [..] 正在后台静默安装 Git $usedVer (约 1 分钟) ..."
        Log "      安装期间请勿关闭此窗口，否则安装将中断"
        Start-Spinner -label "Git $usedVer 正在安装中"

        # Git 静默安装参数说明:
        #   /VERYSILENT    - 完全静默，无任何界面
        #   /NORESTART     - 安装后不重启
        #   /NOCANCEL      - 安装过程中不可取消
        #   /SP-           - 禁用"安装完成"提示
        #   /CLOSEAPPLICATIONS - 关闭相关应用
        #   /RESTARTAPPLICATIONS - 重启相关应用
        #   /SUPPRESSMSGBOXES - 禁止弹窗
        #   /NOICONS       - 不创建桌面图标
        #   /COMPONENTS    - 安装组件选择
        $gitInstallArgs = @(
            "/VERYSILENT",
            "/NORESTART",
            "/NOCANCEL",
            "/SP-",
            "/SUPPRESSMSGBOXES",
            "/CLOSEAPPLICATIONS",
            "/RESTARTAPPLICATIONS",
            "/NOICONS",
            "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh",
            "/DIR=" + "`"$env:ProgramFiles\Git`""
        )

        $proc = Start-Process -FilePath $usedInstaller `
            -ArgumentList $gitInstallArgs `
            -Wait -PassThru
        Stop-Spinner
        Remove-Item $usedInstaller -ErrorAction SilentlyContinue

        # 刷新 PATH 环境变量
        $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                     [System.Environment]::GetEnvironmentVariable("Path","User"))

        # 验证安装
        $v = & git --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $gitExe = "git"
            $gitFound = $true
            $installed = $true
            Log "  [OK] Git 安装成功: $(($v -join ' ').Trim())"
        } else {
            # 尝试刷新后再次检测
            Start-Sleep -Seconds 3
            $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                         [System.Environment]::GetEnvironmentVariable("Path","User"))
            $v = & "C:\Program Files\Git\bin\git.exe" --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $gitExe = "C:\Program Files\Git\bin\git.exe"
                $gitFound = $true
                $installed = $true
                Log "  [OK] Git 安装成功 (直接路径): $(($v -join ' ').Trim())"
            }
        }
    }

    # ================================================================
    # 方案 B: winget（直接下载失败后的保底）
    # ================================================================
    if (-not $installed) {
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Log "  [..] 直接下载均失败，尝试通过 winget 安装 Git ..."
            Log "       (winget 在后台工作，请耐心等待...)"
            Start-Spinner -label "winget 正在下载并安装 Git"
            winget install Git.Git --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            Stop-Spinner

            $env:Path = ([System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                         [System.Environment]::GetEnvironmentVariable("Path","User"))

            $v = & git --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                $gitExe = "git"
                $gitFound = $true
                $installed = $true
                Log "  [OK] winget 安装成功: $(($v -join ' ').Trim())"
            }
        }
    }

    # ================================================================
    # 全部失败
    # ================================================================
    if (-not $installed) {
        Log ""
        Log "  [FAIL] Git 自动安装失败"
        Log "         请手动安装 Git for Windows:"
        Log "         https://git-scm.com/download/win"
        Log "         https://npm.taobao.org/mirrors/git-for-windows/"
        Log ""
        Log "  窗口将在 30 秒后自动关闭..."
        Start-Sleep -Seconds 30
        exit 1
    }
}

# ============================================================
# [4/5] 配置 Git（首次使用）
# ============================================================
Log ""
Log "============================================================"
Log "  [3/4] 检查 Git 配置 ..."
Log "============================================================"

$userName = & $gitExe config --global user.name 2>&1
$userEmail = & $gitExe config --global user.email 2>&1

if (-not $userName -or -not $userEmail) {
    Log "  [..] Git 用户信息未配置，使用默认值..."
    if (-not $userName) {
        $defaultName = [System.Environment]::UserName
        & $gitExe config --global user.name $defaultName 2>&1 | Out-Null
        Log "  [OK] 已设置 user.name = $defaultName"
    } else {
        Log "  [OK] user.name = $userName"
    }
    if (-not $userEmail) {
        $defaultEmail = "$([System.Environment]::UserName)@users.noreply.github.com"
        & $gitExe config --global user.email $defaultEmail 2>&1 | Out-Null
        Log "  [OK] 已设置 user.email = $defaultEmail"
    } else {
        Log "  [OK] user.email = $userEmail"
    }
} else {
    Log "  [OK] Git 用户信息已配置"
    Log "       Name : $userName"
    Log "       Email: $userEmail"
}

# 设置常用配置
& $gitExe config --global core.autocrlf true 2>&1 | Out-Null          # Windows 换行符兼容
& $gitExe config --global pull.rebase false 2>&1 | Out-Null            # pull 默认 merge
& $gitExe config --global init.defaultBranch main 2>&1 | Out-Null      # 默认分支名
& $gitExe config --global http.sslVerify true 2>&1 | Out-Null          # 启用 SSL 验证
Log "  [OK] Git 常用配置已就绪"

# ============================================================
# [5/5] 执行 Git 命令
# ============================================================
Log ""
Log "============================================================"
Log "  [4/4] 执行 Git 命令 ..."
Log "============================================================"

if ($GitCommand) {
    # 自定义命令模式
    Log "  [>>] 执行: $GitCommand"
    Log ""
    & $gitExe $GitCommand.Split(' ') 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log ""
        Log "  [OK] 命令执行成功"
    } else {
        Log ""
        Log "  [WARN] 命令执行完成（退出码: $LASTEXITCODE）"
    }
} else {
    # 默认模式: 克隆仓库 → 自动启动项目
    Log "  仓库地址 : $RepoUrl"
    Log "  目标路径 : $CloneDir"
    Log ""

    $cloneSuccess = $false

    # 检查目标目录是否已存在
    if (Test-Path $CloneDir) {
        Log "  [WARN] 目标目录已存在: $CloneDir"
        $gitDir = Join-Path $CloneDir ".git"
        if (Test-Path $gitDir) {
            # 是有效的 Git 仓库，拉取最新代码
            Log "  [..] 检测到已有仓库，拉取最新代码..."
            Push-Location $CloneDir
            & $gitExe pull 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Log "  [OK] 仓库已更新到最新版本"
                $cloneSuccess = $true
            } else {
                Log "  [WARN] 拉取失败，将删除后重新克隆..."
                Pop-Location
                Remove-Item -Recurse -Force $CloneDir -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                # 重新克隆
            }
        } else {
            Log "  [..] 目录存在但不是 Git 仓库，删除后重新克隆..."
            Remove-Item -Recurse -Force $CloneDir -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }

    # 需要重新克隆
    if (-not $cloneSuccess) {
        $cloneResult = & $gitExe clone $RepoUrl $CloneDir 2>&1
        if ($LASTEXITCODE -eq 0) {
            Log ($cloneResult -join "`n")
            Log "  [OK] 仓库克隆成功!"
            $cloneSuccess = $true
        } else {
            Log "  [FAIL] 克隆失败: $($cloneResult -join ' ')"
            Log ""
            Log "  可能的原因:"
            Log "    1. 网络连接问题（国内访问 Gitee 通常较稳定）"
            Log "    2. 仓库地址错误"
            Log "    3. 目标路径无写入权限"
        }
    }

    # 克隆失败则退出
    if (-not $cloneSuccess) {
        Log ""
        Log "  窗口将在 30 秒后自动关闭..."
        Start-Sleep -Seconds 30
        exit 1
    }
}

# ============================================================
#  完成 → 自动启动项目
# ============================================================
Log ""
Log "============================================================"
Log "  全部完成！即将启动项目..."
Log "============================================================"
Log ""
$gitVer = & $gitExe --version 2>&1
Log "  Git     : $(($gitVer -join ' ').Trim())"

if (-not $GitCommand) {
    Log "  仓库    : $CloneDir"
    Log ""

    # 查找启动脚本
    $startBat  = Join-Path $CloneDir "start.bat"
    $startPs1  = Join-Path $CloneDir "start.ps1"
    $startAll  = Join-Path $CloneDir "start_all.py"
    $launchTarget = $null

    if (Test-Path $startBat) {
        $launchTarget = $startBat
        Log "  启动脚本: start.bat"
    } elseif (Test-Path $startPs1) {
        $launchTarget = $startPs1
        Log "  启动脚本: start.ps1"
    } elseif (Test-Path $startAll) {
        $launchTarget = $startAll
        Log "  启动脚本: start_all.py"
    }

    if ($launchTarget) {
        Log ""
        # 倒计时 3 秒，让用户看到摘要
        for ($i = 3; $i -ge 1; $i--) {
            Write-Host ("`r  将于 {0} 秒后自动启动..." -f $i) -NoNewline
            Start-Sleep -Seconds 1
        }
        Write-Host "`r  正在启动...                          "

        # 启动项目
        if ($launchTarget -match "\.bat$") {
            # .bat 文件：用 cmd 启动
            $procInfo = New-Object System.Diagnostics.ProcessStartInfo
            $procInfo.FileName = "cmd.exe"
            $procInfo.Arguments = "/c `"$launchTarget`""
            $procInfo.WorkingDirectory = $CloneDir
            $procInfo.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($procInfo) | Out-Null
        } elseif ($launchTarget -match "\.ps1$") {
            # .ps1 文件：用 PowerShell 启动
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$launchTarget`"" -WorkingDirectory $CloneDir
        } elseif ($launchTarget -match "\.py$") {
            # .py 文件：用 Python 启动
            Start-Process python.exe -ArgumentList "`"$launchTarget`"" -WorkingDirectory $CloneDir
        }

        Log "  [OK] 项目已启动！"
        Log ""
        Log "  启动器窗口将在 5 秒后自动关闭..."
        Start-Sleep -Seconds 5
    } else {
        Log ""
        Log "  [WARN] 未找到启动脚本，请手动运行:"
        Log "         $CloneDir\start.bat"
        Log ""
        Log "  窗口将在 30 秒后自动关闭..."
        Start-Sleep -Seconds 30
    }
} else {
    Log ""
    Log "  窗口将在 5 秒后自动关闭..."
    Start-Sleep -Seconds 5
}
