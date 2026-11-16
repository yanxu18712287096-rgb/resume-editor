# 我的简历 - Resume Editor

一款**轻量、开源、多功能**的在线简历编辑器。无需注册账号，无需搭建后端服务器，打开浏览器即可编辑和导出简历。支持多份简历管理、所见即所得编辑、11 种简历模块自由组合、PDF 导出等功能。

## macOS 启动

1. 安装 Python 3 和 Google Chrome 或 Microsoft Edge。
2. 双击 `start.command`，首次启动会在项目 `.venv` 中安装依赖。
3. 浏览器自动打开 http://localhost:3000，使用期间保留终端窗口，按 Ctrl+C 停止服务。

也可以在项目目录执行 `bash start.command`。路径含中文或空格均可。
端口 3000 / 8080 被占用时会提示退出，请先停止原服务。
浏览器不在常见位置时，可设置环境变量 `RESUME_BROWSER_PATH` 为浏览器可执行文件路径。

### Windows 备份兼容

Windows 仍使用原有 `start.bat`；Mac 使用独立依赖文件，不改变 Windows 的依赖版本。
在 Windows 编辑器中选择“导出备份”得到 JSON，将文件复制到 Mac，打开简历编辑器选择“导入备份”。Mac 导出的 JSON 也可在 Windows 导入。
浏览器本地数据不会自动跨电脑同步；PDF 是成品，不能作为可编辑备份导入。两端字体不同可能影响分页，导出前请检查预览。

## 🚀 Windows 快速开始

### 方式一：一键部署（推荐，电脑零基础也能用）

<p>
  <a href="https://gitee.com/deardhp/jianli/raw/master/%E7%AE%80%E5%8E%86%E7%BD%91%E7%AB%99%E9%83%A8%E7%BD%B2.exe" style="display:inline-block;background:linear-gradient(135deg,#4A90D9,#357ABD);color:#fff;padding:14px 36px;border-radius:10px;font-size:18px;font-weight:bold;text-decoration:none;box-shadow:0 4px 15px rgba(74,144,217,0.4);border:none;cursor:pointer;">
    ⬇️&nbsp; 一键下载 简历网站部署.exe
  </a>
</p>

> 如果上面链接无法下载，请登录 Gitee 后访问 [仓库文件页](https://gitee.com/deardhp/jianli) 直接下载。

下载后双击运行，脚本将自动完成以下全部步骤：

```
┌────────────────────────────────────────────┐
│ ① 检测 Git → 未安装则自动下载 + 静默安装     │
│     ↓                                      │
│ ② git clone → 项目下载到桌面                │
│     ↓                                      │
│ ③ 自动启动 start.bat → 浏览器打开简历编辑器   │
└────────────────────────────────────────────┘
```

> ⚡ 全程无人值守，下载 Git 使用国内高速镜像（华为云 / 腾讯云 / 淘宝 NPM），几秒完成。

---

### 方式二：手动安装（适合已安装 Git 的用户）

```bash
# 1. 克隆项目到本地
git clone https://gitee.com/deardhp/jianli.git

# 2. 进入项目目录
cd jianli

# 3. 双击 start.bat 启动
```

![输入图片说明](image.png)

启动脚本通过 **PowerShell**（`start.ps1`）自动执行以下 6 个步骤：

1. ✅ **[1/6] 检测 Python 环境** — 优先使用系统已安装的 Python（≥ 3.8），未安装或版本过低则自动下载 Python 3.12.x
   - 下载顺序：华为云镜像 → 清华镜像 → Python 官网
   - 版本回退：3.12.10 → 3.12.9 → 3.12.8 → 3.12.7
   - 兜底方案：winget 安装
2. ✅ **[2/6] 检测 pip** — 确保 pip 可用，失败则自动修复（`ensurepip` / `get-pip.py`）
3. ✅ **[3/6] 安装后端依赖** — 先检查 `fastapi`、`uvicorn`、`pydantic` 是否已安装，已就绪则跳过；缺失则通过镜像源安装
4. ✅ **[4/6] 检查端口冲突** — 自动释放 3000 / 8080 端口
5. ✅ **[5/6] 启动后端服务** — FastAPI PDF 导出服务（端口 8080）
6. ✅ **[6/6] 启动前端服务** — HTTP 开发服务器（端口 3000）→ 自动打开浏览器

> 如 PowerShell 不可用，脚本会自动回退到 **Python 启动器**（`start_all.py`）执行 7 个步骤。

> PDF 导出功能需要后端服务支持，请使用一键部署或一键启动。

## 🏗️ 技术栈

| 层次 | 技术 |
|------|------|
| 前端 | 原生 HTML + CSS + JavaScript（零框架依赖） |
| Markdown 渲染 | [marked.js](https://cdn.jsdelivr.net/npm/marked/marked.min.js) |
| 后端 | Python FastAPI + uvicorn（仅 PDF 导出） |
| 数据存储 | 浏览器 localStorage |
| 离线支持 | Service Worker（预缓存 + 运行时缓存） |
| PDF 生成 | Microsoft Edge headless 模式（`--print-to-pdf`） |
| 开发服务器 | Python http.server（智能缓存策略） |
| 部署工具 | `简历网站部署.exe`（PyInstaller + 嵌入式 PowerShell） |
| 启动器 | PowerShell（`start.ps1`，主力）+ Python（`start_all.py`，回退） |

## 📁 项目结构

```
├── index.html              # 首页 — 简历列表（卡片网格展示 + 增删改查）
├── resume-editor.html      # ⭐ 核心页面 — 简历编辑器（4000+ 行，含模板引擎）
├── about.html              # 更多资料 / 关于页面
├── styles.css              # 全局样式（CSS 变量设计系统）
├── server.py               # 前端开发服务器（智能缓存：HTML 禁用 / CSS/JS 1天 / 图片 7天）
├── sw.js                   # Service Worker 离线缓存（v2）
├── favicon.svg             # 网站图标
├── 简历网站部署.exe          # 一键部署工具（双击自动装Git+克隆+启动）
├── install_git.ps1          # 一键部署源码（PowerShell，可独立运行）
├── start.bat               # Windows 批处理入口（调用 start.ps1）
├── start.ps1               # PowerShell 一键启动（6 步自动启动，520 行）
├── start_all.py            # Python 启动器（回退方案，7 步启动）
└── back/
    ├── main.py             # FastAPI PDF 导出服务（Edge headless 渲染）
    └── requirements.txt    # Python 依赖（fastapi / uvicorn / pydantic）
```

## 📄 使用须知

本工具仅供个人学习与交流使用，**严禁用于任何商业用途**。未经作者许可，不得将本工具或其衍生版本用于商业目的。

本项目基于 **Apache License 2.0** 开源协议。

## 📱 获取更多资料

关注微信公众号或添加作者微信，免费获取简历模板和编程学习资料。

> 关注公众号 阿鹏随笔录 后回复「简历」即可领取
