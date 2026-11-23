"""Behavior tests for the LiteLLM ChatGPT auth helper."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import shlex
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).with_name("litellm-chatgpt-auth.py")
SPEC = importlib.util.spec_from_file_location("litellm_chatgpt_auth", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Could not load {SCRIPT}")
auth_helper = importlib.util.module_from_spec(SPEC)
previous_bytecode_setting = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    SPEC.loader.exec_module(auth_helper)
finally:
    sys.dont_write_bytecode = previous_bytecode_setting

VALID_AUTH = {
    "access_token": "unit-test-access-token",
    "refresh_token": "unit-test-refresh-token",
    "id_token": "unit-test-id-token",
}


def pod(
    name: str,
    *,
    pod_ready: bool,
    container_ready: bool,
    phase: str = "Running",
) -> dict[str, object]:
    return {
        "metadata": {"name": name},
        "status": {
            "phase": phase,
            "conditions": [{"type": "Ready", "status": "True" if pod_ready else "False"}],
            "containerStatuses": [{"name": "litellm", "ready": container_ready}],
        },
    }


class TTYStream(io.StringIO):
    def isatty(self) -> bool:
        return True


class MainFlowTests(unittest.TestCase):
    def run_main(self, answer: str = "transfer") -> tuple[TTYStream, TTYStream]:
        stdout = TTYStream()
        stderr = TTYStream()
        current_context = subprocess.CompletedProcess(
            args=["kubectl", "config", "current-context"],
            returncode=0,
            stdout="test-context\n",
            stderr="",
        )
        with (
            mock.patch.object(auth_helper, "parse_args", return_value=mock.Mock(context=None)),
            mock.patch.object(auth_helper.shutil, "which", return_value="/usr/bin/kubectl"),
            mock.patch.object(auth_helper.subprocess, "run", return_value=current_context),
            mock.patch.object(auth_helper, "get_target_pod", return_value="test-pod"),
            mock.patch.object(auth_helper.sys, "stdin", TTYStream()),
            mock.patch.object(auth_helper.sys, "stdout", stdout),
            mock.patch.object(auth_helper.sys, "stderr", stderr),
            mock.patch("builtins.input", return_value=answer),
        ):
            auth_helper.main()
        return stdout, stderr

    def test_destination_preflight_failure_stops_before_authentication_and_transfer(self):
        with (
            mock.patch.object(auth_helper, "verify_destination", side_effect=SystemExit(1)) as preflight,
            mock.patch.object(auth_helper, "authenticate") as authenticate,
            mock.patch.object(auth_helper, "transfer_auth_file") as transfer,
        ):
            with self.assertRaises(SystemExit):
                self.run_main()

        preflight.assert_called_once_with("test-context", "test-pod")
        authenticate.assert_not_called()
        transfer.assert_not_called()

    def test_declining_confirmation_stops_before_authentication_and_transfer(self):
        with (
            mock.patch.object(auth_helper, "verify_destination") as preflight,
            mock.patch.object(auth_helper, "authenticate") as authenticate,
            mock.patch.object(auth_helper, "transfer_auth_file") as transfer,
        ):
            self.run_main(answer="no")

        preflight.assert_called_once_with("test-context", "test-pod")
        authenticate.assert_not_called()
        transfer.assert_not_called()

    def test_confirmed_path_authenticates_and_transfers_once_without_printing_credentials(self):
        def create_local_credentials(auth_file: Path) -> None:
            auth_file.write_text(json.dumps(VALID_AUTH), encoding="utf-8")

        with (
            mock.patch.object(auth_helper, "verify_destination") as preflight,
            mock.patch.object(
                auth_helper, "authenticate", side_effect=create_local_credentials
            ) as authenticate,
            mock.patch.object(auth_helper, "transfer_auth_file") as transfer,
        ):
            stdout, stderr = self.run_main()

        preflight.assert_called_once_with("test-context", "test-pod")
        authenticate.assert_called_once()
        transfer.assert_called_once_with(
            "test-context", "test-pod", authenticate.call_args.args[0]
        )
        output = stdout.getvalue() + stderr.getvalue()
        for credential in VALID_AUTH.values():
            self.assertNotIn(credential, output)


class TargetPodTests(unittest.TestCase):
    def test_returns_the_only_running_pod_ready_at_pod_and_container_level(self):
        payload = {
            "items": [
                pod("pod-not-ready", pod_ready=False, container_ready=True),
                pod("container-not-ready", pod_ready=True, container_ready=False),
                pod("not-running", pod_ready=True, container_ready=True, phase="Pending"),
                pod("ready-litellm", pod_ready=True, container_ready=True),
            ]
        }
        with mock.patch.object(auth_helper, "run_kubectl", return_value=json.dumps(payload)):
            self.assertEqual(auth_helper.get_target_pod("test-context"), "ready-litellm")

    def test_rejects_zero_or_multiple_ready_pods(self):
        cases = {
            "none ready": [
                pod("pod-not-ready", pod_ready=False, container_ready=True),
                pod("container-not-ready", pod_ready=True, container_ready=False),
                pod("not-running", pod_ready=True, container_ready=True, phase="Pending"),
            ],
            "multiple ready": [
                pod("ready-litellm-1", pod_ready=True, container_ready=True),
                pod("ready-litellm-2", pod_ready=True, container_ready=True),
            ],
        }
        for name, pods in cases.items():
            with self.subTest(name=name):
                with mock.patch.object(
                    auth_helper, "run_kubectl", return_value=json.dumps({"items": pods})
                ):
                    with contextlib.redirect_stderr(io.StringIO()):
                        with self.assertRaises(SystemExit):
                            auth_helper.get_target_pod("test-context")


class LocalAuthFileTests(unittest.TestCase):
    def test_accepts_valid_credentials_and_restricts_file_permissions(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            auth_file = Path(temporary_directory) / "auth.json"
            auth_file.write_text(json.dumps(VALID_AUTH), encoding="utf-8")
            os.chmod(auth_file, 0o644)

            auth_helper.validate_local_auth_file(auth_file)

            self.assertEqual(stat.S_IMODE(auth_file.stat().st_mode), 0o600)

    def test_rejects_invalid_json(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            auth_file = Path(temporary_directory) / "auth.json"
            auth_file.write_text('{"access_token":', encoding="utf-8")

            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    auth_helper.validate_local_auth_file(auth_file)

    def test_rejects_non_regular_paths(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            target = directory / "credential-target.json"
            target.write_text(json.dumps(VALID_AUTH), encoding="utf-8")
            symlink = directory / "auth.json"
            symlink.symlink_to(target)

            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    auth_helper.validate_local_auth_file(directory)
                with self.assertRaises(SystemExit):
                    auth_helper.validate_local_auth_file(symlink)

    def test_rejects_json_without_all_required_credentials(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            auth_file = Path(temporary_directory) / "auth.json"
            auth_file.write_text(json.dumps({"access_token": "test-only"}), encoding="utf-8")

            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    auth_helper.validate_local_auth_file(auth_file)


class RemoteInstallTests(unittest.TestCase):
    def run_remote_install(self, directory: Path, content: str) -> subprocess.CompletedProcess[str]:
        script = auth_helper.REMOTE_INSTALL.replace(
            "folder=/tokens/chatgpt", f"folder={shlex.quote(str(directory))}"
        )
        return subprocess.run(
            ["/bin/sh", "-c", script],
            input=content,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_installs_valid_json_with_mode_0600_and_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            token_directory = Path(temporary_directory)
            auth_file = token_directory / "auth.json"
            original = json.dumps(VALID_AUTH)

            first_install = self.run_remote_install(token_directory, original)

            self.assertEqual(first_install.returncode, 0, first_install.stderr)
            self.assertEqual(auth_file.read_text(encoding="utf-8"), original)
            self.assertEqual(stat.S_IMODE(auth_file.stat().st_mode), 0o600)

            replacement = json.dumps({**VALID_AUTH, "access_token": "replacement-test-token"})
            second_install = self.run_remote_install(token_directory, replacement)

            self.assertNotEqual(second_install.returncode, 0)
            self.assertEqual(auth_file.read_text(encoding="utf-8"), original)

    def test_rejects_invalid_json_without_installing_a_destination(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            token_directory = Path(temporary_directory)

            result = self.run_remote_install(token_directory, '{"access_token":')

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((token_directory / "auth.json").exists())


if __name__ == "__main__":
    unittest.main()
