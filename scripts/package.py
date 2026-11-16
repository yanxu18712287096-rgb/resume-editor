#!/usr/bin/env python3
"""Package tracked project files only; excludes local resumes and environments."""
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / 'dist/resume-editor-mac-windows.zip'
output.parent.mkdir(exist_ok=True)
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        if name:
            archive.write(root / name, 'resume-editor/' + name)
print(output)
