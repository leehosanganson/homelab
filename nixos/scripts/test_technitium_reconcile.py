import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest import mock


SCRIPT = pathlib.Path(__file__).with_name("technitium-reconcile.py")
SPEC = importlib.util.spec_from_file_location("technitium_reconcile", SCRIPT)
reconciler = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reconciler)

TEST_CONFIG = {
    "clusterDomain": "technitium-cluster.infra.leehosanganson.dev",
    "blockListUrls": ["https://lists.example.test/pro.txt", "https://lists.example.test/fake.txt"],
    "zones": {
        "home.lab": [
            {"domain": "router.home.lab", "ipAddress": "192.168.1.250"},
            {"domain": "nas.home.lab", "ipAddress": "192.168.1.197"},
        ],
        "example.test": [
            {"domain": "example.test", "ipAddress": "192.168.1.250"},
            {"domain": "*.example.test", "ipAddress": "192.168.1.250"},
        ],
    },
}


def catalog_zone(config=TEST_CONFIG):
    return f"cluster-catalog.{config['clusterDomain']}"


def existing_target_zones(config=TEST_CONFIG):
    return [
        {"name": catalog_zone(config), "type": "Catalog"},
        *[
            {"name": zone_name, "type": "Primary", "catalog": catalog_zone(config)}
            for zone_name in config["zones"]
        ],
    ]


def empty_records(config=TEST_CONFIG):
    return {zone_name: [] for zone_name in config["zones"]}


class FakeAPI:
    def __init__(self, cluster_state=None, settings=None, zones=None, records=None, options=None):
        self.cluster_state = cluster_state or {
            "clusterInitialized": True,
            "clusterDomain": TEST_CONFIG["clusterDomain"],
            "dnsServerDomain": "technitium-1",
            "nodes": [
                {"name": "technitium-1", "type": "Primary", "state": "Self"},
                {"name": "technitium-2", "type": "Secondary", "state": "Connected"},
            ],
        }
        self.settings = settings or {
            "enableBlocking": False,
            "blockListUrls": [],
            "forwarders": ["1.1.1.1"],
        }
        self.zones = [{"name": catalog_zone(), "type": "Catalog"}] if zones is None else zones
        self.records = {} if records is None else records
        self.options = {} if options is None else options
        self.calls = []

    def get(self, path, params=None):
        params = params or {}
        self.calls.append(("GET", path, dict(params)))
        if path == "/api/admin/cluster/state":
            return {"response": self.cluster_state, "status": "ok"}
        if path == "/api/settings/get":
            return {"response": self.settings, "status": "ok"}
        if path == "/api/zones/list":
            return {"response": {"zones": self.zones, "totalPages": 1}, "status": "ok"}
        if path == "/api/zones/options/get":
            zone = params["zone"]
            return {"response": self.options.get(zone, {"name": zone, "type": "Primary"}), "status": "ok"}
        if path == "/api/zones/records/get":
            return {"response": {"records": self.records.get(params["zone"], [])}, "status": "ok"}
        raise AssertionError(f"Unexpected GET {path}")

    def post(self, path, params=None, json_body=None):
        params = params or {}
        self.calls.append(("POST", path, dict(params), json_body))
        if path == "/api/settings/set":
            self.settings.update(json_body)
        elif path == "/api/zones/create":
            self.zones.append({"name": params["zone"], "type": params["type"], "catalog": params["catalog"]})
            self.options[params["zone"]] = {"name": params["zone"], "type": "Primary", "catalog": params["catalog"]}
            self.records.setdefault(params["zone"], [])
        elif path == "/api/zones/options/set":
            self.options[params["zone"]].update(params)
        elif path == "/api/zones/records/add":
            self.records.setdefault(params["zone"], []).append({
                "name": params["domain"],
                "type": params["type"],
                "disabled": False,
                "rData": {"ipAddress": params["ipAddress"]},
            })
        else:
            raise AssertionError(f"Unexpected POST {path}")
        return {"status": "ok"}


class ReconciliationTests(unittest.TestCase):
    def test_unready_or_non_primary_cluster_never_writes(self):
        states = [
            {"clusterInitialized": False, "clusterDomain": TEST_CONFIG["clusterDomain"]},
            {"clusterInitialized": True, "clusterDomain": "wrong.example"},
            {
                "clusterInitialized": True,
                "clusterDomain": TEST_CONFIG["clusterDomain"],
                "nodes": [{"name": "technitium-1", "type": "Secondary", "state": "Self"}],
            },
        ]
        for state in states:
            with self.subTest(state=state):
                api = FakeAPI(cluster_state=state)
                with self.assertRaises(reconciler.ReconcileError):
                    reconciler.reconcile(api, TEST_CONFIG)
                self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_primary_detection_accepts_documented_nodes_and_legacy_cluster_nodes(self):
        for field in ("nodes", "clusterNodes"):
            with self.subTest(field=field):
                state = {
                    "clusterInitialized": True,
                    "clusterDomain": TEST_CONFIG["clusterDomain"],
                    field: [{"name": "technitium-1", "type": "Primary", "state": "Self"}],
                }
                reconciler.verify_primary(FakeAPI(cluster_state=state), TEST_CONFIG["clusterDomain"])

    def test_missing_or_malformed_node_schema_fails_before_writes(self):
        malformed_states = [
            {"clusterInitialized": True, "clusterDomain": TEST_CONFIG["clusterDomain"]},
            {"clusterInitialized": True, "clusterDomain": TEST_CONFIG["clusterDomain"], "nodes": None},
            {"clusterInitialized": True, "clusterDomain": TEST_CONFIG["clusterDomain"], "nodes": [{}]},
            {"clusterInitialized": True, "clusterDomain": TEST_CONFIG["clusterDomain"], "nodes": ["not-a-node"]},
            {
                "clusterInitialized": True,
                "clusterDomain": TEST_CONFIG["clusterDomain"],
                "nodes": [{"type": "Primary", "state": "Self"}],
                "clusterNodes": [{"type": "Primary", "state": "Self"}],
            },
        ]
        for state in malformed_states:
            with self.subTest(state=state):
                api = FakeAPI(cluster_state=state)
                with self.assertRaises(reconciler.ReconcileError):
                    reconciler.reconcile(api, TEST_CONFIG)
                self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_config_file_requires_the_complete_desired_state_schema(self):
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as config_file:
            json.dump(TEST_CONFIG, config_file)
            config_file.flush()
            self.assertEqual(reconciler.read_config(config_file.name), TEST_CONFIG)

        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as config_file:
            json.dump({"clusterDomain": TEST_CONFIG["clusterDomain"]}, config_file)
            config_file.flush()
            with self.assertRaisesRegex(reconciler.ReconcileError, "configuration"):
                reconciler.read_config(config_file.name)

    def test_wrong_expected_cluster_id_is_rejected_without_writes(self):
        config = {**TEST_CONFIG, "clusterDomain": "other.example"}
        api = FakeAPI()
        with self.assertRaises(reconciler.ReconcileError):
            reconciler.reconcile(api, config)
        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_missing_catalog_is_detected_before_settings_or_zone_writes(self):
        api = FakeAPI(zones=[])
        with self.assertRaises(reconciler.ReconcileError):
            reconciler.reconcile(api, TEST_CONFIG)
        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_disabled_target_zone_fails_preflight_before_any_writes(self):
        zones = existing_target_zones()
        zones[1]["disabled"] = True
        api = FakeAPI(zones=zones)

        with self.assertRaisesRegex(reconciler.ReconcileError, "home.lab is disabled; enable"):
            reconciler.reconcile(api, TEST_CONFIG)

        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_disabled_exact_desired_record_fails_preflight_before_any_writes(self):
        desired = TEST_CONFIG["zones"]["home.lab"][0]
        records = empty_records()
        records["home.lab"] = [{
            "name": desired["domain"],
            "type": "A",
            "disabled": True,
            "rData": {"ipAddress": desired["ipAddress"]},
        }]
        api = FakeAPI(zones=existing_target_zones(), records=records)

        with self.assertRaisesRegex(reconciler.ReconcileError, "disabled.*enable it"):
            reconciler.reconcile(api, TEST_CONFIG)

        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_duplicate_exact_desired_records_fail_preflight_before_any_writes(self):
        desired = TEST_CONFIG["zones"]["home.lab"][0]
        duplicate = {
            "name": desired["domain"],
            "type": "A",
            "disabled": False,
            "rData": {"ipAddress": desired["ipAddress"]},
        }
        records = empty_records()
        records["home.lab"] = [duplicate, dict(duplicate)]
        api = FakeAPI(zones=existing_target_zones(), records=records)

        with self.assertRaisesRegex(reconciler.ReconcileError, "duplicate.*home.lab"):
            reconciler.reconcile(api, TEST_CONFIG)

        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_primary_reconciles_configured_settings_zones_and_records_additively(self):
        unrelated_record = {
            "name": "manual.home.lab",
            "type": "A",
            "disabled": False,
            "rData": {"ipAddress": "192.168.1.99"},
        }
        api = FakeAPI(
            settings={"enableBlocking": False, "blockListUrls": [], "forwarders": ["9.9.9.9"]},
            zones=[{"name": catalog_zone(), "type": "Catalog"}, {"name": "home.lab", "type": "Primary"}],
            records={"home.lab": [unrelated_record]},
            options={"home.lab": {"name": "home.lab", "type": "Primary"}},
        )

        reconciler.reconcile(api, TEST_CONFIG)

        self.assertTrue(api.settings["enableBlocking"])
        self.assertEqual(api.settings["blockListUrls"], TEST_CONFIG["blockListUrls"])
        self.assertEqual(api.settings["forwarders"], ["9.9.9.9"])
        settings_writes = [call for call in api.calls if call[0] == "POST" and call[1] == "/api/settings/set"]
        self.assertEqual(settings_writes[0][3], {
            "enableBlocking": True,
            "blockListUrls": TEST_CONFIG["blockListUrls"],
        })
        self.assertEqual(
            {zone["name"] for zone in api.zones},
            {catalog_zone(), *TEST_CONFIG["zones"]},
        )
        for zone_name in TEST_CONFIG["zones"]:
            self.assertEqual(api.options[zone_name]["catalog"], catalog_zone())
            actual = {
                (record["name"], record["rData"]["ipAddress"])
                for record in api.records[zone_name]
                if record["type"] == "A"
            }
            for item in TEST_CONFIG["zones"][zone_name]:
                self.assertIn((item["domain"], item["ipAddress"]), actual)
        self.assertIn(unrelated_record, api.records["home.lab"])
        self.assertTrue(all(
            call[2]["overwrite"] == "false" and call[2]["ttl"] == reconciler.RECORD_TTL
            for call in api.calls
            if call[0] == "POST" and call[1] == "/api/zones/records/add"
        ))
        self.assertFalse(any(call[0] == "POST" and call[1] == "/api/zones/records/delete" for call in api.calls))

    def test_reconciliation_is_idempotent(self):
        api = FakeAPI()
        reconciler.reconcile(api, TEST_CONFIG)
        first_write_count = sum(call[0] == "POST" for call in api.calls)
        api.calls.clear()

        reconciler.reconcile(api, TEST_CONFIG)

        self.assertGreater(first_write_count, 0)
        self.assertFalse(any(call[0] == "POST" for call in api.calls))

    def test_existing_exact_record_is_not_added_twice_and_different_address_is_preserved(self):
        exact = TEST_CONFIG["zones"]["home.lab"][0]
        api = FakeAPI(
            zones=existing_target_zones(),
            records={
                **empty_records(),
                "home.lab": [
                    {
                        "name": exact["domain"], "type": "A", "disabled": False,
                        "rData": {"ipAddress": exact["ipAddress"]},
                    },
                    {
                        "name": exact["domain"], "type": "A", "disabled": False,
                        "rData": {"ipAddress": "192.168.1.249"},
                    },
                ],
            },
            options={
                zone: {"name": zone, "type": "Primary", "catalog": catalog_zone()}
                for zone in TEST_CONFIG["zones"]
            },
        )

        reconciler.reconcile(api, TEST_CONFIG)

        adds_for_exact_domain = [
            call for call in api.calls
            if call[0] == "POST" and call[1] == "/api/zones/records/add" and call[2]["domain"] == exact["domain"]
        ]
        self.assertEqual(adds_for_exact_domain, [])
        self.assertIn("192.168.1.249", [record["rData"]["ipAddress"] for record in api.records["home.lab"]])

    def test_api_unavailable_stops_before_any_write(self):
        requests = []

        def fail_request(request, timeout):
            requests.append(request)
            raise OSError("connection refused")

        with mock.patch.object(reconciler.urllib.request, "urlopen", side_effect=fail_request):
            api = reconciler.TechnitiumAPI("http://127.0.0.1:5380", "test-secret-token")
            with self.assertRaises(reconciler.ReconcileError):
                reconciler.reconcile(api, TEST_CONFIG)
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].method, "GET")

    def test_invalid_token_api_response_fails_without_writes(self):
        requests = []

        class Response:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b'{"status":"invalid-token"}'

        def fake_urlopen(request, timeout):
            requests.append(request)
            return Response()

        with mock.patch.object(reconciler.urllib.request, "urlopen", side_effect=fake_urlopen):
            api = reconciler.TechnitiumAPI("http://127.0.0.1:5380", "test-secret-token")
            with self.assertRaises(reconciler.ReconcileError):
                reconciler.reconcile(api, TEST_CONFIG)

        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer test-secret-token")
        self.assertNotIn("test-secret-token", requests[0].full_url)

    def test_token_is_not_written_to_standard_output_or_error(self):
        token = "test-secret-token"
        api = FakeAPI()
        stdout = io.StringIO()
        stderr = io.StringIO()
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as credential:
            credential.write(token)
            credential.flush()
            with mock.patch.object(reconciler, "TechnitiumAPI", return_value=api):
                with mock.patch.object(reconciler, "read_config", return_value=TEST_CONFIG):
                    with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                        result = reconciler.main([
                            "--config-file", "generated-config.json",
                            "--token-file", credential.name,
                        ])
        self.assertEqual(result, 0)
        self.assertNotIn(token, stdout.getvalue())
        self.assertNotIn(token, stderr.getvalue())

    def test_json_settings_write_uses_wire_request_and_returns_updated_api_state(self):
        token = "test-secret-token"
        initial_state = {"enableBlocking": False, "blockListUrls": [], "forwarders": ["9.9.9.9"]}
        expected_state = {
            **initial_state,
            "enableBlocking": True,
            "blockListUrls": TEST_CONFIG["blockListUrls"],
        }
        server_state = dict(initial_state)
        captured = []

        class Response:
            def __init__(self, value):
                self.value = value

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return json.dumps(self.value).encode("utf-8")

        def fake_urlopen(request, timeout):
            captured.append(request)
            if request.method == "POST" and request.full_url.endswith("/api/settings/set"):
                self.assertEqual(request.get_header("Content-type"), "application/json")
                server_state.update(json.loads(request.data))
                return Response({"status": "ok"})
            if request.method == "GET" and request.full_url.endswith("/api/settings/get"):
                return Response({"status": "ok", "response": dict(server_state)})
            raise AssertionError(f"Unexpected request {request.method} {request.full_url}")

        with mock.patch.object(reconciler.urllib.request, "urlopen", side_effect=fake_urlopen):
            api = reconciler.TechnitiumAPI("http://127.0.0.1:5380", token)
            write_result = api.post("/api/settings/set", json_body={
                "enableBlocking": True,
                "blockListUrls": TEST_CONFIG["blockListUrls"],
            })
            state_after_write = reconciler.response_object(api.get("/api/settings/get"))

        self.assertEqual(write_result, {"status": "ok"})
        self.assertEqual(state_after_write, expected_state)
        self.assertEqual(len(captured), 2)
        write_request = captured[0]
        self.assertEqual(write_request.get_header("Authorization"), f"Bearer {token}")
        self.assertEqual(json.loads(write_request.data), {
            "enableBlocking": True,
            "blockListUrls": TEST_CONFIG["blockListUrls"],
        })
        self.assertNotIn(token, write_request.full_url)
        self.assertNotIn(token.encode(), write_request.data)
        self.assertNotIn(token, json.dumps({
            "url": write_request.full_url,
            "body": write_request.data.decode("utf-8"),
        }))


if __name__ == "__main__":
    unittest.main()
