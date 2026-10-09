"""Compatibility entry: all game code and publishing now belong to Games."""
from pathlib import Path
import subprocess
import sys


def main() -> None:
    codes_root = Path(__file__).resolve().parents[3]
    entry = codes_root / 'games/scripts/deploy.ps1'
    if not entry.is_file():
        raise SystemExit('Clone https://github.com/caibinice/games into the sibling games directory first.')
    # Run the independent check/test/build/package chain, never blog source files.
    result = subprocess.run(['pwsh', '-NoLogo', '-NoProfile', '-File', str(entry), *sys.argv[1:]])
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
