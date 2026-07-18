#!/usr/bin/env python3
"""Unit tests for cli-proxy initialization, providers, and Factory sync."""

from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest import mock

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))


def load_script(module_name: str, filename: str):
    spec = importlib.util.spec_from_file_location(module_name, SCRIPTS / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


common = load_script("cli_proxy_common", "cli_proxy_common.py")
proxy_init = load_script("cli_proxy_init", "cli-proxy-init.py")
provider = load_script("cli_proxy_provider", "cli-proxy-provider.py")
sync = load_script("factory_sync_cli_proxy", "factory-sync-cli-proxy.py")


def mode(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


class ProxyInitTests(unittest.TestCase):
    EXAMPLE = """# package comment
host: "" # bind comment
port: 8317
remote-management:
  allow-remote: false
  secret-key: ""
api-keys:
  - "your-api-key-1"
  - "your-api-key-2"
# preserve this comment
unknown-section:
  enabled: true
"""

    def test_init_is_idempotent_private_and_never_prints_secrets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            example = root / "example.yaml"
            config = root / "proxy" / "config.yaml"
            env_file = root / "private" / "proxy.env"
            example.write_text(self.EXAMPLE, encoding="utf-8")
            tokens = iter(("api-secret-value", "management-secret-value"))
            with mock.patch.object(proxy_init, "secure_token", side_effect=lambda: next(tokens)):
                changed = proxy_init.initialize(
                    config_path=config,
                    example_path=example,
                    env_path=env_file,
                    enable_management=True,
                )
            self.assertEqual(changed, (True, True))
            parsed = yaml.safe_load(config.read_text(encoding="utf-8"))
            self.assertEqual(parsed["host"], "127.0.0.1")
            self.assertEqual(parsed["api-keys"], ["api-secret-value"])
            self.assertEqual(
                parsed["remote-management"]["secret-key"], "management-secret-value"
            )
            self.assertTrue(parsed["unknown-section"]["enabled"])
            self.assertIn("# preserve this comment", config.read_text(encoding="utf-8"))
            self.assertEqual(mode(config), 0o600)
            self.assertEqual(mode(env_file), 0o600)
            env_values = common.parse_env_file(env_file)
            self.assertEqual(env_values["CLI_PROXY_API_URL"], "http://127.0.0.1:8317")
            self.assertEqual(env_values["CLI_PROXY_API_KEY"], "api-secret-value")

            with mock.patch.object(proxy_init, "secure_token", side_effect=AssertionError("new key")):
                second = proxy_init.initialize(
                    config_path=config,
                    example_path=example,
                    env_path=env_file,
                    enable_management=True,
                )
            self.assertEqual(second, (False, False))

            output = io.StringIO()
            with redirect_stdout(output), redirect_stderr(output):
                exit_code = proxy_init.main(
                    [
                        "--config",
                        str(config),
                        "--example",
                        str(example),
                        "--env-file",
                        str(env_file),
                        "--management-key",
                    ]
                )
            self.assertEqual(exit_code, 0)
            self.assertNotIn("api-secret-value", output.getvalue())
            self.assertNotIn("management-secret-value", output.getvalue())

    def test_existing_real_api_key_is_reused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            example = root / "example.yaml"
            config = root / "config.yaml"
            env_file = root / "proxy.env"
            example.write_text(self.EXAMPLE, encoding="utf-8")
            config.write_text(
                self.EXAMPLE.replace(
                    '  - "your-api-key-1"\n  - "your-api-key-2"',
                    '  - "existing-real-key"\n  - "another-real-key"',
                ),
                encoding="utf-8",
            )
            with mock.patch.object(proxy_init, "secure_token", side_effect=AssertionError("new key")):
                proxy_init.initialize(
                    config_path=config,
                    example_path=example,
                    env_path=env_file,
                )
            self.assertEqual(
                common.parse_env_file(env_file)["CLI_PROXY_API_KEY"], "existing-real-key"
            )
            parsed = yaml.safe_load(config.read_text(encoding="utf-8"))
            self.assertEqual(parsed["api-keys"], ["existing-real-key", "another-real-key"])

    def test_inline_placeholder_api_keys_are_normalized(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            example = root / "example.yaml"
            config = root / "config.yaml"
            env_file = root / "proxy.env"
            example.write_text(
                'host: ""\nport: 8317\napi-keys: [] # placeholder\n',
                encoding="utf-8",
            )
            with mock.patch.object(proxy_init, "secure_token", return_value="generated-key"):
                proxy_init.initialize(
                    config_path=config,
                    example_path=example,
                    env_path=env_file,
                )
            parsed = yaml.safe_load(config.read_text(encoding="utf-8"))
            self.assertEqual(parsed["api-keys"], ["generated-key"])
            self.assertIn("# placeholder", config.read_text(encoding="utf-8"))

    def test_duplicate_host_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config.yaml"
            config.write_text(
                'host: "127.0.0.1"\nport: 8317\n"host": "0.0.0.0"\n'
                'api-keys:\n  - "existing-key"\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(common.ProxyToolError, "YAML validation failed"):
                proxy_init.initialize(
                    config_path=config,
                    example_path=root / "unused.yaml",
                    env_path=root / "proxy.env",
                )
            self.assertFalse((root / "proxy.env").exists())


class CommonHelperTests(unittest.TestCase):
    def test_yaml_validation_rejects_duplicate_nested_keys(self) -> None:
        with self.assertRaisesRegex(common.ProxyToolError, "YAML validation failed"):
            common.validate_yaml_text(
                "claude-api-key:\n"
                "  - api-key: first\n"
                "    base-url: https://one.example\n"
                '    "base-url": https://two.example\n'
            )

    def test_expected_content_prevents_overwriting_a_racing_writer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "settings.json"
            path.write_text("old\n", encoding="utf-8")

            def racing_backup(_path):
                path.write_text("external\n", encoding="utf-8")
                return None

            with mock.patch.object(common, "backup_file", side_effect=racing_backup):
                with self.assertRaisesRegex(common.ProxyToolError, "changed during"):
                    common.write_if_changed(
                        path,
                        "managed\n",
                        expected_content="old\n",
                    )
            self.assertEqual(path.read_text(encoding="utf-8"), "external\n")

    def test_backup_retention_keeps_newest_three_private_backups(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "proxy.env"
            path.write_text("fixture-secret-version-0\n", encoding="utf-8")
            output = io.StringIO()
            with redirect_stdout(output), redirect_stderr(output):
                for version in range(1, 6):
                    common.write_if_changed(
                        path,
                        f"fixture-secret-version-{version}\n",
                    )
            backups = sorted(path.parent.glob("proxy.env.bak.*"))
            self.assertEqual(len(backups), common.BACKUP_RETENTION_COUNT)
            self.assertEqual(
                [backup.read_text(encoding="utf-8") for backup in backups],
                [
                    "fixture-secret-version-2\n",
                    "fixture-secret-version-3\n",
                    "fixture-secret-version-4\n",
                ],
            )
            self.assertTrue(all(mode(backup) == 0o600 for backup in backups))
            self.assertNotIn("fixture-secret", output.getvalue())

    def test_failed_destination_write_does_not_prune_backups(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "config.yaml"
            path.write_text("old\n", encoding="utf-8")
            existing = set()
            for index in range(4):
                backup = path.with_name(
                    f"config.yaml.bak.20000101T00000{index}.000000Z"
                )
                backup.write_text(f"backup-{index}\n", encoding="utf-8")
                existing.add(backup)

            with mock.patch.object(
                common,
                "atomic_write",
                side_effect=common.ProxyToolError("simulated destination failure"),
            ):
                with self.assertRaisesRegex(
                    common.ProxyToolError, "simulated destination failure"
                ):
                    common.write_if_changed(path, "new\n")

            self.assertTrue(all(backup.exists() for backup in existing))
            self.assertGreaterEqual(
                len(list(path.parent.glob("config.yaml.bak.*"))),
                len(existing),
            )

    def test_failed_backup_pruning_warns_after_successful_write(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "proxy.env"
            path.write_text("old-fixture-secret\n", encoding="utf-8")
            output = io.StringIO()

            with mock.patch.object(
                common,
                "prune_generated_backups",
                side_effect=common.ProxyToolError("fixture-secret cleanup failure"),
            ), redirect_stderr(output):
                changed = common.write_if_changed(path, "new-fixture-secret\n")

            self.assertTrue(changed)
            self.assertEqual(path.read_text(encoding="utf-8"), "new-fixture-secret\n")
            self.assertIn("WARNING:", output.getvalue())
            self.assertNotIn("fixture-secret", output.getvalue())

    def test_backup_pruning_ignores_symlinks_directories_and_similar_names(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "config.yaml"
            path.write_text("old\n", encoding="utf-8")
            symlink_target = root / "symlink-target"
            symlink_target.write_text("keep\n", encoding="utf-8")
            symlink = root / "config.yaml.bak.20000101T000001.000000Z"
            symlink.symlink_to(symlink_target)
            directory = root / "config.yaml.bak.20000101T000002.000000Z"
            directory.mkdir()
            similarly_prefixed = root / "config.yaml-extra.bak.20000101T000003.000000Z"
            similarly_prefixed.write_text("keep\n", encoding="utf-8")
            suffixed = root / "config.yaml.bak.20000101T000004.000000Z.extra"
            suffixed.write_text("keep\n", encoding="utf-8")
            for index in range(3, 7):
                generated = root / f"config.yaml.bak.20000101T00000{index}.000000Z"
                generated.write_text(f"generated-{index}\n", encoding="utf-8")

            common.write_if_changed(path, "new\n")

            self.assertTrue(symlink.is_symlink())
            self.assertTrue(directory.is_dir())
            self.assertEqual(symlink_target.read_text(encoding="utf-8"), "keep\n")
            self.assertTrue(similarly_prefixed.is_file())
            self.assertTrue(suffixed.is_file())
            regular_exact = [
                candidate
                for candidate in root.glob("config.yaml.bak.*")
                if candidate.is_file() and not candidate.is_symlink()
                and common._BACKUP_TIMESTAMP_PATTERN.fullmatch(
                    candidate.name.removeprefix("config.yaml.bak.")
                )
            ]
            self.assertEqual(len(regular_exact), common.BACKUP_RETENTION_COUNT)

    def test_env_update_removes_stale_duplicate_assignments(self) -> None:
        updated = common.update_env_text(
            "export KEEP=1\nexport CLI_PROXY_API_KEY=old\n"
            "CLI_PROXY_API_KEY=stale\n",
            {"CLI_PROXY_API_KEY": "new"},
        )
        self.assertEqual(updated.count("CLI_PROXY_API_KEY="), 1)
        with tempfile.TemporaryDirectory() as temporary:
            env_file = Path(temporary) / "proxy.env"
            env_file.write_text(updated, encoding="utf-8")
            self.assertEqual(common.parse_env_file(env_file)["CLI_PROXY_API_KEY"], "new")


class ProviderTests(unittest.TestCase):
    def test_factory_key_migration_and_private_env_persistence(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            settings = root / "settings.json"
            env_file = root / "proxy.env"
            settings.write_text(
                json.dumps(
                    {
                        "customModels": [
                            {
                                "model": "glm-5.2",
                                "baseUrl": provider.ZAI_BASE_URL,
                                "apiKey": "migrated-zai-key",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )
            api_key = provider.resolve_zai_key(
                env_name="ZAI_API_KEY",
                env_path=env_file,
                settings_path=settings,
                allow_prompt=False,
                gum="gum",
            )
            self.assertEqual(api_key, "migrated-zai-key")
            self.assertTrue(provider.persist_zai_key(env_file, "ZAI_API_KEY", api_key))
            self.assertEqual(mode(env_file), 0o600)
            self.assertEqual(
                common.parse_env_file(env_file)["ZAI_API_KEY"], "migrated-zai-key"
            )
            self.assertFalse(provider.persist_zai_key(env_file, "ZAI_API_KEY", api_key))

    def test_zai_upsert_preserves_user_entries_comments_and_unknown_keys(self) -> None:
        source = """# top comment
host: "127.0.0.1"
claude-api-key:
  - api-key: "user-owned-secret"
    # direct user-owned Z.AI entry; must remain
    base-url: "https://api.z.ai/api/anthropic"
    custom-setting: true
  - api-key: "old-owned-secret"
    # team-dotfiles-managed: zai
    base-url: "https://old.invalid"
    models:
      - name: "glm-5.2"
        alias: "old-alias"
  - api-key: "duplicate-owned-secret"
    # team-dotfiles-managed: zai
    base-url: "https://duplicate.invalid"
unknown-after:
  keep: yes # trailing comment
"""
        updated = provider.upsert_zai_text(source, "new-secret")
        updated_again = provider.upsert_zai_text(updated, "new-secret")
        self.assertEqual(updated, updated_again)
        self.assertEqual(updated.count(provider.OWNED_MARKER), 1)
        self.assertIn("# top comment", updated)
        self.assertIn("# direct user-owned Z.AI entry; must remain", updated)
        self.assertIn("# trailing comment", updated)
        parsed = yaml.safe_load(updated)
        entries = parsed["claude-api-key"]
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["api-key"], "user-owned-secret")
        self.assertTrue(entries[0]["custom-setting"])
        owned = entries[1]
        self.assertEqual(owned["api-key"], "new-secret")
        self.assertEqual(owned["base-url"], provider.ZAI_BASE_URL)
        self.assertIn({"name": "glm-5.2", "alias": "glm-5.2"}, owned["models"])
        self.assertIs(parsed["unknown-after"]["keep"], True)

    def test_alias_only_model_mapping_remains_one_preserved_item(self) -> None:
        source = """claude-api-key:
  - api-key: "old-owned-secret"
    # team-dotfiles-managed: zai
    base-url: "https://old.invalid"
    models:
      - alias: "glm-5.2" # keep model comment
        unknown-setting: true # keep unknown comment
"""
        updated = provider.upsert_zai_text(source, "new-secret")
        parsed_models = yaml.safe_load(updated)["claude-api-key"][0]["models"]
        self.assertEqual(len(parsed_models), 1)
        self.assertEqual(parsed_models[0]["name"], provider.ZAI_MODEL)
        self.assertEqual(parsed_models[0]["alias"], provider.ZAI_MODEL)
        self.assertTrue(parsed_models[0]["unknown-setting"])
        self.assertIn("# keep model comment", updated)
        self.assertIn("# keep unknown comment", updated)
        self.assertEqual(updated.count("      - "), 1)
        self.assertEqual(provider.upsert_zai_text(updated, "new-secret"), updated)

    def test_name_only_model_mapping_gains_child_alias(self) -> None:
        source = """claude-api-key:
  - api-key: "old-owned-secret"
    # team-dotfiles-managed: zai
    base-url: "https://old.invalid"
    models:
      - name: "glm-5.2" # preserve name comment
        extra-field: "kept"
"""
        updated = provider.upsert_zai_text(source, "new-secret")
        parsed_models = yaml.safe_load(updated)["claude-api-key"][0]["models"]
        self.assertEqual(
            parsed_models,
            [{"name": provider.ZAI_MODEL, "extra-field": "kept", "alias": provider.ZAI_MODEL}],
        )
        self.assertIn("# preserve name comment", updated)
        self.assertEqual(updated.count("      - "), 1)
        self.assertEqual(provider.upsert_zai_text(updated, "new-secret"), updated)

    def test_configure_zai_creates_backup_and_private_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            config = Path(temporary) / "config.yaml"
            config.write_text("host: localhost\n", encoding="utf-8")
            os.chmod(config, 0o644)
            self.assertTrue(provider.configure_zai(config, "private-test-key"))
            self.assertEqual(mode(config), 0o600)
            self.assertEqual(len(list(config.parent.glob("config.yaml.bak.*"))), 1)
            self.assertFalse(provider.configure_zai(config, "private-test-key"))

    def test_inline_empty_models_are_normalized(self) -> None:
        source = """claude-api-key:
  - api-key: "old-owned-secret"
    # team-dotfiles-managed: zai
    base-url: "https://old.invalid"
    models: [] # placeholder
"""
        updated = provider.upsert_zai_text(source, "new-secret")
        parsed = yaml.safe_load(updated)
        self.assertEqual(
            parsed["claude-api-key"][0]["models"],
            [{"name": "glm-5.2", "alias": "glm-5.2"}],
        )
        self.assertIn("# placeholder", updated)


class CatalogAndMergeTests(unittest.TestCase):
    def test_catalog_filters_unsupported_models_and_maps_owners(self) -> None:
        catalog = sync.filter_catalog(
            {
                "data": [
                    {"id": "gpt-5.6-sol", "owned_by": "openai"},
                    {"id": "claude-opus-4-7", "owned_by": "claude"},
                    {"id": "glm-5.2", "owned_by": "anthropic"},
                    {"id": "text-embedding-3-small", "owned_by": "openai"},
                    {"id": "gpt-image-1", "owned_by": "openai"},
                    {"id": "codex-auto-review", "owned_by": "openai"},
                    {"id": "private-model", "owned_by": "internal"},
                ]
            }
        )
        self.assertEqual([model.model for model in catalog], ["claude-opus-4-7", "glm-5.2", "gpt-5.6-sol"])
        self.assertEqual(sync.provider_for(catalog[0]), "anthropic")
        self.assertEqual(sync.provider_for(catalog[-1]), "openai")

    def test_fetch_catalog_checks_health_and_authenticates_models(self) -> None:
        class FakeResponse(io.BytesIO):
            status = 200

        responses = [
            FakeResponse(b'{}'),
            FakeResponse(b'{"data":[{"id":"gpt-5.5","owned_by":"openai"}]}'),
        ]
        requests = []

        def fake_urlopen(request, timeout):
            requests.append((request, timeout))
            return responses.pop(0)

        with mock.patch.object(sync, "urlopen", side_effect=fake_urlopen):
            catalog = sync.fetch_catalog(
                "http://127.0.0.1:8317/v1", "authentication-secret", timeout=2.0
            )
        self.assertEqual([item.model for item in catalog], ["gpt-5.5"])
        self.assertEqual(requests[0][0].full_url, "http://127.0.0.1:8317/healthz")
        self.assertEqual(requests[1][0].full_url, "http://127.0.0.1:8317/v1/models")
        self.assertIsNone(requests[0][0].get_header("Authorization"))
        self.assertEqual(
            requests[1][0].get_header("Authorization"), "Bearer authentication-secret"
        )

    def test_gum_multi_select_preselects_existing_models(self) -> None:
        catalog = [
            sync.CatalogModel("gpt-5.5", "openai"),
            sync.CatalogModel("gpt-5.6-sol", "openai"),
        ]
        completed = mock.Mock(returncode=0, stdout="gpt-5.6-sol\n")
        with (
            mock.patch.object(sync.shutil, "which", return_value="/usr/bin/gum"),
            mock.patch.object(sync.subprocess, "run", return_value=completed) as run,
        ):
            selected = sync.gum_select(catalog, ["gpt-5.5"])
        self.assertEqual(selected, ["gpt-5.6-sol"])
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ["/usr/bin/gum", "choose", "--no-limit"])
        selected_flag = command.index("--selected")
        self.assertEqual(command[selected_flag + 1], "gpt-5.5")

    def test_merge_preserves_unrelated_settings_models_and_overrides(self) -> None:
        old_id = "custom:gpt-5.5-0"
        settings = {
            "unknownSetting": {"keep": True},
            "customModels": [
                {
                    "model": "user/model",
                    "id": "custom:user-model-0",
                    "index": 99,
                    "baseUrl": "https://user.example/v1",
                    "displayName": "User Model",
                },
                {
                    "model": "glm-5.2",
                    "id": "custom:glm-5.2-zai-0",
                    "index": 100,
                    "baseUrl": "https://api.z.ai/api/anthropic",
                    "displayName": "Direct Z.AI",
                },
                {
                    "model": "gpt-5.5",
                    "id": old_id,
                    "index": 101,
                    "baseUrl": "http://127.0.0.1:8317/v1",
                    "displayName": "My GPT",
                    "extraArgs": {"reasoning": {"effort": "medium"}},
                },
            ],
        }
        selected = [
            sync.CatalogModel("gpt-5.5", "openai"),
            sync.CatalogModel("gpt-5.6-sol", "openai"),
        ]
        merged, managed_ids = sync.merge_settings(
            settings,
            selected=selected,
            base_url="http://127.0.0.1:8317/v1",
            api_key="proxy-secret",
            previous_managed_ids={old_id},
        )
        self.assertEqual(merged["unknownSetting"], {"keep": True})
        custom = merged["customModels"]
        self.assertEqual([entry["index"] for entry in custom], list(range(len(custom))))
        self.assertIn("custom:glm-5.2-zai-0", [entry["id"] for entry in custom])
        old = next(entry for entry in custom if entry["id"] == old_id)
        self.assertEqual(old["displayName"], "My GPT")
        self.assertEqual(old["extraArgs"], {"reasoning": {"effort": "medium"}})
        self.assertEqual(managed_ids, [old_id, "custom:gpt-5.6-sol-0"])

    def test_stable_ids_are_deterministic_and_avoid_user_collision(self) -> None:
        self.assertEqual(sync.stable_model_id("Vendor/Model X"), "custom:vendor-model-x-0")
        occupied = {"custom:vendor-model-x-0"}
        self.assertEqual(
            sync.stable_model_id("Vendor/Model X", occupied),
            "custom:vendor-model-x-cli-proxy-0",
        )

    def test_first_run_does_not_adopt_user_owned_proxy_models(self) -> None:
        user_entry = {
            "model": "gpt-5.5",
            "id": "custom:gpt-5.5-0",
            "baseUrl": "http://127.0.0.1:8317/v1",
            "apiKey": "different-user-key",
            "displayName": "User-owned proxy model",
        }
        merged, managed_ids = sync.merge_settings(
            {"customModels": [user_entry]},
            selected=[],
            base_url="http://127.0.0.1:8317/v1",
            api_key="managed-key",
            previous_managed_ids=set(),
            adopt_legacy=True,
        )
        self.assertEqual(merged["customModels"][0]["displayName"], user_entry["displayName"])
        self.assertEqual(managed_ids, [])

    def test_referenced_managed_model_removal_is_refused(self) -> None:
        model_id = "custom:gpt-5.5-0"
        settings = {
            "customModels": [
                {
                    "model": "gpt-5.5",
                    "id": model_id,
                    "baseUrl": "http://127.0.0.1:8317/v1",
                }
            ],
            "modelFavorites": [model_id],
            "missionOrchestratorModel": model_id,
            "missionModelSettings": {"workerModel": model_id},
            "subagentModelSettings": {"heavyModel": model_id},
            "sessionDefaultSettings": {"model": model_id},
        }
        with self.assertRaisesRegex(common.ProxyToolError, "Refusing to remove referenced"):
            sync.merge_settings(
                settings,
                selected=[],
                base_url="http://127.0.0.1:8317/v1",
                api_key="secret",
                previous_managed_ids={model_id},
            )


class SynchronizationTests(unittest.TestCase):
    def test_external_settings_change_is_refused_before_writes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            settings = root / "settings.json"
            state = root / "factory-models.json"
            settings.write_text('{"customModels": []}\n', encoding="utf-8")
            real_signature = sync.file_signature
            settings_checks = 0

            def changing_signature(path):
                nonlocal settings_checks
                if path == settings:
                    settings_checks += 1
                    return (
                        (1, 1, "first")
                        if settings_checks == 1
                        else (2, 2, "changed")
                    )
                return real_signature(path)

            with mock.patch.object(
                sync, "file_signature", side_effect=changing_signature
            ):
                with self.assertRaisesRegex(common.ProxyToolError, "changed during"):
                    sync.synchronize(
                        settings_path=settings,
                        state_path=state,
                        catalog=[sync.CatalogModel("gpt-5.5", "openai")],
                        selected_names=["gpt-5.5"],
                        base_url="http://127.0.0.1:8317/v1",
                        api_key="secret",
                    )
            self.assertFalse(state.exists())

    def test_state_is_rolled_back_when_settings_write_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            settings = root / "settings.json"
            state = root / "factory-models.json"
            settings.write_text('{"customModels": []}\n', encoding="utf-8")
            real_write = sync.write_if_changed
            calls = 0

            def failing_write(path, content, **kwargs):
                nonlocal calls
                calls += 1
                if path == settings:
                    raise OSError("simulated settings failure")
                return real_write(path, content, **kwargs)

            with mock.patch.object(sync, "write_if_changed", side_effect=failing_write):
                with self.assertRaises(OSError):
                    sync.synchronize(
                        settings_path=settings,
                        state_path=state,
                        catalog=[sync.CatalogModel("gpt-5.5", "openai")],
                        selected_names=["gpt-5.5"],
                        base_url="http://127.0.0.1:8317/v1",
                        api_key="secret",
                    )
            self.assertGreaterEqual(calls, 2)
            self.assertFalse(state.exists())
            self.assertEqual(
                json.loads(settings.read_text(encoding="utf-8")), {"customModels": []}
            )

    def test_synchronize_writes_private_settings_and_state(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            settings = root / "settings.json"
            state = root / "factory-models.json"
            settings.write_text('{"customModels": [], "keep": 1}\n', encoding="utf-8")
            os.chmod(settings, 0o644)
            changed = sync.synchronize(
                settings_path=settings,
                state_path=state,
                catalog=[sync.CatalogModel("gpt-5.5", "openai")],
                selected_names=["gpt-5.5"],
                base_url="http://127.0.0.1:8317/v1",
                api_key="do-not-print-me",
            )
            self.assertEqual(changed, (True, True, 1))
            self.assertEqual(mode(settings), 0o600)
            self.assertEqual(mode(state), 0o600)
            self.assertEqual(json.loads(settings.read_text())["keep"], 1)

    def test_noninteractive_fixture_selection_uses_curated_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config.yaml"
            fixture = root / "models.json"
            settings = root / "settings.json"
            state = root / "factory-models.json"
            env_file = root / "missing.env"
            config.write_text(
                'host: "127.0.0.1"\nport: 8317\napi-keys:\n  - "fixture-proxy-secret"\n',
                encoding="utf-8",
            )
            fixture.write_text(
                json.dumps(
                    {
                        "data": [
                            {"id": "gpt-5.5", "owned_by": "openai"},
                            {"id": "gpt-5.6-sol", "owned_by": "openai"},
                            {"id": "glm-5.2", "owned_by": "anthropic"},
                            {"id": "text-embedding-3-small", "owned_by": "openai"},
                        ]
                    }
                ),
                encoding="utf-8",
            )
            settings.write_text(
                json.dumps(
                    {
                        "keep": "unchanged",
                        "customModels": [
                            {
                                "id": "custom:user-0",
                                "model": "user-model",
                                "index": 8,
                                "baseUrl": "https://user.example/v1",
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            output = io.StringIO()
            with redirect_stdout(output), redirect_stderr(output):
                exit_code = sync.main(
                    [
                        "--config",
                        str(config),
                        "--env-file",
                        str(env_file),
                        "--models-file",
                        str(fixture),
                        "--settings",
                        str(settings),
                        "--state",
                        str(state),
                        "--non-interactive",
                        "--yes",
                    ]
                )
            self.assertEqual(exit_code, 0, output.getvalue())
            self.assertNotIn("fixture-proxy-secret", output.getvalue())
            saved_state = json.loads(state.read_text(encoding="utf-8"))
            self.assertEqual(
                saved_state["selectedModels"], ["gpt-5.5", "gpt-5.6-sol", "glm-5.2"]
            )
            saved_settings = json.loads(settings.read_text(encoding="utf-8"))
            self.assertEqual(saved_settings["keep"], "unchanged")
            self.assertIn("custom:user-0", [item["id"] for item in saved_settings["customModels"]])
            glm = next(item for item in saved_settings["customModels"] if item["model"] == "glm-5.2")
            self.assertEqual(glm["provider"], "anthropic")
            self.assertEqual(glm["extraArgs"]["reasoning"] if "reasoning" in glm["extraArgs"] else glm["extraArgs"]["effort"], "high")


if __name__ == "__main__":
    unittest.main()
