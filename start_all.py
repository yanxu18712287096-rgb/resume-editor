#!/usr/bin/env python3
"""
我的简历 - 一键启动脚本（零基础小白友好版）
自动检测环境、安装依赖、释放端口、启动前后端
"""
import os
import sys
import time
import subprocess
import threading
import urllib.request
import urllib.error
import signal
import shutil

ROOT = os.path.dirname(os.path.abspath(__file__))
FRONTEND_PORT = 3000
BACKEND_PORT = 8080
FRONTEND_URL = f"http://localhost:{FRONTEND_PORT}"
BACKEND_URL = f"http://localhost:{BACKEND_PORT}"

_procs = {}

# 多个国内镜像源（按优先级排列）
PIP_MIRRORS = [
    "https://pypi.tuna.tsinghua.edu.cn/simple",
    "https://mirrors.aliyun.com/pypi/simple/",
    "https://pypi.mirrors.ustc.edu.cn/simple/",
    "https://pypi.doubanio.com/simple/",
]


# 检测到的 Python 执行器
PYTHON = None

# ============================================================
#  工具函数
# ============================================================

def log(msg: str):
    print(msg, flush=True)


def log_inline(msg: str):
    print(msg, end="", flush=True)


def exec_cmd(cmd, timeout=60, capture=True):
    """执行命令，返回 (returncode, stdout, stderr)"""
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        stdout, stderr = proc.communicate(timeout=timeout)
        return proc.returncode, stdout.strip(), stderr.strip()
    except subprocess.TimeoutExpired:
        proc.kill()
        return -1, "", "timeout"
    except Exception as e:
        return -1, "", str(e)


def kill_by_port(port: int):
    """根据端口号杀掉占用进程"""
    try:
        code, out, _ = exec_cmd(["netstat", "-ano"], timeout=10)
        if code != 0:
            return
        for line in out.splitlines():
            if f":{port}" in line and "LISTENING" in line:
                parts = line.strip().split()
                if parts:
                    pid = parts[-1]
                    if pid.isdigit() and int(pid) > 0:
                        exec_cmd(["taskkill", "/F", "/PID", pid], timeout=5)
                        log(f"  [OK] 已释放端口 {port} (PID {pid})")
    except Exception:
        pass


def check_port(port: int, path="/api/health") -> bool:
    """检查端口是否已被占用"""
    try:
        req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method="GET")
        urllib.request.urlopen(req, timeout=2)
        return True
    except urllib.error.HTTPError:
        return True
    except Exception:
        return False


def wait_for(name: str, check_fn, timeout: int = 60) -> bool:
    """轮询等待服务就绪"""
    for i in range(timeout):
        if check_fn():
            return True
        if i % 10 == 0 and i > 0:
            log(f"  [{name}] 等待中 ... ({i}s)")
        time.sleep(1)
    return False


def kill_proc_tree(proc):
    """安全终止进程"""
    if proc is None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=3)
    except Exception:
        try:
            proc.kill()
            proc.wait(timeout=2)
        except Exception:
            pass


def cleanup():
    """清理所有子进程 + 端口"""
    log("")
    log("  [清理] 正在停止所有服务 ...")
    for name, proc in _procs.items():
        kill_proc_tree(proc)
    time.sleep(1)
    for port in [BACKEND_PORT, FRONTEND_PORT]:
        kill_by_port(port)
    log("  [OK] 所有服务已停止。")


# ============================================================
#  环境检测
# ============================================================

def check_python():
    """检查 Python 是否安装，未安装则自动下载安装"""
    log("  [1/7] 检查 Python 环境 ...")

    # 先尝试用 sys.executable，失败则找 python/py
    python_exe = sys.executable
    code, out, _ = exec_cmd([python_exe, "--version"])
    if code != 0:
        # 尝试 python 命令
        code, out, _ = exec_cmd(["python", "--version"])
        if code == 0:
            python_exe = "python"
        else:
            # 尝试 py -3
            code, out, _ = exec_cmd(["py", "-3", "--version"])
            if code == 0:
                python_exe = "py -3"
            else:
                log("  [..] 未检测到 Python，准备自动下载安装 ...")
                return install_python()

    log(f"  [OK] {out.strip()}")

    # 检查 pip
    code, _, _ = exec_cmd([python_exe, "-m", "pip", "--version"])
    if code != 0:
        log("  [FAIL] pip 不可用，尝试修复 ...")
        code, _, _ = exec_cmd([python_exe, "-m", "ensurepip", "--upgrade"], timeout=30)
        if code != 0:
            log("  [FAIL] pip 修复失败，请重新安装 Python（勾选 'Add to PATH'）")
            sys.exit(1)
        log("  [OK] pip 已修复")
    else:
        log("  [OK] pip 已就绪")

    # 将 python_exe 设为主执行器供后续使用
    global PYTHON
    PYTHON = python_exe
    log("")


def install_python():
    """自动下载并安装 Python"""
    import urllib.request
    import shutil

    PYTHON_VERSION = "3.12.4"
    PYTHON_URL = f"https://www.python.org/ftp/python/{PYTHON_VERSION}/python-{PYTHON_VERSION}-amd64.exe"
    installer_name = f"python-{PYTHON_VERSION}-amd64.exe"
    installer_path = os.path.join(ROOT, installer_name)

    log(f"  [..] 正在下载 Python {PYTHON_VERSION} ...")
    log(f"       下载地址: {PYTHON_URL}")
    log(f"       保存到: {installer_path}")

    # 用 urllib 下载，显示进度
    try:
        req = urllib.request.Request(PYTHON_URL, headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        })
        with urllib.request.urlopen(req, timeout=120) as response:
            total = int(response.headers.get("Content-Length", 0))
            downloaded = 0
            with open(installer_path, "wb") as f:
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total > 0:
                        pct = int(downloaded * 100 / total)
                        log_inline(f"\r  [..] 下载中 ... {pct}%")
                    else:
                        log_inline(f"\r  [..] 已下载 {downloaded // 1024} KB")
    except Exception as e:
        log(f"\n  [FAIL] 下载失败: {e}")
        log("         请手动下载安装:")
        log(f"         {PYTHON_URL}")
        sys.exit(1)

    log("\n  [OK] 下载完成，正在启动安装程序 ...")
    log("  [..] 请在弹出的安装窗口中:")
    log("        1. 勾选底部 \"Add Python to PATH\"")
    log("        2. 点击 \"Install Now\"")
    log("")

    # 启动安装程序
    try:
        subprocess.Popen([installer_path], creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except Exception:
        os.startfile(installer_path)

    # 等待用户安装完成
    input("  安装完成后按回车键继续 ...")

    # 删除安装包
    try:
        os.remove(installer_path)
    except Exception:
        pass

    # 重新检测 Python
    log("  [..] 验证安装 ...")
    code, out, _ = exec_cmd(["python", "--version"])
    if code != 0:
        code, out, _ = exec_cmd(["py", "-3", "--version"])
        if code != 0:
            log("  [FAIL] Python 仍未检测到，请确保安装时勾选了 'Add Python to PATH'")
            log("         安装完成后手动关闭此窗口再重新运行 start.bat")
            sys.exit(1)

    global PYTHON
    PYTHON = "python"
    log(f"  [OK] {out.strip()}，安装成功！")
    log("")


def _parse_requirements(req_file: str) -> list:
    """从 requirements.txt 中解析包名（不含版本号）"""
    packages = []
    try:
        with open(req_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                # 取 == 或 >= 等符号之前的部分作为包名
                pkg_name = line.split("==")[0].split(">=")[0].split("<=")[0].split("~=")[0].split("!=")[0].strip()
                if pkg_name:
                    packages.append(pkg_name)
    except Exception:
        pass
    return packages


def install_deps():
    """安装后端 Python 依赖"""
    log("  [2/7] 检查后端依赖 ...")

    py = PYTHON or sys.executable
    req_file = os.path.join(ROOT, "back", "requirements.txt")

    if not os.path.exists(req_file):
        log("  [WARN] 未找到 requirements.txt，跳过依赖安装")
        log("")
        return

    # 从 requirements.txt 动态解析需要检查的包名（与安装保持一致）
    required_packages = _parse_requirements(req_file)

    # 检查是否已安装
    if required_packages:
        all_installed = True
        for dep in required_packages:
            code, _, _ = exec_cmd([py, "-c", f"import {dep}"])
            if code != 0:
                all_installed = False
                break

        if all_installed:
            log("  [OK] 所有依赖已就绪")
            log("")
            return

    log("  [..] 部分依赖缺失，开始安装 ...")

    # 使用多个镜像源依次尝试安装
    installed = False
    for mirror in PIP_MIRRORS:
        log(f"  [..] 尝试镜像: {mirror}")
        code, _, err = exec_cmd(
            [py, "-m", "pip", "install",
             "-r", req_file,
             "-i", mirror,
             "--trusted-host", mirror.split("/")[2]],
            timeout=120,
        )
        if code == 0:
            installed = True
            # 保存镜像配置方便下次使用
            exec_cmd([py, "-m", "pip", "config", "set",
                      "global.index-url", mirror], timeout=10)
            log(f"  [OK] 依赖安装成功")
            break
        else:
            log(f"  [..] 此镜像失败，切换下一个 ...")

    if not installed:
        log("  [FAIL] 所有镜像源均无法安装依赖")
        log("         请检查网络连接或手动执行:")
        log(f"         pip install -r {req_file}")
        sys.exit(1)
    log("")


def check_edge():
    """检查 Edge 浏览器（用于 PDF 导出）"""
    log("  [3/7] 检查 PDF 导出环境 ...")
    edge_path = shutil.which("msedge")
    if edge_path:
        log("  [OK] Microsoft Edge 已就绪")
    else:
        log("  [WARN] 未检测到 Edge 浏览器")
        log("         PDF 导出不可用，编辑器内导出将使用浏览器打印方案")
    log("")


def check_ports():
    """检查并释放端口"""
    log("  [4/7] 检查端口冲突 ...")
    for port, name in [(BACKEND_PORT, "后端"), (FRONTEND_PORT, "前端")]:
        if check_port(port, "/api/health" if port == BACKEND_PORT else "/"):
            log(f"  [..] {name}端口 {port} 被占用，正在释放 ...")
            kill_by_port(port)
            time.sleep(1)
            if check_port(port, "/api/health" if port == BACKEND_PORT else "/"):
                log(f"  [FAIL] {name}端口 {port} 无法释放，请手动关闭占用程序")
                sys.exit(1)
        log(f"  [OK] {name}端口 {port} 可用")
    log("")


# ============================================================
#  启动服务
# ============================================================

def start_backend():
    """启动后端 FastAPI PDF 导出服务"""
    log("  [5/7] 启动后端 PDF 导出服务 ...")
    backend_dir = os.path.join(ROOT, "back")
    log_file = os.path.join(backend_dir, "uvicorn.out.log")

    py = PYTHON or sys.executable

    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"

    proc = subprocess.Popen(
        [py, "-m", "uvicorn", "main:app",
         "--host", "127.0.0.1", "--port", str(BACKEND_PORT)],
        stdout=open(log_file, "w", encoding="utf-8"),
        stderr=subprocess.STDOUT,
        cwd=backend_dir,
        env=env,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    _procs["backend"] = proc

    if wait_for("backend", lambda: check_port(BACKEND_PORT, "/api/health"), timeout=30):
        log(f"  [OK] 后端已就绪 → {BACKEND_URL}/api/health")
    else:
        log("  [WARN] 后端启动超时，PDF 导出不可用")
        log(f"         查看日志: {log_file}")
    log("")


def start_frontend():
    """启动前端 HTTP 服务"""
    log("  [6/7] 启动前端服务 ...")
    server_script = os.path.join(ROOT, "server.py")

    py = PYTHON or sys.executable

    proc = subprocess.Popen(
        [py, server_script, str(FRONTEND_PORT)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=ROOT,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )
    _procs["frontend"] = proc

    if wait_for("frontend", lambda: check_port(FRONTEND_PORT, "/"), timeout=30):
        log(f"  [OK] 前端已就绪 → {FRONTEND_URL}")
    else:
        log("  [FAIL] 前端启动失败，请检查端口是否被占用")
        sys.exit(1)
    log("")


def open_browser():
    """打开浏览器"""
    log("  [7/7] 打开浏览器 ...")
    try:
        os.startfile(FRONTEND_URL)
    except Exception:
        try:
            subprocess.run(["cmd", "/c", "start", FRONTEND_URL],
                           capture_output=True, timeout=5)
        except Exception:
            pass
    log("")


# ============================================================
#  主流程
# ============================================================

def main():
    os.chdir(ROOT)

    log("")
    log("  =================================================")
    log("     我的简历 - 一键启动")
    log("     Resume Editor - Auto Startup")
    log("  =================================================")
    log("")

    try:
        # 1) Python 检测
        check_python()

        # 2) 依赖安装
        install_deps()

        # 3) Edge 检测
        check_edge()

        # 4) 端口检查
        check_ports()

        # 5) 启动后端
        start_backend()

        # 6) 启动前端
        start_frontend()

        # 7) 打开浏览器
        open_browser()

        # 显示完成信息
        log("  ─────────────────────────────────────────────")
        log(f"  前端地址: {FRONTEND_URL}")
        log(f"  后端地址: {BACKEND_URL}/api/health")
        log("  关闭此窗口即可停止所有服务")
        log("  ─────────────────────────────────────────────")
        log("")

        # 等待用户退出
        signal.signal(signal.SIGINT, lambda s, f: (cleanup(), sys.exit(0)))

        try:
            while all(p.poll() is None for p in _procs.values()
                      if isinstance(p, subprocess.Popen)):
                time.sleep(1)
        except KeyboardInterrupt:
            pass

    except SystemExit:
        cleanup()
        raise
    except Exception as e:
        log(f"  [ERROR] 发生异常: {e}")
        cleanup()
        sys.exit(1)

    finally:
        cleanup()


if __name__ == "__main__":
    main()
