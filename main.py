from __future__ import annotations

import sys
import traceback


def main() -> int:
    try:
        from novel_ime.tray_app import run_app
    except ModuleNotFoundError as exc:
        missing = exc.name or ""
        if missing.startswith("PySide6"):
            print(
                "启动失败：缺少 PySide6。请先执行 `python3 -m pip install -r /Users/mac/word/requirements.txt`。",
                file=sys.stderr,
            )
        else:
            print(f"启动失败：无法导入菜单栏应用入口。{exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"启动失败：无法导入菜单栏应用入口。{exc}", file=sys.stderr)
        return 1

    try:
        return run_app()
    except Exception:
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
