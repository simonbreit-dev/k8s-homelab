"""Local regressions: no real Terraform providers, SSH, or node mutations."""

import base64
from copy import deepcopy
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


def inventory():
    data = yaml.safe_load((ROOT / "tests/inventory.yml").read_text())
    data["all"]["vars"]["ansible_python_interpreter"] = sys.executable
    return data


def task(path, name):
    return next(
        item
        for item in yaml.safe_load((ROOT / path).read_text())
        if item["name"] == name
    )


class AnsibleTests(unittest.TestCase):
    def run_tasks(
        self, tasks, variables=None, arguments=(), data=None, expected_success=True
    ):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            hosts = path / "inventory.yml"
            hosts.write_text(yaml.safe_dump(data or inventory()))
            marker = path / "mutation-marker"
            playbook = path / "playbook.yml"
            playbook.write_text(
                yaml.safe_dump(
                    [
                        {
                            "name": "Local regression",
                            "hosts": "k8s_nodes",
                            "gather_facts": False,
                            "vars": variables or {},
                            "tasks": deepcopy(tasks)
                            + [
                                {
                                    "name": "Record that guarded tasks completed",
                                    "ansible.builtin.copy": {
                                        "content": "passed",
                                        "dest": str(marker),
                                        "mode": "0600",
                                    },
                                }
                            ],
                        }
                    ],
                    sort_keys=False,
                )
            )
            command = [
                str(ROOT / "ansible/.venv/bin/ansible-playbook"),
                "-i",
                str(hosts),
                str(playbook),
            ]
            result = subprocess.run(
                command + list(arguments),
                cwd=ROOT / "ansible",
                capture_output=True,
                text=True,
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode == 0, expected_success, output)
            self.assertEqual(marker.exists(), expected_success, output)
            self.assertNotIn("[DEPRECATION WARNING]", output)
            return output

    def test_scope_preflight(self):
        scope = task("ansible/tasks/preflight.yml", "Verify supported bootstrap scope")
        for arguments, success in [
            ((), True),
            (("--limit", "test-cp"), False),
            (("--limit", "test-worker"), False),
            (("--check",), False),
        ]:
            with self.subTest(arguments=arguments):
                self.run_tasks([scope], arguments=arguments, expected_success=success)
        bad_topology = inventory()
        bad_topology["all"]["children"]["k8s_nodes"]["children"]["control_plane"][
            "hosts"
        ]["second-cp"] = {}
        self.run_tasks([scope], data=bad_topology, expected_success=False)

    def test_connection_wait_passes_locally_and_stops_on_timeout(self):
        wait = task(
            "ansible/tasks/wait-for-cloud-init.yml",
            "Wait for nodes to become reachable over Tailscale",
        )
        variables = {"bootstrap_connection_timeout": 1}
        self.run_tasks([wait], variables)
        data = inventory()
        data["all"]["vars"][
            "ansible_python_interpreter"
        ] = "/nonexistent-bootstrap-test-python"
        self.run_tasks([wait], variables, data=data, expected_success=False)

    def test_cloud_init_wait_is_bounded_and_failure_stops_configuration(self):
        wait = task(
            "ansible/tasks/wait-for-cloud-init.yml", "Wait for successful cloud-init completion"
        )
        wait["register"] = "cloud_init_result"
        check = {
            "name": "Verify waiting reports no mutation",
            "ansible.builtin.assert": {"that": ["not cloud_init_result.changed"]},
        }
        with tempfile.TemporaryDirectory() as directory:
            timeout = Path(directory) / "timeout"
            timeout.write_text(
                f"#!{sys.executable}\n" + "import os, sys\n"
                'assert sys.argv[1:] == ["--kill-after=5s", "1s", "cloud-init", "status", "--wait", "--long"]\n'
                'print("status: error\\nerrors: simulated cloud-init failure" if os.environ["CLOUD_INIT_TEST_RC"] != "0" else "status: done")\n'
                'sys.exit(int(os.environ["CLOUD_INIT_TEST_RC"]))\n'
            )
            timeout.chmod(0o755)
            for return_code in [0, 1, 2, 124]:
                with self.subTest(return_code=return_code):
                    wait["environment"] = {
                        "PATH": directory,
                        "CLOUD_INIT_TEST_RC": str(return_code),
                    }
                    output = self.run_tasks(
                        [wait, check],
                        {"bootstrap_cloud_init_timeout": 1},
                        expected_success=return_code == 0,
                    )
                    if return_code != 0:
                        self.assertIn("simulated cloud-init failure", output)

    def test_package_mismatch_is_rejected(self):
        guard = task(
            "ansible/tasks/preflight.yml",
            "Reject implicit bootstrap package upgrades or downgrades",
        )
        variables = yaml.safe_load(
            (ROOT / "ansible/inventory/group_vars/all.yml").read_text()
        )
        variables.update(
            tailscale_package_version="1.102.4", bootstrap_installed_packages={}
        )
        self.run_tasks([guard], variables)
        variables["bootstrap_installed_packages"] = {"kubeadm": "1.33.0-1.1"}
        self.run_tasks([guard], variables, expected_success=False)

    def test_unsupported_os_and_missing_private_ip_are_rejected(self):
        guard = task(
            "ansible/tasks/preflight.yml",
            "Verify supported node environment and inventory",
        )
        ip_guard = task(
            "ansible/tasks/preflight.yml", "Verify assigned private node IP"
        )
        facts = {
            "distribution": "Ubuntu",
            "distribution_version": "24.04",
            "architecture": "x86_64",
            "all_ipv4_addresses": ["10.0.1.11", "10.0.1.12"],
        }
        self.run_tasks([guard, ip_guard], {"ansible_facts": facts})
        facts["distribution"] = "Debian"
        self.run_tasks(
            [guard, ip_guard], {"ansible_facts": facts}, expected_success=False
        )
        facts["distribution"] = "Ubuntu"
        facts["all_ipv4_addresses"] = []
        output = self.run_tasks(
            [guard, ip_guard], {"ansible_facts": facts}, expected_success=False
        )
        self.assertIn("Check the Hetzner network", output)

    def test_missing_controller_tools_are_rejected(self):
        guard = task("ansible/tasks/preflight.yml", "Verify local controller tools")
        with tempfile.TemporaryDirectory() as directory:
            guard["environment"] = {"PATH": directory}
            self.run_tasks([guard], expected_success=False)

    def test_forwarding_repair_reports_only_real_changes(self):
        repair = task(
            "ansible/roles/kubernetes/tasks/main.yml", "Repair IPv4 forwarding drift"
        )
        # Keep the real condition/change reporting; replace only the system mutation.
        repair["ansible.builtin.command"] = {"argv": [sys.executable, "-c", "pass"]}
        repair["register"] = "repair_result"
        check = {
            "name": "Check forwarding change report",
            "ansible.builtin.assert": {
                "that": ["repair_result.changed == expected_change"]
            },
        }
        for state, changed in [("0", True), ("1", False)]:
            self.run_tasks(
                [repair, check],
                {
                    "kubernetes_ipv4_forwarding": {"stdout": state},
                    "expected_change": changed,
                },
            )

    def test_partial_bootstrap_is_rejected(self):
        guard = task(
            "ansible/roles/control_plane/tasks/main.yml",
            "Reject incomplete control-plane initialization",
        )
        variables = {
            "control_plane_admin_conf": {"stat": {"exists": False}},
            "control_plane_bootstrap_artifacts": {
                "results": [{"stat": {"exists": True}}]
            },
        }
        self.run_tasks([guard], variables, expected_success=False)

    def test_retained_worker_ca_mismatch_is_rejected(self):
        decode = task(
            "ansible/roles/worker/tasks/main.yml", "Decode existing worker kubeconfig"
        )
        read_ca = task(
            "ansible/roles/worker/tasks/main.yml",
            "Read existing worker certificate authority",
        )
        guard = task(
            "ansible/roles/worker/tasks/main.yml",
            "Verify worker trusts the current cluster identity",
        )
        data = inventory()
        data["all"]["children"]["k8s_nodes"]["children"]["control_plane"]["hosts"][
            "test-cp"
        ]["control_plane_ca_data"] = "current-ca"
        variables = {
            "worker_kubelet_conf": {"stat": {"exists": True}},
        }
        config = {
            "current-context": "default-context",
            "contexts": [
                {"name": "default-context", "context": {"cluster": "default-cluster"}}
            ],
            "clusters": [
                {
                    "name": "kubernetes",
                    "cluster": {"certificate-authority-data": "unrelated-ca"},
                },
                {
                    "name": "default-cluster",
                    "cluster": {"certificate-authority-data": "old-ca"},
                },
            ],
        }
        for ca, expected in [("old-ca", False), ("current-ca", True), ("", False)]:
            with self.subTest(ca=ca):
                config["clusters"][1]["cluster"]["certificate-authority-data"] = ca
                variables["worker_existing_config"] = {
                    "content": base64.b64encode(yaml.safe_dump(config).encode()).decode()
                }
                self.run_tasks(
                    [decode, read_ca, guard], variables, data=data,
                    expected_success=expected,
                )

    def test_kubeconfig_write_is_idempotent_and_preserves_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "config"
            original = {
                "apiVersion": "v1",
                "kind": "Config",
                "current-context": "admin",
                "clusters": [
                    {
                        "name": "kubernetes",
                        "cluster": {
                            "server": "https://10.0.1.11:6443",
                            "certificate-authority-data": "dummy-ca",
                        },
                    },
                    {"name": "other", "cluster": {"server": "https://other.example"}},
                ],
                "users": [{"name": "admin", "user": {"client-key-data": "dummy-key"}}],
                "contexts": [
                    {
                        "name": "admin",
                        "context": {"cluster": "kubernetes", "user": "admin"},
                    }
                ],
            }
            write = task(
                "ansible/roles/control_plane/tasks/main.yml",
                "Write local kubeconfig with the Tailscale API endpoint",
            )
            write["ansible.builtin.template"]["src"] = str(
                ROOT / "ansible/roles/control_plane/templates/kubeconfig.yml.j2"
            )
            write["run_once"] = True
            write["register"] = "first_write"
            again = deepcopy(write)
            again["register"] = "second_write"
            self.run_tasks(
                [
                    write,
                    again,
                    {
                        "name": "Check change reporting",
                        "ansible.builtin.assert": {
                            "that": ["first_write.changed", "not second_write.changed"]
                        },
                        "run_once": True,
                    },
                ],
                {
                    "control_plane_source_config": original,
                    "kubeconfig_local_path": str(destination),
                },
            )
            expected = deepcopy(original)
            expected["clusters"][0]["cluster"]["server"] = "https://test-cp:6443"
            self.assertEqual(yaml.safe_load(destination.read_text()), expected)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
