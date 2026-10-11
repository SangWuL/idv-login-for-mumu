"""Offline coverage for saved channel scans; never opens Qt, ADB or real accounts."""
import base64
import importlib.util
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs

import requests

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))


def load_source(name, filename):
    spec = importlib.util.spec_from_file_location(name, SRC / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Environment:
    def __init__(self):
        self.values = {}

    def get(self, key, default=None):
        return self.values.get(key, default)

    def set(self, key, value, *args, **kwargs):
        self.values[key] = value


class SavedScanTests(unittest.TestCase):
    def setUp(self):
        self.env = Environment()
        self.logger = Mock()
        self.app = types.ModuleType("app_state")
        self.app.toast = Mock()
        self.app.run_on_main_thread = Mock()
        utils = types.ModuleType("channelHandler.channelUtils")
        utils.getShortGameId = lambda value: value.split("-")[-1]
        utils.cmp_game_id = lambda a, b: utils.getShortGameId(a) == utils.getShortGameId(b)
        self.modules = patch.dict(sys.modules, {
            "envmgr": types.SimpleNamespace(genv=self.env),
            "logutil": types.SimpleNamespace(setup_logger=lambda: self.logger),
            "const": types.SimpleNamespace(manual_login_channels=[]),
            "ssl_utils": types.SimpleNamespace(should_verify_ssl=lambda: True),
            "app_state": self.app,
            "channelHandler.channelUtils": utils,
            "mitmproxy": types.SimpleNamespace(http=types.SimpleNamespace(HTTPFlow=object)),
        })
        self.modules.start()
        self.addCleanup(self.modules.stop)
        # Other legacy tests install process-global stubs. Load these real modules
        # privately and restore their dependency slots after every test.
        sys.modules["channel_cache"] = load_source("scan_cache_under_test", "channel_cache.py")
        self.cm = load_source("scan_channels_under_test", "channelmgr.py")
        self.addon_module = load_source("scan_addon_under_test", "mitm_addon.py")
        self.manager = self.cm.ChannelManager.__new__(self.cm.ChannelManager)
        self.manager.channels = []
        self.manager.db_sync = None
        self.manager.logger = self.logger
        self.manager.save_records = Mock()
        self.app.channels_helper = self.manager
        self.record = self.make_record()
        self.manager.channels.append(self.record)
        self.get = patch.object(self.cm.requests, "get").start()
        self.post = patch.object(self.cm.requests, "post").start()
        self.addCleanup(patch.stopall)
        self.get.return_value = self.response({})
        self.post.return_value = self.response({})

    def make_record(self, *, pc=True, game="g37"):
        auth = {"gameid": game, "login_channel": "myapp", "sdkuid": "fake-sdk-user"}
        ext = {
            "from_game_id": game, "src_jf_game_id": game,
            "src_sdk_version": "test-sdk", "src_app_channel2": "myapp",
            "src_app_channel": "myapp", "src_pay_channel": "myapp",
            "src_udid": "fake-device",
            "extra_unisdk_data": json.dumps({
                "SAUTH_JSON": base64.b64encode(json.dumps(auth).encode()).decode(),
                "test": "a+b&c=d% /",
            }),
        }
        user = {"id": "fake-mpay-user", "token": "fake+token/&=% value", "login_channel": "myapp"}
        if pc:
            user["pc_ext_info"] = ext
        record = self.cm.channel({"login_channel": "myapp", "code": "fake-one-shot-code"},
                                 user, {} if pc else ext, name="test scan")
        return record

    @staticmethod
    def response(payload):
        response = Mock(status_code=200)
        response.json.return_value = payload
        return response

    def test_pc_ext_info_and_legacy_ext_packets(self):
        for pc in (True, False):
            with self.subTest(pc=pc):
                record = self.make_record(pc=pc)
                packet = record.request_unisdk("some-prefix-g37", interactive=False)
                self.assertEqual(record.game_id, "g37")
                self.assertEqual(packet["sdk_version"], "test-sdk")
                self.assertEqual(packet["jf_game_id"], "g37")
                self.assertEqual(packet["token"], record.user_info["token"])

    def test_scan_import_persists_and_refresh_preserves_default(self):
        policy = Mock()
        account_policy = types.SimpleNamespace(
            native_scan_channels=lambda game: [], AccountListPolicy=lambda manager: policy)
        self.manager.channels = []
        self.manager._manual_channel_name = Mock(return_value="")
        snapshots = []
        self.manager.save_records.side_effect = lambda: snapshots.append(
            json.loads(json.dumps([vars(record) for record in self.manager.channels])))
        with patch.dict(sys.modules, {"account_list_policy": account_policy}):
            self.assertTrue(self.manager.import_from_scan(
                self.record.login_info, self.record.exchange_data, "prefix-g37"))
            saved_uuid = self.manager.channels[0].uuid
            restored = self.cm.channel.from_dict(snapshots[-1][0])
            self.assertEqual(restored.record_source, "scan")
            self.assertEqual(restored.game_id, "g37")
            self.assertEqual(restored.request_unisdk("g37")["token"], self.record.user_info["token"])
            self.assertEqual(self.env.get("auto-g37"), saved_uuid)
            refreshed = self.make_record()
            refreshed.login_info["code"] = "different-one-shot-code"
            refreshed.user_info["token"] = "refreshed-fake-token"
            self.assertTrue(self.manager.import_from_scan(
                refreshed.login_info, refreshed.exchange_data, "g37"))
        self.assertEqual(len(self.manager.channels), 1)
        self.assertEqual(self.manager.channels[0].uuid, self.env.get("auto-g37"))
        self.assertEqual(snapshots[-1][0]["user_info"]["token"], "refreshed-fake-token")
        self.assertEqual(policy.include_logged_in.call_count, 2)

    def test_dictionary_extra_is_serialized_as_json(self):
        ext = self.record.user_info["pc_ext_info"]
        ext["extra_unisdk_data"] = json.loads(ext["extra_unisdk_data"])
        packet = self.record.request_unisdk("g37")
        self.assertIsInstance(packet["extra_unisdk_data"], str)
        self.assertEqual(json.loads(packet["extra_unisdk_data"]), ext["extra_unisdk_data"])

    def test_empty_token_is_rejected_without_network(self):
        self.record.user_info["token"] = ""
        self.assertIs(self.manager.simulate_scan(self.record.uuid, "qr", "g37"), False)
        self.get.assert_not_called()
        self.post.assert_not_called()

    def test_pc_ext_takes_precedence(self):
        self.record.ext_info = {"src_sdk_version": "old"}
        self.assertEqual(self.record.request_unisdk("g37")["sdk_version"], "test-sdk")

    def test_form_encoding_preserves_credentials(self):
        self.env.set("CHANNEL_ACCOUNT_SELECTED", self.record.uuid)
        self.assertEqual(self.manager.simulate_scan(self.record.uuid, "fresh-qr", "g37"), {})
        kwargs = self.post.call_args.kwargs
        self.assertIsInstance(kwargs["data"], dict)
        prepared = requests.Request("POST", "https://example.invalid", data=kwargs["data"]).prepare()
        body = parse_qs(prepared.body)
        self.assertEqual(body["token"], [self.record.user_info["token"]])
        self.assertEqual(body["extra_unisdk_data"], [self.record.get_uniSdk_data()["extra_unisdk_data"]])
        self.assertEqual(body["uuid"], ["fresh-qr"])
        self.assertNotIn("fake-one-shot-code", prepared.body)
        self.assertEqual(kwargs["timeout"], (5, 20))
        self.assertEqual(self.get.call_args.kwargs["timeout"], (5, 20))

    def test_expired_and_wrong_game_rejected_before_network(self):
        for field in ("expires", "expire", "record_expiry", "wrong_game"):
            with self.subTest(field=field):
                record = self.make_record(game="h55" if field == "wrong_game" else "g37")
                if field == "record_expiry":
                    record.expires_at = 1
                elif field != "wrong_game":
                    record.user_info[field] = 1
                self.manager.channels = [record]
                self.env.set("CHANNEL_ACCOUNT_SELECTED", record.uuid)
                self.assertIs(self.manager.simulate_scan(record.uuid, "qr", "g37"), False)
                self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), "")
        self.get.assert_not_called()
        self.post.assert_not_called()

    def test_scan_business_error_does_not_confirm(self):
        self.get.return_value = self.response({"code": 1234, "reason": "fake-secret"})
        done = Mock()
        self.assertIs(self.manager.simulate_scan(self.record.uuid, "qr", "g37", on_complete=done), False)
        done.assert_called_once_with(False)
        self.post.assert_not_called()
        self.assertNotIn("fake-secret", str(self.logger.mock_calls))
        self.assertNotIn("fake-one-shot-code", str(self.logger.mock_calls))

    def test_confirm_business_error_is_failure(self):
        self.post.return_value = self.response({"code": 1234})
        self.env.set("CHANNEL_ACCOUNT_SELECTED", self.record.uuid)
        done = Mock()
        self.manager.simulate_scan(self.record.uuid, "qr", "g37", on_complete=done)
        done.assert_called_once_with(False)
        self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), "")

    def test_1424_retry_is_bounded_and_validated(self):
        self.get.side_effect = [self.response({"code": 1424, "game": {"id": "prefix-g37"}}),
                                self.response({"code": 999})]
        self.assertIs(self.manager.simulate_scan(self.record.uuid, "qr", "g37"), False)
        self.assertEqual(self.get.call_count, 2)
        self.assertEqual(self.get.call_args.kwargs["timeout"], (5, 20))
        self.post.assert_not_called()

    def test_1424_retry_success_confirms_resolved_game(self):
        self.get.side_effect = [self.response({"code": 1424, "game": {"id": "prefix-g37"}}),
                                self.response({})]
        self.assertEqual(self.manager.simulate_scan(self.record.uuid, "qr", "g37"), {})
        self.assertEqual(self.post.call_args.kwargs["data"]["game_id"], "prefix-g37")

    def test_network_failure_allows_manual_scan(self):
        self.get.side_effect = requests.Timeout("fake-secret-url")
        self.env.set("CHANNEL_ACCOUNT_SELECTED", self.record.uuid)
        self.assertIs(self.manager.simulate_scan(self.record.uuid, "qr", "g37"), False)
        self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), "")
        self.assertNotIn("fake-secret-url", str(self.logger.mock_calls))

    def test_malformed_confirmation_is_not_success(self):
        for payload in ([], None, "unexpected"):
            self.post.return_value = self.response(payload)
            self.assertIs(self.manager.simulate_scan(self.record.uuid, "qr", "g37"), False)

    def test_cancelled_qr_never_scans(self):
        self.manager.simulate_scan(self.record.uuid, "qr", "g37", is_current=lambda: False)
        self.get.assert_not_called()
        self.post.assert_not_called()

    def test_qr_refresh_during_scan_does_not_confirm_or_clear_new_selection(self):
        current = [True]
        def refresh(*args, **kwargs):
            current[0] = False
            self.env.set("CHANNEL_ACCOUNT_SELECTED", "new-selection")
            return self.response({})
        self.get.side_effect = refresh
        done = Mock()
        self.manager.simulate_scan(self.record.uuid, "qr", "g37", on_complete=done,
                                   is_current=lambda: current[0])
        self.post.assert_not_called()
        done.assert_not_called()
        self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), "new-selection")

    def setup_auto(self):
        addon = self.addon_module.IDVLoginAddon.__new__(self.addon_module.IDVLoginAddon)
        addon.genv = self.env
        addon.logger = self.logger
        addon.game_helper = Mock()
        addon.game_helper.get_login_delay.return_value = 0
        addon._auto_scan_generation = object()
        addon._auto_scan_ticket = None
        addon.ui_manager = None
        addon.stack_mgr = Mock()
        self.env.set("auto-g37", self.record.uuid)
        return addon

    def test_scan_auto_login_runs_in_worker_not_qt(self):
        addon = self.setup_auto()
        with patch.object(self.addon_module.threading, "Thread") as thread:
            addon._schedule_auto_scan({"uuid": "fresh-qr", "game_id": "prefix-g37"}, "g37")
            thread.call_args.kwargs["target"]()
        self.app.run_on_main_thread.assert_not_called()
        self.assertEqual(self.post.call_count, 1)
        self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), self.record.uuid)
        self.assertNotIn("自动登录成功", str(self.logger.mock_calls))

    def test_changed_qr_default_or_record_cancels_delayed_auto_login(self):
        for change in ("qr", "default", "record", "manual_choice"):
            with self.subTest(change=change):
                self.manager.channels = [self.record]
                self.env.set("CHANNEL_ACCOUNT_SELECTED", "")
                addon = self.setup_auto()
                with patch.object(self.addon_module.threading, "Thread") as thread:
                    addon._schedule_auto_scan({"uuid": "qr", "game_id": "g37"}, "g37")
                    if change == "qr":
                        addon._auto_scan_generation = object()
                    elif change == "default":
                        self.env.set("auto-g37", "")
                    elif change == "record":
                        self.manager.channels = []
                    else:
                        self.env.set("CHANNEL_ACCOUNT_SELECTED", "user-selected-another")
                    thread.call_args.kwargs["target"]()
        self.get.assert_not_called()
        self.post.assert_not_called()

    def test_invalid_default_leaves_manual_scan_available(self):
        addon = self.setup_auto()
        self.record.expires_at = 1
        with patch.object(self.addon_module.threading, "Thread") as thread:
            addon._schedule_auto_scan({"uuid": "qr", "game_id": "g37"}, "g37")
            thread.assert_not_called()
        self.assertFalse(self.env.get("CHANNEL_ACCOUNT_SELECTED"))

    def test_auto_failure_clears_selection(self):
        addon = self.setup_auto()
        self.post.return_value = self.response({"code": 999})
        with patch.object(self.addon_module.threading, "Thread") as thread:
            addon._schedule_auto_scan({"uuid": "qr", "game_id": "g37"}, "g37")
            thread.call_args.kwargs["target"]()
        self.assertEqual(self.env.get("CHANNEL_ACCOUNT_SELECTED"), "")

    def test_manual_adapter_still_uses_qt_dispatch(self):
        addon = self.setup_auto()
        self.record.record_source = "manual"
        with patch.object(self.addon_module.threading, "Thread") as thread:
            addon._schedule_auto_scan({"uuid": "qr", "game_id": "g37"}, "g37")
            thread.call_args.kwargs["target"]()
        self.app.run_on_main_thread.assert_called_once()
        self.get.assert_not_called()
        self.post.assert_not_called()

    def test_default_routes_normalize_long_game_id(self):
        dependencies = {
            "cloudSync": types.SimpleNamespace(CloudSyncManager=object),
            "cloudRes": types.SimpleNamespace(CloudRes=object),
        }
        with patch.dict(sys.modules, dependencies):
            module = load_source("scan_local_handler_under_test", "local_handler.py")
        handler = module.LocalRequestHandler.__new__(module.LocalRequestHandler)
        handler.logger = self.logger
        handler._json_response = lambda status, data: (status, data)
        args = {"game_id": "prefix-g37", "uuid": self.record.uuid}
        self.assertEqual(handler._set_default(args, None, "GET"), (200, {"success": True}))
        self.assertEqual(self.env.get("auto-g37"), self.record.uuid)
        self.assertEqual(handler._get_default_channel(args, None, "GET"), (200, {"uuid": self.record.uuid}))
        handler._clear_default(args, None, "GET")
        self.assertEqual(self.env.get("auto-g37"), "")

    def test_create_login_without_scanner_list_and_duplicate_ticket(self):
        addon = self.setup_auto()
        flow = types.SimpleNamespace(
            request=types.SimpleNamespace(query={"game_id": "prefix-g37"}),
            response=types.SimpleNamespace(content=json.dumps({"uuid": "fresh-qr"}).encode()))
        with patch.object(self.addon_module.threading, "Thread") as thread:
            addon._modify_create_login_response(flow)
            addon._modify_create_login_response(flow)
            self.assertEqual(thread.call_count, 1)
        self.assertEqual(json.loads(flow.response.content)["uuid"], "fresh-qr")
        self.logger.exception.assert_not_called()

    def test_real_scan_cancels_delayed_auto_and_is_captured(self):
        addon = self.setup_auto()
        flow = types.SimpleNamespace(
            request=types.SimpleNamespace(query={"game_id": "g37", "process_id": "p"}),
            response=types.SimpleNamespace(content=json.dumps({
                "qrcode": {"status": 2}, "login_info": {"code": "fake-code"}}).encode()))
        generation = addon._auto_scan_generation
        addon._handle_qrcode_query_response(flow)
        self.assertIsNot(addon._auto_scan_generation, generation)
        addon.stack_mgr.push_pending_login_info.assert_called_once_with("g37", "p", {"code": "fake-code"})


if __name__ == "__main__":
    unittest.main()
