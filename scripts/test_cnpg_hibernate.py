"""Offline behavior tests for the bulk CloudNativePG hibernation helper."""

import json
import os
import pty
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("cnpg-hibernate.sh")
RESOURCE = "clusters.postgresql.cnpg.io"

KUBECTL = r'''
import json
import sys
import time
from pathlib import Path

args = sys.argv[1:]
with open("calls", "a") as log:
    log.write(json.dumps(args) + "\n")
settings = json.loads(Path("settings").read_text())
targets = {(ns, name): state for ns, name, state in settings["targets"]}

if args == ["config", "current-context"]:
    print("mock-context")
    sys.exit()
if args == ["cnpg", "version"]:
    if settings.get("no_plugin"):
        sys.exit(1)
    version = settings.get("plugin_version", "1.28.4")
    print(f"Build: {{Version:{version} Commit:none Date:unknown}}")
    sys.exit()
if args[:2] == ["cnpg", "hibernate"] and args[-1] == "--help":
    print(f"  kubectl cnpg hibernate {args[2]} CLUSTER [flags]")
    sys.exit()

assert "--context=mock-context" in args, args
args = [a for a in args if not a.startswith(("--context=", "--request-timeout="))]

def emit(value):
    print(json.dumps(value))
    sys.exit()

def state_for(ns, name):
    marker = Path(f"{ns}-{name}.state")
    return marker.read_text() if marker.exists() else targets[ns, name]

def cluster(ns, name):
    state = state_for(ns, name)
    complete = name not in settings.get("pending", [])
    conditions = []
    if state == "on" and name in settings.get("waiting_for_healthy", []):
        conditions.append({"type": "cnpg.io/hibernation", "status": "False", "reason": "WaitingForHealthy"})
    elif name in settings.get("deleting_pods", []):
        conditions.append({"type": "cnpg.io/hibernation", "status": "False", "reason": "DeletingPods"})
    elif (state == "on" and complete) or name in settings.get("stale_condition", []):
        conditions.append({"type": "cnpg.io/hibernation", "status": "True", "reason": "Hibernated"})
    return {
        "metadata": {"namespace": ns, "name": name, "uid": f"{ns}-{name}",
                     "annotations": {"cnpg.io/hibernation": state} if state else {}},
        "spec": {"instances": 2},
        "status": {
            "phase": "Cluster in healthy state" if state != "on" and name not in settings.get("unhealthy", [])
            else "Not healthy",
            "readyInstances": 2 if state != "on" and complete and name not in settings.get("short_ready", []) else 1,
            "conditions": conditions,
        },
    }

if args == ["get", "deployment", "cnpg-controller-manager", "-n", "cnpg-system", "-o", "json"]:
    emit({"metadata": {"generation": 1}, "spec": {"replicas": 1, "template": {"spec": {"containers": [{
        "name": "manager", "image": "ghcr.io/cloudnative-pg/cloudnative-pg:"
        + settings.get("operator_version", "1.28.4") + "@sha256:abcd",
        "env": settings.get("operator_env", []), "envFrom": settings.get("operator_env_from", []),
    }]}}}, "status": {"observedGeneration": 1, "replicas": 1, "updatedReplicas": 1,
                      "availableReplicas": 0 if settings.get("unready") else 1}})
if args == ["get", "clusters.postgresql.cnpg.io", "-A", "-o", "json"]:
    emit({"items": [cluster(ns, name) for ns, name in targets]})
if args[:2] == ["cnpg", "hibernate"]:
    _, _, action, name, flag, ns = args
    assert flag == "-n" and action in ("on", "off"), args
    if action == (state_for(ns, name) or "off"):
        print(f"already {action}", file=sys.stderr)
        sys.exit(1)
    if action == "on" and name in settings.get("delayed_on", []):
        Path(f"{ns}-{name}.pending-on").touch()
        sys.exit(1)
    if name in settings.get("fail", []) or action == "off" and name in settings.get("fail_off", []):
        if name in settings.get("unreadable_after_error", []):
            Path(f"{ns}-{name}.unreadable").touch()
        sys.exit(1)
    Path(f"{ns}-{name}.state").write_text(action)
    sys.exit(action == "on" and name in settings.get("fail_after_on", []))

assert args[0] == "get" and args[-2:] == ["-o", "json"], args
kind = args[1]
if kind == "clusters.postgresql.cnpg.io":
    _, _, name, flag, ns, _, _ = args
    assert flag == "-n", args
    if Path(f"{ns}-{name}.unreadable").exists():
        sys.exit(1)
    emit(cluster(ns, name))

_, _, flag, ns, label_flag, selector, _, _ = args
assert flag == "-n" and label_flag == "-l", args
label, name = selector.split(",")[0].split("=")
assert label == "cnpg.io/cluster", args
state = state_for(ns, name)
if kind == "pods":
    assert "cnpg.io/podRole=instance" in selector, args
    if state == "on":
        emit({"items": [{}] if name in settings.get("lingering", []) else []})
    mode = settings.get("pod_modes", {}).get(name)
    if mode == "blocked":
        time.sleep(30)
    pod = {"metadata": {"deletionTimestamp": "now"} if mode == "terminating" else {},
           "status": {"conditions": [{"type": "Ready", "status": "False" if mode == "unready" else "True"}]}}
    # Apply the pending write after sampling ready pods, but before returning that sample.
    delayed = Path(f"{ns}-{name}.pending-on")
    if delayed.exists() and sum(
        "pods" in call and selector in call and ns in call
        for call in map(json.loads, Path("calls").read_text().splitlines())
    ) == settings.get("delayed_on_after_samples", 1):
        delayed.unlink()
        Path(f"{ns}-{name}.state").write_text("on")
    emit({"items": [] if mode == "absent" else [pod] * (3 if mode == "extra" else 2)})
assert kind == "pvc", args
if state == "on" and name in settings.get("blocked_pvcs", []):
    time.sleep(30)
uid = f"{ns}-{name}-pvc"
if name in settings.get("replaced", []) and state == "on":
    uid = "replacement"
emit({"items": [{"metadata": {"name": f"{name}-1", "uid": uid},
                 "spec": {"volumeName": f"{ns}-{name}-pv"}, "status": {"phase": "Bound"}}]})
'''


class HibernationTests(unittest.TestCase):
    def run_helper(self, *args, answer="yes", tty=True, targets=(), broken_sleep=False, **settings):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "settings").write_text(json.dumps(dict(settings, targets=targets)))
            (root / "calls").touch()
            (root / "kubeconfig").touch()
            stub = root / "kubectl"
            stub.write_text(f"#!{sys.executable}\n{KUBECTL}")
            stub.chmod(0o755)
            if broken_sleep:
                sleep = root / "sleep"
                sleep.write_text("#!/bin/sh\nexit 1\n")
                sleep.chmod(0o755)
            jq = shutil.which("jq")
            self.assertIsNotNone(jq, "tests need jq to evaluate the production filters")
            jq_stub = root / "jq"
            jq_stub.write_text(f'#!/bin/sh\nprintf \'["jq"]\\n\' >> calls\nexec {shlex.quote(jq)} "$@"\n')
            jq_stub.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       KUBECONFIG=str(root / "kubeconfig"), CNPG_HIBERNATE_TIMEOUT_SECONDS="1")
            command = ["bash", str(SCRIPT), *args]
            options = dict(cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=10)
            if tty:
                master, slave = pty.openpty()
                try:
                    os.write(master, f"{answer}\n".encode())
                    result = subprocess.run(command, stdin=slave, **options)
                finally:
                    os.close(master)
                    os.close(slave)
            else:
                result = subprocess.run(command, input=f"{answer}\n", **options)
            calls = [json.loads(line) for line in (root / "calls").read_text().splitlines()]
            self.assertNotIn("Traceback", result.stdout)
            return result.returncode, result.stdout, calls

    def mutations(self, calls):
        return [[a for a in call[2:] if not a.startswith("--")] for call in calls
                if call[:2] == ["cnpg", "hibernate"] and call[-1] != "--help"]

    def test_invalid_args_do_not_call_dependencies(self):
        for args in [(), ("pause",), ("on", "--yes")]:
            with self.subTest(args=args):
                status, out, calls = self.run_helper(*args)
                self.assertNotEqual(status, 0)
                self.assertIn("Usage:", out)
                self.assertEqual(calls, [])

    def test_help_without_terminal_or_dependency_calls(self):
        status, out, calls = self.run_helper("--help", tty=False)
        self.assertEqual(status, 0, out)
        self.assertIn("Usage:", out)
        self.assertIn("previously hibernated", out)
        self.assertIn("CNPG_HIBERNATE_TIMEOUT_SECONDS", out)
        self.assertIn(
            "Warning: CNPG plugin mutations target namespace/name and are not atomic with "
            "the preceding UID check. Do not delete and recreate a cluster during this operation.",
            " ".join(out.split()),
        )
        self.assertEqual(calls, [])

    def test_requires_terminal_and_consent(self):
        for tty, answer, message in [(False, "yes", "terminal"), (True, "no", "Cancelled")]:
            with self.subTest(tty=tty):
                status, out, calls = self.run_helper("on", tty=tty, answer=answer,
                                                     targets=[("alpha", "db", "")])
                self.assertNotEqual(status, 0)
                self.assertIn(message, out)
                self.assertEqual(self.mutations(calls), [])

    def test_on_discovers_namespaces_and_verifies_skips(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", ""), ("beta", "db", "on")])
        self.assertEqual(status, 0, out)
        self.assertEqual(sum(call[2:5] == ["get", RESOURCE, "-A"] for call in calls), 1)
        self.assertEqual(self.mutations(calls), [["on", "db", "-n", "alpha"]])
        self.assertIn("beta/db: hibernated", out)
        self.assertIn("PVCs retained", out)

    def test_off_reactivates_all_hibernated_clusters(self):
        status, out, calls = self.run_helper("off", targets=[
            ("alpha", "db", "on"), ("beta", "db", "on"), ("gamma", "active", ""), ("delta", "active", "off"),
        ])
        self.assertEqual(status, 0, out)
        self.assertEqual(self.mutations(calls), [["off", "db", "-n", "alpha"], ["off", "db", "-n", "beta"]])
        self.assertIn("reactivates all hibernated clusters", out)
        self.assertIn("4 verified", out)

    def test_on_rejects_remaining_instance_pods_and_replaced_storage(self):
        status, out, calls = self.run_helper("on", targets=[
            ("alpha", "lingering", ""), ("alpha", "replaced", ""), ("alpha", "pending", "on"),
            ("alpha", "ok", ""),
        ], lingering=["lingering"], replaced=["replaced"], pending=["pending"])
        self.assertNotEqual(status, 0)
        self.assertEqual([(action, name) for action, name, *_ in self.mutations(calls)], [
            ("on", "lingering"), ("off", "lingering"), ("on", "replaced"), ("off", "replaced"), ("on", "ok"),
        ])
        self.assertIn("alpha/lingering: timed out", out)
        self.assertIn("alpha/lingering: cancellation recovery verified", out)
        self.assertIn("alpha/replaced: PVC inventory changed", out)
        self.assertIn("alpha/pending: timed out", out)
        self.assertIn("1 verified, 3 failed", out)

    def test_off_reports_timeout_and_failed_mutation_but_continues(self):
        status, out, calls = self.run_helper("off", targets=[
            ("alpha", "fail", "on"), ("alpha", "pending", "on"), ("beta", "unhealthy", "on"),
            ("beta", "ok", "on"),
        ], fail=["fail"], pending=["pending"], unhealthy=["unhealthy"])
        self.assertNotEqual(status, 0)
        self.assertEqual(len(self.mutations(calls)), 4)
        self.assertIn("alpha/fail: plugin mutation failed", out)
        self.assertIn("alpha/pending: timed out", out)
        self.assertIn("beta/unhealthy: timed out", out)
        self.assertIn("1 verified, 3 failed", out)

    def test_on_requires_healthy_phase_and_requested_ready_count(self):
        status, out, calls = self.run_helper("on", targets=[
            ("alpha", "bad-phase", ""), ("alpha", "short-ready", "off"), ("alpha", "ok", ""),
        ], unhealthy=["bad-phase"], short_ready=["short-ready"])
        self.assertNotEqual(status, 0, out)
        self.assertIn("alpha/bad-phase: cannot request hibernation", out)
        self.assertIn("alpha/short-ready: cannot request hibernation", out)
        self.assertEqual(self.mutations(calls), [["on", "ok", "-n", "alpha"]])
        self.assertIn("1 verified, 2 failed", out)

    def test_on_timeout_does_not_cancel_a_preexisting_deferred_request(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "on")], waiting_for_healthy=["db"])
        self.assertNotEqual(status, 0, out)
        self.assertIn("alpha/db: timed out waiting for hibernate on", out)
        self.assertEqual(self.mutations(calls), [])

    def test_on_timeout_cancels_new_deferred_request_and_checks_recovery(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")], waiting_for_healthy=["db"])
        self.assertNotEqual(status, 0)
        self.assertEqual(self.mutations(calls), [["on", "db", "-n", "alpha"], ["off", "db", "-n", "alpha"]])
        self.assertIn("alpha/db: timed out waiting for hibernate on", out)
        self.assertIn("alpha/db: cancellation recovery verified", out)

    def test_plugin_on_error_checks_fresh_intent_before_canceling(self):
        for settings, actions, message in [
            ({"fail": ["db"]}, ["on", "off"], "current off/healthy state observed"),
            ({"fail_after_on": ["db"]}, ["on", "off"], "current off/healthy state observed"),
            ({"fail": ["db"], "unreadable_after_error": ["db"]}, ["on"], "unknown; an on request may be pending"),
        ]:
            with self.subTest(settings=settings):
                status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")], **settings)
                self.assertNotEqual(status, 0, out)
                self.assertIn("plugin mutation failed", out)
                self.assertIn(message, out)
                self.assertNotIn("cancellation recovery verified", out)
                self.assertIn("an in-flight on request may still apply", out)
                self.assertIn("STOP: manually recheck this cluster before shutdown", out)
                self.assertEqual([call[0] for call in self.mutations(calls)], actions)

    def test_delayed_on_after_rejected_cancel_is_reported_pending(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "off")], delayed_on=["db"])
        self.assertNotEqual(status, 0, out)
        self.assertEqual(self.mutations(calls), [["on", "db", "-n", "alpha"], ["off", "db", "-n", "alpha"]])
        self.assertIn("already off", out)
        self.assertIn("cancellation plugin failed", out)
        self.assertIn("cancellation recovery failed; an on request may still be pending", out)
        self.assertNotIn("cancellation recovery verified", out)
        pod_read = next(i for i, call in enumerate(calls) if "pods" in call)
        self.assertTrue(any(RESOURCE in call and "db" in call for call in calls[pod_read + 1:]))

    def test_delayed_on_after_both_healthy_recovery_samples_is_unresolved(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "off")],
                                             delayed_on=["db"], delayed_on_after_samples=2)
        self.assertNotEqual(status, 0, out)
        self.assertEqual(self.mutations(calls), [["on", "db", "-n", "alpha"], ["off", "db", "-n", "alpha"]])
        self.assertIn("already off", out)
        self.assertEqual(sum("pods" in call for call in calls), 2)
        self.assertNotIn("cancellation recovery verified", out)
        self.assertIn("current off/healthy state observed", out)
        self.assertIn("an in-flight on request may still apply", out)
        self.assertIn("STOP: manually recheck this cluster before shutdown", out)

    def test_successful_cancellation_request_still_requires_healthy_pods(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")],
                                             fail_after_on=["db"], pod_modes={"db": "absent"})
        self.assertNotEqual(status, 0, out)
        self.assertEqual([call[0] for call in self.mutations(calls)], ["on", "off"])
        self.assertIn("cancellation recovery failed", out)
        self.assertNotIn("cancellation plugin failed", out)

    def test_failed_cancellation_reports_plugin_and_recovery_failure(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")],
                                             fail_after_on=["db"], fail_off=["db"])
        self.assertNotEqual(status, 0, out)
        self.assertEqual([call[0] for call in self.mutations(calls)], ["on", "off"])
        self.assertIn("cancellation plugin failed", out)
        self.assertIn("cancellation recovery failed", out)
        self.assertIn("0 verified, 1 failed", out)

    def test_off_rejects_stale_healthy_status(self):
        for mode in ("absent", "unready", "terminating", "extra", "stale_condition"):
            with self.subTest(mode=mode):
                status, out, calls = self.run_helper("off", targets=[("alpha", "db", "on")],
                    pod_modes={"db": mode}, stale_condition=["db"] if mode == "stale_condition" else [])
                self.assertNotEqual(status, 0, out)
                self.assertIn("alpha/db: timed out waiting for hibernate off", out)
                self.assertEqual(self.mutations(calls), [["off", "db", "-n", "alpha"]])

    def test_off_rejects_deleting_pods_condition_even_with_stale_ready_pods(self):
        status, out, calls = self.run_helper("off", targets=[("alpha", "db", "on")], deleting_pods=["db"])
        self.assertNotEqual(status, 0, out)
        self.assertIn("alpha/db: timed out waiting for hibernate off", out)
        self.assertEqual(self.mutations(calls), [["off", "db", "-n", "alpha"]])

    def test_off_bounds_a_blocked_pod_read(self):
        status, out, calls = self.run_helper("off", targets=[("alpha", "db", "off")], pod_modes={"db": "blocked"})
        self.assertNotEqual(status, 0, out)
        self.assertTrue(any("pods" in call for call in calls))
        self.assertIn("alpha/db: timed out waiting for hibernate off", out)

    def test_on_bounds_a_blocked_final_pvc_read_and_recovers(self):
        status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")], blocked_pvcs=["db"])
        self.assertNotEqual(status, 0, out)
        self.assertEqual(sum("pvc" in call for call in calls), 2)
        self.assertEqual([call[0] for call in self.mutations(calls)], ["on", "off"])
        self.assertIn("alpha/db: timed out waiting for hibernate on", out)
        self.assertIn("cancellation recovery verified", out)
        self.assertNotIn("STOP:", out)

    def test_failed_poll_sleep_is_reported_and_other_targets_continue(self):
        status, out, _ = self.run_helper("off", broken_sleep=True, targets=[
            ("alpha", "pending", "on"), ("alpha", "ok", "on"),
        ], pending=["pending"])
        self.assertNotEqual(status, 0, out)
        self.assertIn("alpha/pending: sleep failed", out)
        self.assertIn("1 verified, 1 failed", out)

    def test_preflight_rejects_scoped_or_unresolved_operator_before_discovery(self):
        for settings in [
            {"operator_env": [{"name": "WATCH_NAMESPACE", "value": "alpha,beta"}]},
            {"operator_env": [{"name": "WATCH_NAMESPACE", "valueFrom": {"fieldRef": {"fieldPath": "metadata.namespace"}}}]},
            {"operator_env_from": [{"configMapRef": {"name": "operator-config"}}]},
        ]:
            with self.subTest(settings=settings):
                status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")], **settings)
                self.assertNotEqual(status, 0, out)
                self.assertIn("WATCH_NAMESPACE", out)
                self.assertFalse(any(RESOURCE in call for call in calls))
                self.assertEqual(self.mutations(calls), [])

    def test_preflight_accepts_explicitly_empty_watch_namespace(self):
        status, out, _ = self.run_helper("on", operator_env=[{"name": "WATCH_NAMESPACE", "value": ""}])
        self.assertEqual(status, 0, out)

    def test_preflight_rejects_older_plugin_before_discovery(self):
        status, out, calls = self.run_helper("on", plugin_version="1.28.9", operator_version="1.28.10",
                                             targets=[("alpha", "db", "")])
        self.assertNotEqual(status, 0, out)
        self.assertIn("older than", out)
        self.assertFalse(any(RESOURCE in call for call in calls))
        self.assertEqual(self.mutations(calls), [])

    def test_preflight_accepts_newer_plugin(self):
        status, out, _ = self.run_helper("on", plugin_version="v1.28.10", operator_version="1.28.9")
        self.assertEqual(status, 0, out)
        self.assertIn("No CNPG Clusters found", out)

    def test_preflight_blocks_without_ready_operator_and_plugin(self):
        for settings in [
            {"unready": True}, {"no_plugin": True},
            *({field: version} for field in ("operator_version", "plugin_version")
              for version in ("1.27.0", "1.29.0", "1.28.0-rc1")),
        ]:
            with self.subTest(settings=settings):
                status, out, calls = self.run_helper("on", targets=[("alpha", "db", "")], **settings)
                self.assertNotEqual(status, 0)
                self.assertIn("ERROR:", out)
                self.assertEqual(self.mutations(calls), [])


if __name__ == "__main__":
    unittest.main()
