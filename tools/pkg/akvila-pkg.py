#!/usr/bin/env python3
"""Akvila Package Manager — minimal implementation.

Commands:
  akvila-pkg init          Create a new akvila.pkg manifest
  akvila-pkg build         Compile the project with dependencies
  akvila-pkg add <name>    Add a dependency (from registry or local path)
  akvila-pkg list          List installed dependencies
"""

import json
import os
import sys
import subprocess
import shutil

REGISTRY_URL = "https://pkg.akvila-lang.org"  # Future registry
PKG_DIR = ".akvila_packages"


def load_manifest(path="akvila.pkg"):
    """Load the package manifest."""
    if not os.path.exists(path):
        print(f"error: {path} not found. Run 'akvila-pkg init' first.")
        sys.exit(1)
    manifest = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                key = key.strip()
                val = val.strip().strip(";").strip().strip('"')
                if val.startswith("[") and val.endswith("]"):
                    val = [v.strip().strip('"') for v in val[1:-1].split(",") if v.strip()]
                manifest[key] = val
    return manifest


def cmd_init():
    """Create a new akvila.pkg manifest."""
    if os.path.exists("akvila.pkg"):
        print("akvila.pkg already exists.")
        return
    name = os.path.basename(os.getcwd())
    with open("akvila.pkg", "w") as f:
        f.write(f'// Akvila package manifest\n')
        f.write(f'name = "{name}";\n')
        f.write(f'version = "0.1.0";\n')
        f.write(f'license = "MPLS-1.0";\n')
        f.write(f'main = "src/main.akvila";\n')
        f.write(f'dependencies = [];\n')
    print(f"Created akvila.pkg for '{name}'")


def cmd_build():
    """Build the project."""
    manifest = load_manifest()
    main_file = manifest.get("main", "src/main.akvila")
    if not os.path.exists(main_file):
        print(f"error: main file '{main_file}' not found")
        sys.exit(1)

    compiler = os.environ.get("AKVILA_COMPILER", "akvila")
    name = manifest.get("name", "output")

    # Collect source files (main + dependencies)
    sources = [main_file]
    deps = manifest.get("dependencies", [])
    if isinstance(deps, str):
        deps = [deps] if deps else []
    for dep in deps:
        dep_path = os.path.join(PKG_DIR, dep, "src")
        if os.path.isdir(dep_path):
            for f in sorted(os.listdir(dep_path)):
                if f.endswith(".akvila"):
                    sources.append(os.path.join(dep_path, f))

    # For now, compile just the main file
    print(f"Building {name}...")
    result = subprocess.run(
        [compiler, main_file],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(result.stderr or result.stdout)
        sys.exit(1)

    # Write assembly output
    asm_file = f"build/{name}.asm"
    os.makedirs("build", exist_ok=True)
    with open(asm_file, "w") as f:
        f.write(result.stdout)

    # Assemble and link
    obj_file = f"build/{name}.o"
    bin_file = f"build/{name}"
    subprocess.run(["nasm", "-f", "elf64", "-o", obj_file, asm_file], check=True)
    subprocess.run(["ld", "-o", bin_file, obj_file], check=True)
    print(f"Built: {bin_file}")


def cmd_add(name):
    """Add a dependency."""
    manifest = load_manifest()
    deps = manifest.get("dependencies", [])
    if isinstance(deps, str):
        deps = [deps] if deps else []
    if name in deps:
        print(f"'{name}' is already a dependency.")
        return
    deps.append(name)

    # Update manifest
    with open("akvila.pkg") as f:
        content = f.read()
    dep_str = ", ".join(f'"{d}"' for d in deps)
    content = content.replace(
        f'dependencies = [{", ".join(f"{chr(34)}{d}{chr(34)}" for d in deps[:-1])}]',
        f'dependencies = [{dep_str}]'
    )
    # Simple approach: rewrite the dependencies line
    lines = content.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith("dependencies"):
            lines[i] = f'dependencies = [{dep_str}];'
    with open("akvila.pkg", "w") as f:
        f.write("\n".join(lines))
    print(f"Added dependency: {name}")


def cmd_list():
    """List dependencies."""
    manifest = load_manifest()
    deps = manifest.get("dependencies", [])
    if isinstance(deps, str):
        deps = [deps] if deps else []
    if not deps:
        print("No dependencies.")
    else:
        for dep in deps:
            status = "installed" if os.path.isdir(os.path.join(PKG_DIR, dep)) else "not installed"
            print(f"  {dep} ({status})")


def main():
    if len(sys.argv) < 2:
        print("Usage: akvila-pkg <command> [args]")
        print("Commands: init, build, add <name>, list")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "init":
        cmd_init()
    elif cmd == "build":
        cmd_build()
    elif cmd == "add" and len(sys.argv) >= 3:
        cmd_add(sys.argv[2])
    elif cmd == "list":
        cmd_list()
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
