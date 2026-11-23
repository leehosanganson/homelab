#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["litellm[proxy]==1.110.2"]
# ///
"""Authenticate with ChatGPT and safely install LiteLLM's auth file in Kubernetes."""

from __future__ import annotations

import argparse
import contextlib
import json
import logging
import os
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, NoReturn

NAMESPACE = "llm"
POD_SELECTOR = "app=litellm"
CONTAINER = "litellm"
TOKEN_DIRECTORY = "/tokens/chatgpt"
TOKEN_FILE = f"{TOKEN_DIRECTORY}/auth.json"
MAX_AUTH_FILE_BYTES = 1024 * 1024

REMOTE_PREFLIGHT = r"""set -eu
folder=/tokens/chatgpt
file="$folder/auth.json"
test -d "$folder"
test -w "$folder"
test ! -e "$file"
test ! -L "$file"
probe=$(mktemp "$folder/.auth.json.preflight.XXXXXX")
trap 'rm -f -- "$probe"' 0 HUP INT TERM
rm -f -- "$probe"
trap - 0 HUP INT TERM
test ! -e "$file"
test ! -L "$file"
"""

REMOTE_INSTALL = r"""set -eu
folder=/tokens/chatgpt
file="$folder/auth.json"
umask 077
validate_auth() {
  python3 -c 'import json, os, sys
p = sys.argv[1]
if os.path.getsize(p) > 1048576:
    raise SystemExit(1)
with open(p, encoding="utf-8") as f:
    value = json.load(f)
required = ("access_token", "refresh_token", "id_token")
valid = isinstance(value, dict) and all(
    isinstance(value.get(key), str) and value[key] for key in required
)
if not valid:
    raise SystemExit(1)
' "$1"
}
tmp=$(mktemp "$folder/.auth.json.XXXXXX")
cleanup() { rm -f -- "$tmp"; }
trap cleanup 0 HUP INT TERM
chmod 600 "$tmp"
cat > "$tmp"
validate_auth "$tmp"
chmod 600 "$tmp"
# link(2) is atomic and fails if the destination already exists.
ln "$tmp" "$file"
validate_auth "$file"
"""


def fail(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Sign in with ChatGPT, then stream the resulting token file to the "
            "LiteLLM pod in namespace llm."
        )
    )
    parser.add_argument(
        "--context",
        help="Kubernetes context to use (default: the current context)",
    )
    return parser.parse_args()


def kubectl_args(context: str, *args: str) -> list[str]:
    return ["kubectl", "--context", context, *args]


def run_kubectl(context: str, *args: str) -> str:
    try:
        result = subprocess.run(
            kubectl_args(context, *args),
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        fail("Could not run kubectl; check that it is installed and available")
    if result.returncode != 0:
        fail("A Kubernetes check failed; no credentials were transferred")
    return result.stdout


def get_target_pod(context: str) -> str:
    pod_output = run_kubectl(
        context,
        "-n",
        NAMESPACE,
        "get",
        "pods",
        "-l",
        POD_SELECTOR,
        "-o",
        "json",
    )
    try:
        payload: Any = json.loads(pod_output)
        if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
            fail("kubectl returned an invalid pod list")
        pods = payload["items"]
        ready_pods = []
        for pod in pods:
            if not isinstance(pod, dict):
                fail("kubectl returned an invalid pod list")
            status = pod.get("status", {})
            if not isinstance(status, dict):
                fail("kubectl returned an invalid pod list")
            metadata = pod.get("metadata", {})
            conditions = status.get("conditions", [])
            container_statuses = status.get("containerStatuses", [])
            if (
                not isinstance(metadata, dict)
                or not isinstance(conditions, list)
                or not isinstance(container_statuses, list)
                or any(not isinstance(item, dict) for item in conditions + container_statuses)
            ):
                fail("kubectl returned an invalid pod list")
            pod_ready = any(
                condition.get("type") == "Ready" and condition.get("status") == "True"
                for condition in conditions
            )
            container_ready = any(
                item.get("name") == CONTAINER and item.get("ready") is True
                for item in container_statuses
            )
            if status.get("phase") == "Running" and pod_ready and container_ready:
                ready_pods.append(metadata["name"])
    except (AttributeError, KeyError, TypeError, ValueError):
        fail("kubectl returned an invalid pod list")

    if len(ready_pods) != 1:
        fail(
            f"Expected exactly one ready LiteLLM pod in namespace {NAMESPACE}; "
            f"found {len(ready_pods)}"
        )
    return ready_pods[0]


def verify_destination(context: str, pod: str) -> None:
    try:
        result = subprocess.run(
            kubectl_args(
                context,
                "-n",
                NAMESPACE,
                "exec",
                pod,
                "-c",
                CONTAINER,
                "--",
                "sh",
                "-c",
                REMOTE_PREFLIGHT,
            ),
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        fail("Could not run kubectl; check that it is installed and available")
    if result.returncode != 0:
        fail(
            f"{TOKEN_FILE} is not writable or already exists in pod {pod}; "
            "OAuth was not started and no credentials were transferred"
        )


def validate_local_auth_file(path: Path) -> None:
    try:
        metadata = path.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > MAX_AUTH_FILE_BYTES:
            fail("LiteLLM returned an invalid or oversized authentication file")
        os.chmod(path, 0o600)
        with path.open("r", encoding="utf-8") as auth_file:
            auth_data: Any = json.load(auth_file)
        if not isinstance(auth_data, dict) or any(
            not isinstance(auth_data.get(key), str) or not auth_data[key]
            for key in ("access_token", "refresh_token", "id_token")
        ):
            fail("LiteLLM returned an invalid authentication file")
    except (OSError, UnicodeError, json.JSONDecodeError):
        fail("Could not validate the temporary authentication file")


def authenticate(auth_file: Path) -> None:
    try:
        from litellm.llms.chatgpt.authenticator import Authenticator
    except Exception:
        fail("Could not load LiteLLM's ChatGPT authenticator")

    try:
        # The authenticator prints the required device-code instructions. Keep
        # those on the terminal's error stream, never on standard output.
        previous_logging_disable = logging.root.manager.disable
        logging.disable(logging.CRITICAL)
        try:
            with contextlib.redirect_stdout(sys.stderr):
                Authenticator(auth_file=str(auth_file)).get_access_token()
        finally:
            logging.disable(previous_logging_disable)
    except Exception:
        # Third-party exceptions can contain response bodies or token data.
        fail("ChatGPT authentication failed; details were suppressed to protect credentials")


def transfer_auth_file(context: str, pod: str, auth_file: Path) -> None:
    try:
        with auth_file.open("rb") as token_stream:
            result = subprocess.run(
                kubectl_args(
                    context,
                    "-n",
                    NAMESPACE,
                    "exec",
                    "-i",
                    pod,
                    "-c",
                    CONTAINER,
                    "--",
                    "sh",
                    "-c",
                    REMOTE_INSTALL,
                ),
                stdin=token_stream,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
    except OSError:
        fail("Could not stream credentials to the LiteLLM pod")
    if result.returncode != 0:
        fail(
            "Credential transfer failed. The destination was not overwritten; "
            "check the pod and mounted volume before trying again"
        )


def main() -> None:
    args = parse_args()
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        fail("Run this command in an interactive terminal so you can approve the transfer")
    if shutil.which("kubectl") is None:
        fail("kubectl is required")

    try:
        current_context = subprocess.run(
            ["kubectl", "config", "current-context"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        fail("Could not run kubectl; check that it is installed and available")

    if args.context is not None:
        context = args.context.strip()
        if not context:
            fail("--context must not be empty")
    elif current_context.returncode == 0 and current_context.stdout.strip():
        context = current_context.stdout.strip()
    else:
        fail("kubectl has no current context; pass --context to select one")

    print(f"Kubernetes context: {context}", file=sys.stderr)
    pod = get_target_pod(context)
    verify_destination(context, pod)
    print(f"Ready pod: {pod} (namespace {NAMESPACE}, container {CONTAINER})", file=sys.stderr)
    print(
        f"Destination: {TOKEN_FILE} (must be writable and absent)",
        file=sys.stderr,
    )
    try:
        answer = input(
            "This will sign in with ChatGPT and transfer credentials to this pod. "
            "Type 'transfer' to continue: "
        )
    except EOFError:
        fail("No confirmation received; no credentials were created or transferred")
    if answer != "transfer":
        print("Cancelled; no credentials were created or transferred.", file=sys.stderr)
        return

    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="litellm-chatgpt-auth-") as private_dir:
        os.chmod(private_dir, 0o700)
        auth_file = Path(private_dir) / "auth.json"
        authenticate(auth_file)
        validate_local_auth_file(auth_file)
        transfer_auth_file(context, pod, auth_file)

    print("Credentials were transferred. No credential values were displayed.", file=sys.stderr)
    restart_command = "kubectl " + shlex.join(
        ["--context", context, "-n", NAMESPACE, "rollout", "restart", "deployment/litellm"]
    )
    print(
        "Restart LiteLLM to load the newly provisioned credentials (not done automatically):\n"
        f"  {restart_command}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
