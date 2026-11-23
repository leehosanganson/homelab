#!/usr/bin/env python3
"""Reconcile declarative DNS settings on the initialized Technitium primary."""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


PAGE_SIZE = 100
RECORD_TTL = 3600


class ReconcileError(RuntimeError):
    """Raised when current state is unsafe or an API operation fails."""


class TechnitiumAPI:
    def __init__(self, base_url, token, timeout=15):
        self.base_url = base_url.rstrip("/")
        self._authorization = f"Bearer {token}"
        self.timeout = timeout

    def _request(self, method, path, params=None, json_body=None):
        query = urllib.parse.urlencode(params or {}, doseq=True)
        url = f"{self.base_url}{path}"
        if query:
            url = f"{url}?{query}"
        body = None
        headers = {"Authorization": self._authorization, "Accept": "application/json"}
        if json_body is not None:
            body = json.dumps(json_body, separators=(",", ":")).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                result = json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            status = getattr(error, "code", None)
            suffix = f" (HTTP {status})" if status else ""
            raise ReconcileError(f"Technitium API request failed at {path}{suffix}") from None
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise ReconcileError(f"Technitium API returned invalid JSON at {path}") from None

        if not isinstance(result, dict) or result.get("status") != "ok":
            status = result.get("status", "invalid response") if isinstance(result, dict) else "invalid response"
            raise ReconcileError(f"Technitium API rejected {path} ({status})")
        return result

    def get(self, path, params=None):
        return self._request("GET", path, params=params)

    def post(self, path, params=None, json_body=None):
        return self._request("POST", path, params=params, json_body=json_body)


def response_object(result):
    response = result.get("response")
    if not isinstance(response, dict):
        raise ReconcileError("Technitium API response has no valid response object")
    return response


def read_config(path):
    try:
        with open(path, "r", encoding="utf-8") as config_file:
            config = json.load(config_file)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        raise ReconcileError("Cannot read the Technitium desired-state configuration") from None
    validate_config(config)
    return config


def validate_config(config):
    if not isinstance(config, dict) or set(config) != {"clusterDomain", "blockListUrls", "zones"}:
        raise ReconcileError("Technitium desired-state configuration has an invalid schema")
    if not isinstance(config["clusterDomain"], str) or not config["clusterDomain"]:
        raise ReconcileError("Technitium desired-state configuration has an invalid cluster domain")
    if (
        not isinstance(config["blockListUrls"], list)
        or any(not isinstance(url, str) or not url for url in config["blockListUrls"])
    ):
        raise ReconcileError("Technitium desired-state configuration has invalid block-list URLs")
    zones = config["zones"]
    if not isinstance(zones, dict) or not zones:
        raise ReconcileError("Technitium desired-state configuration has invalid zones")

    zone_names = set()
    desired_records = set()
    for zone_name, records in zones.items():
        if not isinstance(zone_name, str) or not zone_name or zone_name.casefold() in zone_names:
            raise ReconcileError("Technitium desired-state configuration has duplicate or invalid zone names")
        zone_names.add(zone_name.casefold())
        if not isinstance(records, list):
            raise ReconcileError(f"Technitium desired-state records for {zone_name} are invalid")
        for record in records:
            if (
                not isinstance(record, dict)
                or set(record) != {"domain", "ipAddress"}
                or not isinstance(record["domain"], str)
                or not record["domain"]
                or not isinstance(record["ipAddress"], str)
                or not record["ipAddress"]
            ):
                raise ReconcileError(f"Technitium desired-state record for {zone_name} has an invalid schema")
            key = (zone_name.casefold(), canonical_domain(record["domain"]), record["ipAddress"])
            if key in desired_records:
                raise ReconcileError(f"Technitium desired-state configuration duplicates a record in {zone_name}")
            desired_records.add(key)


def verify_primary(api, cluster_domain):
    state = response_object(api.get("/api/admin/cluster/state", {"includeServerIpAddresses": "true"}))
    if state.get("clusterInitialized") is not True:
        raise ReconcileError("Technitium cluster is not initialized")
    if state.get("clusterDomain") != cluster_domain:
        raise ReconcileError("Technitium cluster domain does not match configured cluster domain")

    if "nodes" in state and "clusterNodes" in state:
        raise ReconcileError("Technitium cluster state contains ambiguous nodes and clusterNodes fields")
    nodes = state.get("nodes", state.get("clusterNodes"))
    if not isinstance(nodes, list):
        raise ReconcileError("Technitium cluster state is missing a valid nodes list")
    for node in nodes:
        if (
            not isinstance(node, dict)
            or not isinstance(node.get("state"), str)
            or not isinstance(node.get("type"), str)
        ):
            raise ReconcileError("Technitium cluster state has a malformed nodes entry")
    self_nodes = [node for node in nodes if node["state"].casefold() == "self"]
    if len(self_nodes) != 1 or self_nodes[0]["type"].casefold() != "primary":
        raise ReconcileError("This Technitium node is not confirmed as the cluster primary")


def catalog_zone(config):
    return f"cluster-catalog.{config['clusterDomain']}"


def list_zones(api):
    zones = []
    page = 1
    while True:
        response = response_object(api.get("/api/zones/list", {"pageNumber": page, "zonesPerPage": PAGE_SIZE}))
        page_zones = response.get("zones")
        if not isinstance(page_zones, list):
            raise ReconcileError("Technitium zone list is invalid")
        if any(not isinstance(zone, dict) or not isinstance(zone.get("name"), str) for zone in page_zones):
            raise ReconcileError("Technitium zone list contains a malformed zone")
        zones.extend(page_zones)
        total_pages = response.get("totalPages")
        if total_pages is not None:
            if not isinstance(total_pages, int) or isinstance(total_pages, bool) or total_pages < 1:
                raise ReconcileError("Technitium zone list has an invalid page count")
            if page >= total_pages:
                return zones
        elif len(page_zones) < PAGE_SIZE:
            return zones
        page += 1
        if page > 10000:
            raise ReconcileError("Technitium zone list exceeds the safe page limit")


def matching_zone(zones, zone_name):
    matches = [
        zone for zone in zones
        if zone["name"].casefold() == zone_name.casefold()
    ]
    if len(matches) > 1:
        raise ReconcileError(f"Technitium zone {zone_name} is ambiguous because it appears more than once")
    return matches[0] if matches else None


def validate_zones(zones, config):
    catalog_name = catalog_zone(config)
    catalog = matching_zone(zones, catalog_name)
    if catalog is None or not isinstance(catalog.get("type"), str) or catalog["type"].casefold() != "catalog":
        raise ReconcileError(f"Expected cluster catalog zone {catalog_name} is not available")
    if catalog.get("disabled") is True:
        raise ReconcileError(
            f"Cluster catalog zone {catalog_name} is disabled; enable it in Technitium before retrying reconciliation"
        )

    for zone_name in config["zones"]:
        zone = matching_zone(zones, zone_name)
        if zone is None:
            continue
        if not isinstance(zone.get("type"), str) or zone["type"].casefold() != "primary":
            raise ReconcileError(f"Existing zone {zone_name} is not a Primary zone")
        if zone.get("disabled") is True:
            raise ReconcileError(
                f"Target zone {zone_name} is disabled; enable it in Technitium before retrying reconciliation"
            )


def canonical_domain(domain):
    return domain.rstrip(".").casefold()


def get_records(api, zone_name):
    response = response_object(api.get("/api/zones/records/get", {
        "domain": zone_name,
        "zone": zone_name,
        "listZone": "true",
    }))
    records = response.get("records")
    if not isinstance(records, list):
        raise ReconcileError(f"Technitium record list for {zone_name} is invalid")
    if any(not isinstance(record, dict) for record in records):
        raise ReconcileError(f"Technitium record list for {zone_name} contains a malformed record")
    return records


def preflight_records(records_by_zone, config):
    for zone_name, desired_records in config["zones"].items():
        current_records = records_by_zone[zone_name]
        for desired in desired_records:
            key = (canonical_domain(desired["domain"]), desired["ipAddress"])
            matches = [
                record for record in current_records
                if isinstance(record.get("type"), str)
                and record["type"].casefold() == "a"
                and isinstance(record.get("name"), str)
                and isinstance(record.get("rData"), dict)
                and record["rData"].get("ipAddress") == desired["ipAddress"]
                and (canonical_domain(record["name"]), record["rData"]["ipAddress"]) == key
            ]
            if len(matches) > 1:
                raise ReconcileError(
                    f"Desired A record {desired['domain']} has duplicate exact entries in {zone_name}; "
                    "remove duplicates in Technitium before retrying reconciliation"
                )
            if matches and matches[0].get("disabled") is True:
                raise ReconcileError(
                    f"Desired A record {desired['domain']} in {zone_name} is disabled; "
                    "enable it in Technitium before retrying reconciliation"
                )


def ensure_records(api, zone_name, desired_records, current_records):
    current = {
        (canonical_domain(record["name"]), record["rData"]["ipAddress"])
        for record in current_records
        if isinstance(record.get("type"), str)
        and record["type"].casefold() == "a"
        and isinstance(record.get("name"), str)
        and isinstance(record.get("rData"), dict)
        and isinstance(record["rData"].get("ipAddress"), str)
    }
    for record in desired_records:
        domain = record["domain"]
        address = record["ipAddress"]
        if (canonical_domain(domain), address) in current:
            continue
        api.post("/api/zones/records/add", {
            "domain": domain,
            "zone": zone_name,
            "type": "A",
            "ipAddress": address,
            "ttl": RECORD_TTL,
            "overwrite": "false",
        })
        current.add((canonical_domain(domain), address))


def reconcile(api, config):
    validate_config(config)
    cluster_domain = config["clusterDomain"]
    verify_primary(api, cluster_domain)
    zones = list_zones(api)
    validate_zones(zones, config)
    settings = response_object(api.get("/api/settings/get"))

    catalogs = {}
    records = {}
    for zone_name in config["zones"]:
        zone = matching_zone(zones, zone_name)
        if zone is not None:
            options = response_object(api.get("/api/zones/options/get", {
                "zone": zone_name,
                "includeAvailableCatalogZoneNames": "true",
            }))
            catalogs[zone_name] = options.get("catalog")
            records[zone_name] = get_records(api, zone_name)
        else:
            catalogs[zone_name] = None
            records[zone_name] = []
    preflight_records(records, config)

    desired_blocklist_urls = config["blockListUrls"]
    if settings.get("enableBlocking") is not True or settings.get("blockListUrls") != desired_blocklist_urls:
        api.post("/api/settings/set", json_body={
            "enableBlocking": True,
            "blockListUrls": desired_blocklist_urls,
        })

    for zone_name in config["zones"]:
        if matching_zone(zones, zone_name) is None:
            api.post("/api/zones/create", {
                "zone": zone_name,
                "type": "Primary",
                "catalog": catalog_zone(config),
            })
        elif catalogs[zone_name] != catalog_zone(config):
            api.post("/api/zones/options/set", {"zone": zone_name, "catalog": catalog_zone(config)})
    for zone_name, desired_records in config["zones"].items():
        ensure_records(api, zone_name, desired_records, records[zone_name])


def read_token(path):
    try:
        with open(path, "r", encoding="utf-8") as token_file:
            token = token_file.read().strip()
    except OSError:
        raise ReconcileError("Cannot read the Technitium API credential") from None
    if not token:
        raise ReconcileError("Technitium API credential is empty")
    return token


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:5380")
    parser.add_argument("--config-file", required=True)
    parser.add_argument("--token-file", required=True)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        config = read_config(args.config_file)
        token = read_token(args.token_file)
        api = TechnitiumAPI(args.base_url, token)
        reconcile(api, config)
    except ReconcileError as error:
        print(f"Technitium reconciliation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
