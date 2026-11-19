"""按确定顺序计算发行目录中所有文件的哈希值，排除校验文件自身。"""
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
entries = []
for path in sorted(root.rglob("*")):
    if path.is_file() and path.name != "SHA256SUMS":
        entries.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root)}")
(root / "SHA256SUMS").write_text("\n".join(entries) + "\n")
