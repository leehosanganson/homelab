import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().with_name("ip-inventory.py")


def run_inventory(*args, script=SCRIPT, cwd=None):
    return subprocess.run(
        [sys.executable, str(script), *args],
        cwd=cwd, capture_output=True, text=True, check=False,
    )


class InventoryTests(unittest.TestCase):
    def run_fixture(self, host_source, proxy_source):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "scripts/ip-inventory.py"
            script.parent.mkdir()
            shutil.copyfile(SCRIPT, script)
            shutil.copyfile(SCRIPT.with_suffix(".nix"), script.with_suffix(".nix"))
            for path, source in (
                ("nixos/hosts/haproxy-1/default.nix", host_source),
                ("nixos/modules/haproxy.nix", proxy_source),
            ):
                target = root / path
                target.parent.mkdir(parents=True)
                target.write_text(source, encoding="utf-8")
            return run_inventory(script=script)

    def test_unrelated_let_named_path_does_not_hide_host_address(self):
        result = self.run_fixture('''{ sops-secrets, ... }: {
  source = ./let;
  sops.defaultSopsFile = "${sops-secrets}/secrets.yaml";
  networking.hostName = "fixture";
  networking.interfaces.eth0.ipv4.addresses = [
    { address = "192.0.2.21"; }
  ];
}
''', '{ ... }: {}')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\n192.0.2.21\n", result.stdout)
        self.assertIn("host fixture (eth0) [nixos/hosts/haproxy-1/default.nix:6]", result.stdout)

    def test_only_selected_nix_interpolation_contributes_backends(self):
        result = self.run_fixture('''{ ... }: {
  networking.hostName = "haproxy-1";
}
''', """{ config, ... }: {
  services.haproxy.config = ''
    backend example
    ${if config.networking.hostName == "haproxy-1" then "
      server selected 192.0.2.22:443
    " else "
      server phantom 192.0.2.23:443
    "}
  '';
}
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("192.0.2.23", result.stdout)
        self.assertIn("\n192.0.2.22\n", result.stdout)
        self.assertIn("backend example/selected (port 443) [nixos/modules/haproxy.nix:2]", result.stdout)

    def test_list_groups_roles_and_reports_provenance(self):
        result = run_inventory()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Coverage: NixOS host interface addresses", result.stdout)
        shared = result.stdout.split("\n192.168.1.151\n", 1)[1].split("\n192.168.1.152\n", 1)[0]
        self.assertIn("host k3s-ctrl-01", shared)
        self.assertRegex(shared, r"nixos/hosts/k3s-ctrl-01/default\.nix:\d+")
        self.assertIn("backend k3s/ctrl-01 (port 443)", shared)
        self.assertIn("backend k3s_api_backend/ctrl-01 (port 6443)", shared)
        self.assertIn("backend synology/nas-1 (port 5000)", result.stdout)
        self.assertIn("backend ipkvm/comet (port 443)", result.stdout)
        self.assertIn("vip VI_HAPROXY", result.stdout)
        self.assertIn("backend local_ssl_termination/loopback", result.stdout)
        self.assertNotIn("\n192.168.1.1\n", result.stdout)
        self.assertNotIn("\nfd00:1::1\n", result.stdout)

    def test_lookup_normalizes_ipv6_and_works_outside_repo(self):
        with tempfile.TemporaryDirectory() as cwd:
            result = run_inventory("fd00:0001:0:0162:0:0:0:0162", cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\nfd00:1:0:162::162\n", result.stdout)
        self.assertIn("host matter-server", result.stdout)
        self.assertNotIn("192.168.1.162", result.stdout)

    def test_invalid_and_unlisted_ips_have_distinct_exits(self):
        invalid = run_inventory("not-an-ip")
        self.assertEqual(invalid.returncode, 2)
        self.assertIn("invalid IP address", invalid.stderr)
        unlisted = run_inventory("203.0.113.254")
        self.assertEqual(unlisted.returncode, 1)
        self.assertIn("No covered declaration", unlisted.stdout)

    def test_only_ips_in_supported_contexts_are_labeled(self):
        result = self.run_fixture('''{ ... }: {
  ignored.interfaces.eth0.ipv4.addresses = [ { address = "192.0.2.1"; } ];
  networking = {
    hostName = "declared-name";
    # interfaces.eth0.ipv4.addresses = [ { address = "192.0.2.2"; } ];
    interfaces."lan0".ipv4.addresses = [
      { address = "192.0.2.3"; prefixLength = 24; }
      { address = "192.0.2." + toString 4; }
      { address = "192.0.2.5"; }
    ];
    defaultGateway = { address = "192.0.2.6"; };
  };
}
''', """{ ... }: {
  services.haproxy.config = ''
    backend example
    server node 192.0.2.3:443 check
    server v6 [2001:db8::7]:443
    server domain example.invalid:443
    # server commented 192.0.2.8:443
    listen other
    server not-a-backend 192.0.2.9:443
    defaults later
    server not-a-backend 192.0.2.10:443
  '';
  services.keepalived.extraConfig = ''
    vrrp_instance DEMO {
      virtual_ipaddress {
        192.0.2.3/24 dev eth0
      }
      unicast_peer {
        192.0.2.11
      }
    }
  '';
}
""")
        self.assertEqual(result.returncode, 0, result.stderr)
        headings = [line for line in result.stdout.splitlines() if line and not line.startswith(" ")]
        self.assertEqual(headings[1:], ["192.0.2.3", "192.0.2.4", "192.0.2.5", "2001:db8::7"])
        self.assertEqual(result.stdout.count("host declared-name"), 3)
        self.assertIn("backend example/node (port 443)", result.stdout)
        self.assertIn("vip DEMO [nixos/modules/haproxy.nix:13]", result.stdout)
        self.assertNotIn("host haproxy-1", result.stdout)


if __name__ == "__main__":
    unittest.main()
