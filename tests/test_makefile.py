"""Exercise Makefile orchestration with fake tools; never touch infrastructure."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MakefileTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name).resolve()
        shutil.copy2(ROOT / "Makefile", self.root / "Makefile")
        (self.root / "terraform").mkdir()
        binaries = self.root / "ansible/.venv/bin"
        binaries.mkdir(parents=True)
        tools = self.root / "fake-tools"
        tools.mkdir()
        self.log = self.root / "commands.jsonl"
        stub = f"#!{sys.executable}\n" + """
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "terraform":
    stage = "terraform-" + args[1]
elif name == "python3":
    stage = "venv"
elif name == "python":
    stage = "pip" if args[:2] == ["-m", "pip"] else "tests"
elif name == "ansible-galaxy":
    stage = "collections"
else:
    stage = "syntax" if "--syntax-check" in args else "configure"
with open(os.environ["MAKEFILE_TEST_LOG"], "a") as stream:
    stream.write(json.dumps({"stage": stage, "args": args,
                            "cwd": os.getcwd(),
                            "path": os.environ["PATH"]}) + "\\n")
sys.exit(1 if os.environ.get("MAKEFILE_TEST_FAIL") == stage else 0)
"""
        for path in [
            tools / "terraform",
            tools / "python3",
            binaries / "python",
            binaries / "ansible-playbook",
            binaries / "ansible-galaxy",
        ]:
            path.write_text(stub)
            path.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=str(tools) + os.pathsep + os.environ["PATH"],
            MAKEFILE_TEST_LOG=str(self.log),
        )
        for name in ["VIRTUAL_ENV", "MAKEFLAGS", "MFLAGS", "MAKEFILE_TEST_FAIL"]:
            self.env.pop(name, None)

    def run_make(self, *arguments, fail=None):
        self.log.unlink(missing_ok=True)
        env = dict(self.env)
        if fail:
            env["MAKEFILE_TEST_FAIL"] = fail
        result = subprocess.run(
            ["make", *arguments],
            cwd=self.root,
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        entries = (
            [json.loads(line) for line in self.log.read_text().splitlines()]
            if self.log.exists()
            else []
        )
        return result, entries

    def test_default_help_and_dry_run_have_no_side_effects(self):
        for arguments in [(), ("-n", "deploy")]:
            result, entries = self.run_make(*arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(entries, [])
            self.assertIn(
                "-chdir=terraform apply" if arguments else "deploy", result.stdout
            )

    def test_deployment_is_sequential_even_with_parallel_make(self):
        result, entries = self.run_make("-j8", "deploy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [entry["stage"] for entry in entries],
            ["terraform-init", "terraform-apply", "configure"],
        )
        self.assertEqual(entries[-1]["cwd"], str(self.root / "ansible"))
        self.assertEqual(entries[-1]["args"], ["playbooks/site.yml"])
        self.assertEqual(entries[1]["args"], ["-chdir=terraform", "apply"])

    def test_deployment_stops_at_each_failed_stage(self):
        stages = ["terraform-init", "terraform-apply", "configure"]
        for index, stage in enumerate(stages):
            with self.subTest(stage=stage):
                result, entries = self.run_make("deploy", fail=stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(
                    [entry["stage"] for entry in entries], stages[: index + 1]
                )

    def test_missing_controller_stops_before_infrastructure(self):
        shutil.rmtree(self.root / "ansible/.venv")
        for target in ["deploy", "destroy"]:
            result, entries = self.run_make(target)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(entries, [])
            self.assertIn("make setup", result.stderr)

    def test_configure_uses_existing_inventory_without_terraform(self):
        result, entries = self.run_make("configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [entry["stage"] for entry in entries],
            ["configure"],
        )

    def test_plan_and_destroy_preserve_prompts(self):
        for target in ["plan", "destroy"]:
            with self.subTest(target=target):
                result, entries = self.run_make(target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    [entry["stage"] for entry in entries],
                    ["terraform-init", "terraform-" + target],
                )
                self.assertEqual(entries[-1]["args"], ["-chdir=terraform", target])
                if target == "destroy":
                    self.assertEqual(entries[-1]["path"].split(os.pathsep)[0], str(self.root / "ansible/.venv/bin"))

    def test_setup_installs_only_local_controller_dependencies(self):
        config = self.root / "terraform/config.auto.tfvars"
        config.write_text("existing configuration")
        result, entries = self.run_make("setup")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [entry["stage"] for entry in entries], ["venv", "pip", "collections"]
        )
        self.assertEqual(config.read_text(), "existing configuration")

    def test_check_uses_backend_disabled_init_and_mock_commands(self):
        result, entries = self.run_make("check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            [entry["stage"] for entry in entries],
            [
                "terraform-init",
                "terraform-fmt",
                "terraform-validate",
                "terraform-test",
                "syntax",
                "tests",
            ],
        )
        self.assertIn("-backend=false", entries[0]["args"])
        self.assertIn("-lockfile=readonly", entries[0]["args"])
        self.assertEqual(entries[3]["path"].split(os.pathsep)[0], str(self.root / "tests/bin"))
        self.assertEqual(entries[4]["cwd"], str(self.root / "ansible"))
        self.assertIn("../tests/inventory.yml", entries[4]["args"])


if __name__ == "__main__":
    unittest.main()
