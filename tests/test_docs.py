from __future__ import annotations

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DOCUMENTS = (
    PROJECT_ROOT / "README.md",
    PROJECT_ROOT / "tests" / "README.md",
    *sorted((PROJECT_ROOT / "examples").glob("*/README.md")),
)
COMMANDS = ("init", "validate", "generate", "run", "submit", "status", "reset")


def test_local_documentation_links_exist() -> None:
    missing: list[str] = []
    for document in DOCUMENTS:
        text = document.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^]]+\]\(([^)]+)\)", text):
            if "://" in target or target.startswith("#"):
                continue
            local_target = target.split("#", 1)[0]
            if local_target and not (document.parent / local_target).exists():
                missing.append(f"{document.relative_to(PROJECT_ROOT)} -> {target}")
    assert not missing, "Missing documentation links:\n" + "\n".join(missing)


def test_readme_documents_every_public_command() -> None:
    readme = (PROJECT_ROOT / "README.md").read_text(encoding="utf-8")
    for command in COMMANDS:
        assert f"step-by-sample {command}" in readme


def test_current_docs_do_not_describe_a_bash_first_interface() -> None:
    for document in DOCUMENTS:
        assert "Bash-first" not in document.read_text(encoding="utf-8")
