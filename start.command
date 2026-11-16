#!/bin/bash
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
    echo '请先安装 Python 3（https://www.python.org/downloads/macos/），然后重新启动。'
    read -r -p '按回车退出…'
    exit 1
fi
python3 start_mac.py
result=$?
if [ "$result" -ne 0 ]; then
    read -r -p '启动失败，按回车退出…'
fi
exit "$result"
