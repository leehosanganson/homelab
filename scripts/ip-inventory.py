#!/usr/bin/env python3
"""List covered IP declarations in this checkout's NixOS infrastructure."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from collections import defaultdict
from ipaddress import ip_address, ip_interface
from pathlib import Path


COVERAGE = "Coverage: NixOS host interface addresses, keepalived VIPs, and HAProxy backend IP endpoints only."


def parse_ip(text):
    try:
        return ip_address(text) if "%" not in text else None
    except ValueError:
        return None


def config_lines(text):
    for line in text.splitlines():
        yield line.partition("#")[0].split()


def vip_entries(lines):
    blocks = []
    instance = None
    for fields in lines:
        if not fields:
            continue
        if fields[-1] == "{" and len(fields) in (2, 3):
            if not blocks and fields[0] == "vrrp_instance" and len(fields) == 3:
                instance = fields[1]
            blocks.append(fields[0])
        elif fields == ["}"] and blocks:
            blocks.pop()
        elif instance and blocks == ["vrrp_instance", "virtual_ipaddress"]:
            try:
                ip = ip_interface(fields[0]).ip
            except ValueError:
                continue
            if "%" not in fields[0]:
                yield ip, f"vip {instance}"


def backend_entries(lines):
    sections = {
        "global", "defaults", "frontend", "listen", "backend", "peers", "mailers",
        "resolvers", "userlist", "cache", "program", "ring", "log-forward", "fcgi-app",
        "crt-store", "acme", "traces",
    }
    backend = None
    for fields in lines:
        if not fields:
            continue
        if fields[0] in sections:
            backend = fields[1] if fields[0] == "backend" and len(fields) >= 2 else None
        elif backend and fields[0] == "server" and len(fields) >= 3:
            endpoint = re.fullmatch(r'(\[[^\]]+\]|[^:]+):([0-9]{1,5})', fields[2])
            if endpoint:
                address, port = endpoint.groups()
                ip = parse_ip(address.strip("[]"))
                if ip and 0 < int(port) <= 65535:
                    yield ip, f"backend {backend}/{fields[1]} (port {port})"


def project(root):
    try:
        result = subprocess.run(
            [
                "nix-instantiate", "--eval", "--strict", "--json",
                "--eval-store", "dummy://",
                "--option", "restrict-eval", "true",
                "--option", "allowed-uris", "",
                "--option", "allow-import-from-derivation", "false",
                "--option", "nix-path", "",
                "-I", f"inventory={root / 'nixos'}",
                "-I", f"projection={root / 'scripts/ip-inventory.nix'}",
                "--expr", "import <projection>",
            ],
            env={**os.environ, "NIX_PATH": ""},
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError as error:
        raise ValueError("nix-instantiate is required") from error
    if result.returncode:
        raise ValueError(f"Nix projection failed:\n{result.stderr.strip()}")
    return json.loads(result.stdout)


def provenance(root, entry):
    position = entry["position"]
    path = Path(position["file"] if position else entry["file"])
    if path.is_relative_to(root):
        path = path.relative_to(root)
    return f"{path}:{position['line']}" if position else str(path)


def inventory(root):
    projected = project(root)
    by_ip = defaultdict(list)
    for entry in projected["hosts"]:
        ip = parse_ip(entry["address"])
        if ip and entry["family"] == f"ipv{ip.version}":
            label = f"host {entry['hostname']} ({entry['interface']})"
            by_ip[ip].append(f"{label} [{provenance(root, entry)}]")
    for key, reader in (("keepalived", vip_entries), ("haproxy", backend_entries)):
        option = projected[key]
        for ip, label in reader(config_lines(option["text"])):
            by_ip[ip].append(f"{label} [{provenance(root, option)}]")
    return by_ip


def main():
    parser = argparse.ArgumentParser(description=COVERAGE)
    parser.add_argument("ip", nargs="?", help="optional IPv4 or IPv6 address to look up")
    args = parser.parse_args()
    lookup = parse_ip(args.ip) if args.ip is not None else None
    if args.ip is not None and lookup is None:
        parser.error(f"invalid IP address: {args.ip}")
    try:
        by_ip = inventory(Path(__file__).resolve().parents[1])
    except (OSError, ValueError) as error:
        parser.exit(2, f"{parser.prog}: {error}\n")
    print(COVERAGE)
    if lookup is not None and lookup not in by_ip:
        print(f"No covered declaration for {lookup}.")
        return 1
    for ip in [lookup] if lookup is not None else sorted(by_ip, key=lambda ip: (ip.version, int(ip))):
        print(f"\n{ip}")
        for label in by_ip[ip]:
            print(f"  {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
