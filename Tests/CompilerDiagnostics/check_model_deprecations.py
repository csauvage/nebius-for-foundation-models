#!/usr/bin/env python3
"""Verify Swift migration errors for removed models and string-selection warnings."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[2]
subprocess.run(
    ["swift", "build", "--target", "NebiusForFoundationModels"], cwd=root, check=True
)
build_path = subprocess.check_output(
    ["swift", "build", "--show-bin-path"], cwd=root, text=True
).strip()
removed_aliases = {
    "deepSeekV4Pro": "deepSeekV4Pro0813",
    "deepSeekV4Flash0731": "deepSeekV41Flash1017",
    "deepSeekV41Flash": "deepSeekV41Flash1017",
    "qwen3235BInstruct2507": "qwen330BInstruct2507",
    "qwen35Large": "qwen3827B",
    "kimiK26": "kimiK3",
    "kimiK27Code": "kimiK3",
    "nemotron3Nano30B": "nemotron35Lightning",
    "nemotron3Super120B": "nemotron35SuperVL",
    "miniCPMV45": "nemotron35SuperVL",
    "glm51": "glm53",
}
removed_source = "import NebiusForFoundationModels\n"
removed_source += "\n".join(f"let _ = NebiusModel.{name}" for name in removed_aliases)
supported_source = "import NebiusForFoundationModels\n"
supported_source += "\n".join(
    f"let _ = NebiusModel.{name}" for name in sorted(set(removed_aliases.values()))
)
supported_source += '''
let _ = NebiusModel.kimiK31Pro
let _ = NebiusModelCatalog.model(id: "moonshotai/Kimi-K3.1-Pro")?.languageModel
let _ = NebiusModel.custom(id: "private/model", capabilities: [.vision])
let _ = NebiusModel.custom(id: "private/model", fastVariantID: "private/fast", capabilities: .fullText)
'''
legacy_source = '''import NebiusForFoundationModels
let _ = NebiusModel(id: "moonshotai/Kimi-K3.1-Pro")
let _ = NebiusModel(id: "private/model", fastVariantID: "private/fast", capabilities: [.vision])
'''

def typecheck(source):
    with tempfile.TemporaryDirectory(prefix="nebius-model-check-") as directory:
        fixture = Path(directory) / "Client.swift"
        fixture.write_text(source)
        return subprocess.run(
            [
                "swiftc", "-typecheck",
                "-I", str(Path(build_path) / "Modules"),  # Native SwiftPM layout.
                "-I", build_path,  # Swift Build / Xcode layout.
                str(fixture),
            ],
            cwd=root,
            capture_output=True,
            text=True,
        )


removed = typecheck(removed_source)
assert removed.returncode != 0, "Removed model constants must not compile"
errors = [line for line in removed.stderr.splitlines() if ": error:" in line]
assert len(errors) == len(removed_aliases), removed.stderr
for alias, replacement in removed_aliases.items():
    assert any(
        f"'{alias}'" in error and replacement in error
        and "2026-11-09 Serverless shutdown" in error
        for error in errors
    ), removed.stderr

supported = typecheck(supported_source)
assert supported.returncode == 0, supported.stdout + supported.stderr
assert ": warning:" not in supported.stderr, supported.stderr

legacy = typecheck(legacy_source)
assert legacy.returncode == 0, legacy.stdout + legacy.stderr
warnings = [line for line in legacy.stderr.splitlines() if ": warning:" in line]
assert len(warnings) == 2, legacy.stderr
selection_warnings = [warning for warning in warnings if "Prefer typed model constants" in warning]
assert len(selection_warnings) == 2, legacy.stderr
assert all("NebiusModel.custom" in warning for warning in selection_warnings), legacy.stderr

print("Verified 11 removal errors with replacement names and two string-initializer warnings; replacements, catalog selection and explicit custom models compile without warnings.")
