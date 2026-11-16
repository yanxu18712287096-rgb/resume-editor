#!/usr/bin/env python3
"""
卡码简历 - PDF 导出服务（Python FastAPI 版）

参考 Java 后端 PdfExportService 的设计思路：
1. 使用系统已安装的 Edge 浏览器的 headless 模式将 HTML 精确渲染为 PDF
2. 无需额外下载任何依赖，直接调用系统 Edge 浏览器
3. 保证导出的 PDF 与浏览器预览效果完全一致（字体、颜色、布局、UI 样式）
"""

import os
import sys
import shutil
import subprocess
import tempfile
import time
import logging
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel

# ============================================
# 日志配置
# ============================================
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("resume-pdf")

# ============================================
# FastAPI 应用
# ============================================
app = FastAPI(
    title="卡码简历 PDF 导出服务",
    description="使用 Edge headless 将简历 HTML 精确渲染为 PDF",
    version="1.0.0",
)

# CORS 配置 — 允许前端跨域调用
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境应限制为具体域名
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================
# Edge 浏览器查找
# ============================================
EDGE_PATHS = [
    os.environ.get("RESUME_BROWSER_PATH", ""),
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    str(Path.home() / "Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
    str(Path.home() / "Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    os.path.expandvars("%LOCALAPPDATA%\\Microsoft\\Edge\\Application\\msedge.exe"),
    os.path.expandvars("%PROGRAMFILES%\\Microsoft\\Edge\\Application\\msedge.exe"),
    os.path.expandvars("%PROGRAMFILES(X86)%\\Microsoft\\Edge\\Application\\msedge.exe"),
]


def find_edge() -> Optional[str]:
    """在系统中查找 Edge 浏览器可执行文件路径"""
    # 1. 检查常见安装路径
    for path in EDGE_PATHS:
        if path and Path(path).exists():
            log.info("Edge 浏览器已找到: %s", path)
            return path

    for name in ("msedge", "google-chrome", "chromium", "chromium-browser"):
        executable = shutil.which(name)
        if executable:
            return executable

    if os.name != "nt":
        return None

    # 2. 尝试通过 where 命令查找
    try:
        result = subprocess.run(
            ["where", "msedge"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split("\n"):
                line = line.strip()
                if line and Path(line).exists():
                    log.info("Edge 浏览器已找到 (where): %s", line)
                    return line
    except Exception:
        pass

    log.warning("未找到 Edge 浏览器，PDF 导出功能不可用")
    return None


EDGE_PATH = find_edge()


# ============================================
# 请求/响应模型
# ============================================
class PdfExportRequest(BaseModel):
    html: str
    filename: str = "我的简历"


class HealthResponse(BaseModel):
    status: str
    edge_found: bool
    edge_path: Optional[str] = None


# ============================================
# PDF 导出核心函数
# ============================================
def convert_html_to_pdf(html: str, filename: str) -> bytes:
    """
    将完整 HTML 页面转换为 PDF 字节数组。

    使用 Edge headless 模式的 --print-to-pdf 功能，
    与 Java 后端 PdfExportService.convertHtmlToPdf() 逻辑一致。

    Args:
        html: 完整的 HTML 文档字符串（含 DOCTYPE、style、内容）
        filename: 导出文件名（不含扩展名，仅用于日志）

    Returns:
        PDF 文件的字节数组

    Raises:
        RuntimeError: Edge 未找到、超时或生成失败
    """
    global EDGE_PATH

    # 如果之前未找到，再尝试查找一次（可能 Edge 刚安装）
    if EDGE_PATH is None:
        EDGE_PATH = find_edge()
    if EDGE_PATH is None:
        raise RuntimeError("未找到 Edge 浏览器，请安装 Microsoft Edge")

    temp_html = None
    temp_pdf = None

    try:
        # 将 HTML 写入临时文件
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".html", delete=False, encoding="utf-8"
        ) as f:
            f.write(html)
            temp_html = f.name

        # PDF 输出临时文件
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            temp_pdf = f.name
        # Edge headless 不会覆盖已存在的文件，确保删除
        if Path(temp_pdf).exists():
            Path(temp_pdf).unlink()

        # 构建命令行参数 — 与 Java 版本完全一致
        cmd = [
            EDGE_PATH,
            "--headless",
            "--disable-gpu",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--disable-extensions",
            "--disable-sync",
            "--hide-scrollbars",
            "--virtual-time-budget=10000",
            "--print-to-pdf-no-header",
            f"--print-to-pdf={temp_pdf}",
            Path(temp_html).absolute().as_uri(),
        ]

        log.info("正在调用 Edge headless 生成 PDF: %s", filename)

        # 启动 Edge 进程
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            # 等待进程完成（超时 60 秒）
            stdout_data, _ = process.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise RuntimeError("Edge 浏览器超时，PDF 生成失败")

        exit_code = process.returncode
        if exit_code != 0:
            log.warning("Edge 退出码: %d, 输出: %s", exit_code, stdout_data)
            # 即使退出码非零，PDF 可能已生成，继续检查

        # 检查 PDF 是否生成成功
        pdf_path = Path(temp_pdf)
        if not pdf_path.exists() or pdf_path.stat().st_size == 0:
            raise RuntimeError("Edge 未能生成 PDF 文件")

        pdf_bytes = pdf_path.read_bytes()
        log.info("PDF 生成成功: %s (%d 字节)", filename, len(pdf_bytes))
        return pdf_bytes

    except Exception as e:
        log.error("PDF 生成失败: %s", str(e))
        raise RuntimeError(f"PDF 生成失败: {str(e)}") from e

    finally:
        # 清理临时文件
        for tmp_file in [temp_html, temp_pdf]:
            if tmp_file:
                try:
                    Path(tmp_file).unlink(missing_ok=True)
                except Exception:
                    pass


# ============================================
# API 端点
# ============================================


@app.get("/api/health", response_model=HealthResponse)
def health_check():
    """健康检查 — 检查 Edge 是否可用"""
    return HealthResponse(
        status="ok",
        edge_found=EDGE_PATH is not None,
        edge_path=EDGE_PATH,
    )


@app.post("/api/export-pdf")
async def export_pdf(request: PdfExportRequest):
    """
    将 HTML 渲染为 PDF 并下载。

    请求体:
        html: 完整的 HTML 文档字符串
        filename: 导出文件名（可选，默认"我的简历"）

    返回: PDF 文件下载

    与 Java 后端 POST /api/resumes/export-pdf 接口一致。
    """
    html = request.html
    filename = request.filename

    if not html or not html.strip():
        raise HTTPException(status_code=400, detail="HTML 内容不能为空")

    if EDGE_PATH is None:
        raise HTTPException(
            status_code=503,
            detail="PDF 导出服务未就绪（请确保已安装 Microsoft Edge 或 Google Chrome 浏览器）",
        )

    try:
        pdf_bytes = convert_html_to_pdf(html, filename)
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))

    # 中文文件名编码（RFC 5987）
    encoded_filename = filename.encode("utf-8")
    percent_encoded = "".join(
        f"%{b:02X}" for b in encoded_filename
    )

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": (
                f'attachment; filename="resume.pdf"; '
                f"filename*=UTF-8''{percent_encoded}.pdf"
            ),
            "Content-Length": str(len(pdf_bytes)),
        },
    )


# ============================================
# 启动入口
# ============================================
if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print("=" * 50)
    print("  卡码简历 PDF 导出服务")
    print("=" * 50)
    print()
    print(f"  API 地址: http://localhost:{port}")
    print(f"  健康检查: http://localhost:{port}/api/health")
    print(f"  导出接口: POST http://localhost:{port}/api/export-pdf")
    print()
    if EDGE_PATH:
        print(f"  Edge 浏览器: {EDGE_PATH}")
    else:
        print("  ⚠️ 未找到 Edge 浏览器，PDF 导出不可用")
    print()
    print("  按 Ctrl+C 停止服务")
    print()

    uvicorn.run(app, host="127.0.0.1", port=port, log_level="info")
