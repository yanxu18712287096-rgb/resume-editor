#!/usr/bin/env python3
"""卡码简历开发服务器 - 智能缓存策略"""
import http.server
import os
import sys
import mimetypes

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 3000

# 缓存策略（单位：秒）
CACHE_RULES = {
    # HTML → 不缓存（始终最新）
    ".html": 0,
    # CSS/JS → 缓存 1 天
    ".css": 86400,
    ".js": 86400,
    # 图片/字体 → 缓存 7 天
    ".png": 604800,
    ".jpg": 604800,
    ".jpeg": 604800,
    ".gif": 604800,
    ".ico": 604800,
    ".svg": 604800,
    ".webp": 604800,
    ".woff": 604800,
    ".woff2": 604800,
    ".ttf": 604800,
    ".eot": 604800,
}


def _get_cache_seconds(path: str) -> int:
    """根据文件后缀获取缓存秒数"""
    _, ext = os.path.splitext(path)
    return CACHE_RULES.get(ext.lower(), 0)


class CachedHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """智能缓存 HTTP 请求处理器"""

    def end_headers(self):
        path = self.path.split("?")[0]  # 去掉查询参数
        cache_seconds = _get_cache_seconds(path)

        if cache_seconds > 0:
            # 静态资源 → 启用缓存
            self.send_header(
                "Cache-Control",
                f"public, max-age={cache_seconds}, immutable"
            )
        else:
            # HTML 等动态页面 → 不缓存
            self.send_header(
                "Cache-Control",
                "no-cache, no-store, must-revalidate"
            )
            self.send_header("Pragma", "no-cache")
            self.send_header("Expires", "0")

        super().end_headers()

    def log_message(self, format, *args):
        sys.stderr.write("[%s] %s - %s\n" % (
            self.log_date_time_string(),
            self.client_address[0],
            format % args
        ))


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    server = http.server.HTTPServer(
        ("127.0.0.1", PORT), CachedHTTPRequestHandler
    )
    print("========================================")
    print("  卡码简历开发服务器")
    print("  Cache: HTML=禁用 | CSS/JS=1天 | 图片/字体=7天")
    print("========================================")
    print()
    print("  Access: http://localhost:%s" % PORT)
    print()
    print("[OK] 服务已启动，按 Ctrl+C 停止")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务器已停止")
        server.server_close()
