"""Compile the installer AND its embedded scripts; outer compilation alone misses their syntax."""
import pathlib
import re
import subprocess
import sys
import tempfile

source = pathlib.Path("Install_LumenGPU_0.2.lua")
text = source.read_text(encoding="utf-8")
scripts = re.findall(r"make\([^\n]*?'(LumenGPU_(?:Client|Server))',\[====\[\n(.*?)\n\]====\]\)", text, re.S)
assert sorted(name for name, _ in scripts) == ["LumenGPU_Client", "LumenGPU_Server"], "Missing embedded scripts"
with tempfile.TemporaryDirectory() as td:
    paths = [source]
    for name, body in scripts:
        path = pathlib.Path(td) / (name + ".luau")
        path.write_text(body, encoding="utf-8")
        paths.append(path)
    for path in paths:
        print("Compiling", path.name, flush=True)
        subprocess.run([sys.argv[1], str(path)], stdout=subprocess.DEVNULL, check=True)
print("All three Luau sources compiled successfully.")
