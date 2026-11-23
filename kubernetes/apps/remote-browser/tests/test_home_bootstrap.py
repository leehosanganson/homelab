import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
DEPLOYMENT = REPOSITORY_ROOT / "kubernetes/apps/remote-browser/base/deployment.yaml"
SERVICE = REPOSITORY_ROOT / "kubernetes/apps/remote-browser/base/service.yaml"
INGRESS = REPOSITORY_ROOT / "kubernetes/apps/remote-browser/base/ingress.yaml"


def metadata_annotations(manifest):
    metadata = manifest.split("\nmetadata:\n", 1)[1].split("\nspec:\n", 1)[0]
    if "\n  annotations:\n" not in metadata:
        return ""
    return metadata.split("\n  annotations:\n", 1)[1]


def bootstrap_script():
    manifest = DEPLOYMENT.read_text()
    container = manifest.index("        - name: bootstrap-kasm-home")
    command = manifest.index("            - |\n", container) + len("            - |\n")
    lines = manifest[command:].splitlines()
    script_lines = []
    for line in lines:
        if line.startswith("              "):
            script_lines.append(line[14:])
        elif not line:
            script_lines.append("")
        else:
            break

    script = "\n".join(script_lines)
    script = script.replace("/home/kasm-user", '"$KASM_IMAGE_HOME"')
    script = script.replace(
        "/home/kasm-default-profile", '"$KASM_DEFAULT_PROFILE"'
    )
    script = script.replace("/mnt/kasm-home", '"$KASM_HOME_TARGET"')
    script = script.replace("/mnt/legacy-profile", '"$LEGACY_PROFILE_ROOT"')
    return script


def tree_digest(root):
    digest = hashlib.sha256()
    root_stat = root.lstat()
    digest.update(
        str((root_stat.st_mode, root_stat.st_uid, root_stat.st_gid)).encode()
    )
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root).as_posix()
        path_stat = path.lstat()
        digest.update(relative.encode())
        digest.update(
            str((path_stat.st_mode, path_stat.st_uid, path_stat.st_gid)).encode()
        )
        if path.is_symlink():
            digest.update(b"symlink:")
            digest.update(os.readlink(path).encode())
        elif path.is_file():
            digest.update(b"file:")
            digest.update(path.read_bytes())
        elif path.is_dir():
            digest.update(b"directory")
    return digest.hexdigest()


class HomeBootstrapTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.image_home = self.root / "image-home"
        self.image_home.mkdir()
        self.default_profile = self.root / "default-profile"
        self.default_profile.mkdir()
        (self.default_profile / ".bashrc").write_text("# Kasm default shell setup\n")
        desktop = self.default_profile / "Desktop"
        desktop.mkdir()
        (desktop / "google-chrome.desktop").write_text("[Desktop Entry]\n")
        self.legacy_profile = self.root / "legacy-profile" / "google-chrome"
        legacy_default = self.legacy_profile / "Default"
        legacy_default.mkdir(parents=True)
        (legacy_default / "Preferences").write_text('{"profile": "legacy"}\n')
        (self.legacy_profile / "Local State").write_text('{"legacy": true}\n')

        self.target = self.root / "target"
        self.target.mkdir()
        self.source_before = (
            tree_digest(self.default_profile),
            tree_digest(self.legacy_profile),
        )
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake_id = self.bin / "id"
        fake_id.write_text(
            "#!/bin/sh\n"
            'case "$1" in\n'
            "  -u) printf '1200\\n' ;;\n"
            "  -g) printf '1201\\n' ;;\n"
            "  *) exit 2 ;;\n"
            "esac\n"
        )
        fake_id.chmod(0o755)
        fake_find = self.bin / "find"
        real_find = shutil.which("find")
        fake_find.write_text(
            f"#!{shutil.which('bash')}\n"
            'if [[ "${KASM_FAIL_TARGET_FIND:-}" == 1 && "$1" == "$KASM_HOME_TARGET" &&\n'
            '      "$2" == "-mindepth" && "$4" == "-maxdepth" ]]; then\n'
            '  echo "find: simulated target scan failure" >&2\n'
            "  exit 1\n"
            "fi\n"
            f'exec {real_find} "$@"\n'
        )
        fake_find.chmod(0o755)
        fake_chmod = self.bin / "chmod"
        real_chmod = shutil.which("chmod")
        fake_chmod.write_text(
            f"#!{shutil.which('bash')}\n"
            'for path in "$@"; do\n'
            '  if [[ "$path" == "$KASM_HOME_TARGET" ]]; then\n'
            "    printf \"chmod: changing permissions of '%s': Operation not permitted\\\\n\" \"$path\" >&2\n"
            "    exit 1\n"
            "  fi\n"
            "done\n"
            f'exec {real_chmod} "$@"\n'
        )
        fake_chmod.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_bootstrap(self, fail_target_find=False):
        env = os.environ.copy()
        env.update(
            {
                "KASM_IMAGE_HOME": str(self.image_home),
                "KASM_DEFAULT_PROFILE": str(self.default_profile),
                "KASM_HOME_TARGET": str(self.target),
                "LEGACY_PROFILE_ROOT": str(self.legacy_profile.parent),
                "PATH": f"{self.bin}:{os.environ['PATH']}",
                "KASM_FAIL_TARGET_FIND": "1" if fail_target_find else "0",
            }
        )
        return subprocess.run(
            ["bash", "-euo", "pipefail", "-c", bootstrap_script()],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_sources_unchanged(self):
        self.assertEqual(
            self.source_before,
            (tree_digest(self.default_profile), tree_digest(self.legacy_profile)),
        )

    def test_copies_default_home_and_legacy_chrome_profile(self):
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.target / ".bashrc").is_file())
        self.assertEqual((self.target / ".bashrc").stat().st_uid, os.getuid())
        self.assertTrue((self.target / "Desktop/google-chrome.desktop").is_file())
        self.assertEqual(
            (self.target / ".config/google-chrome/Default/Preferences").read_text(),
            '{"profile": "legacy"}\n',
        )
        self.assertEqual(
            (self.target / ".config/google-chrome/Local State").read_text(),
            '{"legacy": true}\n',
        )
        self.assertTrue((self.target / ".kasm-home-bootstrap-complete").is_file())
        self.assert_sources_unchanged()

    def test_bootstrap_succeeds_when_target_root_cannot_be_chmodded(self):
        self.target.chmod(0o2775)
        external = self.root / "external-target"
        external.mkdir()
        external.chmod(0o500)
        (self.default_profile / "linked-data").symlink_to(external)
        self.source_before = (
            tree_digest(self.default_profile),
            tree_digest(self.legacy_profile),
        )

        result = self.run_bootstrap()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.target / ".kasm-home-bootstrap-complete").is_file())
        self.assertEqual(self.target.stat().st_mode & 0o7777, 0o2775)
        self.assertTrue((self.target / "linked-data").is_symlink())
        self.assertEqual(external.stat().st_mode & 0o7777, 0o500)
        self.assert_sources_unchanged()

    def test_marker_makes_bootstrap_idempotent(self):
        first = self.run_bootstrap()
        self.assertEqual(first.returncode, 0, first.stderr)
        sentinel = self.target / "Kasm-created-after-bootstrap"
        sentinel.write_text("preserve this runtime change\n")
        before_retry = tree_digest(self.target)

        retry = self.run_bootstrap()

        self.assertEqual(retry.returncode, 0, retry.stderr)
        self.assertEqual(tree_digest(self.target), before_retry)
        self.assert_sources_unchanged()

    def test_invalid_marker_is_rejected_without_changes(self):
        marker_variants = {
            "wrong content": lambda marker: marker.write_text(
                "not the completion message\n"
            ),
            "directory": lambda marker: marker.mkdir(),
            "dangling symlink": lambda marker: marker.symlink_to(
                self.root / "missing"
            ),
            "symlink to valid content": lambda marker: marker.symlink_to(
                self.root / "expected-marker"
            ),
        }

        for name, create_marker in marker_variants.items():
            with self.subTest(marker=name):
                for child in self.target.iterdir():
                    if child.is_dir() and not child.is_symlink():
                        child.rmdir()
                    else:
                        child.unlink()
                marker = self.target / ".kasm-home-bootstrap-complete"
                if name == "symlink to valid content":
                    (self.root / "expected-marker").write_text(
                        "Bootstrapped from the image home and legacy Chrome profile.\n"
                    )
                create_marker(marker)
                before_rejection = tree_digest(self.target)

                result = self.run_bootstrap()

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("marker exists but is invalid", result.stderr)
                self.assertEqual(tree_digest(self.target), before_rejection)
                self.assert_sources_unchanged()

    def test_backend_transport_annotations_are_on_service_not_ingress(self):
        service_annotations = metadata_annotations(SERVICE.read_text())
        ingress_annotations = metadata_annotations(INGRESS.read_text())

        for annotation in (
            "traefik.ingress.kubernetes.io/service.serversscheme: https",
            "traefik.ingress.kubernetes.io/service.serverstransport: "
            "remote-browser-kasmvnc@kubernetescrd",
        ):
            with self.subTest(annotation=annotation):
                self.assertIn(annotation, service_annotations)
                self.assertNotIn(annotation, ingress_annotations)

        self.assertIn(
            "cert-manager.io/cluster-issuer: letsencrypt-cloudflare",
            ingress_annotations,
        )

    def test_kasmvnc_tls_paths_match_mounted_home(self):
        config = (
            REPOSITORY_ROOT
            / "kubernetes/apps/remote-browser/overlays/default/kasmvnc.yaml"
        ).read_text()
        deployment = DEPLOYMENT.read_text()

        self.assertIn("pem_certificate: ${HOME}/.vnc/self.pem", config)
        self.assertIn("pem_key: ${HOME}/.vnc/self.pem", config)
        self.assertIn("mountPath: /home/kasm-user", deployment)

    def test_target_scan_error_fails_closed_without_changes(self):
        before_target = tree_digest(self.target)
        before_sources = (
            tree_digest(self.default_profile),
            tree_digest(self.legacy_profile),
        )

        result = self.run_bootstrap(fail_target_find=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("find: simulated target scan failure", result.stderr)
        self.assertEqual(tree_digest(self.target), before_target)
        self.assertEqual(
            (tree_digest(self.default_profile), tree_digest(self.legacy_profile)),
            before_sources,
        )

    def test_nonempty_unmarked_target_is_rejected_without_changes(self):
        sentinel = self.target / "existing-data"
        sentinel.write_text("do not overwrite\n")
        before_rejection = tree_digest(self.target)

        result = self.run_bootstrap()

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-empty without a bootstrap marker", result.stderr)
        self.assertEqual(tree_digest(self.target), before_rejection)
        self.assert_sources_unchanged()


if __name__ == "__main__":
    unittest.main()
