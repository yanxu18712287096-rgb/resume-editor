#!/usr/bin/env python3
"""macOS launcher; dependencies live in the project's .venv."""
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time
import urllib.request
import webbrowser

ROOT = Path(__file__).resolve().parent

def main():
    os.chdir(ROOT)
    for port in (3000, 8080):
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', port))
            except OSError:
                raise RuntimeError(f'端口 {port} 已被占用，请先关闭原来的服务。')
    python = ROOT / '.venv/bin/python'
    if not python.exists():
        subprocess.run([sys.executable, '-m', 'venv', str(ROOT / '.venv')], check=True)
    requirements = ROOT / 'back/requirements-mac.txt'
    subprocess.run([str(python), '-m', 'pip', 'install', '-r', str(requirements)], check=True)
    processes = []
    def stop(signum, frame):
        raise KeyboardInterrupt
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    try:
        processes.append(subprocess.Popen([str(python), '-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', '8080'], cwd=ROOT / 'back'))
        processes.append(subprocess.Popen([str(python), 'server.py'], cwd=ROOT))
        for url in ('http://localhost:8080/api/health', 'http://localhost:3000/'):
            for attempt in range(60):
                if any(p.poll() is not None for p in processes):
                    raise RuntimeError('服务启动失败，请查看上方日志。')
                try:
                    with urllib.request.urlopen(url, timeout=1):
                        break
                except OSError:
                    time.sleep(.5)
            else:
                raise RuntimeError(f'服务启动超时: {url}')
        print('已启动：http://localhost:3000；按 Ctrl+C 停止。', flush=True)
        webbrowser.open('http://localhost:3000')
        while all(p.poll() is None for p in processes):
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        for p in processes:
            if p.poll() is None:
                p.terminate()
        for p in processes:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'启动失败：{error}', file=sys.stderr)
        sys.exit(1)
