"""Exercise real ZIP packaging and backup hooks with a fake remote transport."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]


class UploadTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sidecar-upload-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.backup = self.root / "completed backup"
        self.backup.mkdir()
        (self.backup / "data.ibd").write_bytes(b"database data\x00\x01")
        (self.backup / ".hidden").write_text("hidden data")
        (self.backup / "empty").mkdir()
        self.checkpoint = self.backup / "xtrabackup_checkpoints"
        self.checkpoint.write_text("backup_type = full-backuped\nto_lsn = 100\n")
        self.env = dict(PATH=f"{self.bin}:/usr/bin:/bin", HOME=str(self.root), HOSTNAME="test-host",
                        UPLOAD_DESTINATION="testremote:bucket/prefix", UPLOAD_PROJECT_NAME="myproject",
                        UPLOAD_TMP_DIR=str(self.root / "staging"), CAPTURE=str(self.root / "capture.json"))
        self.write_tool("rclone", '''#!/usr/bin/python3
import json, os, pathlib, sys, zipfile
args = sys.argv[1:]
archive = pathlib.Path(args[1])
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names = z.namelist()
config = {k: v for k, v in os.environ.items() if k.startswith('RCLONE_CONFIG_SIDECAR_GCS_')}
pathlib.Path(os.environ['CAPTURE']).write_text(json.dumps({'args': args, 'config': config, 'entries': names}))
sys.exit(int(os.environ.get('RCLONE_EXIT', '0')))
''')

    def write_tool(self, name, content):
        path = self.bin / name
        path.write_text(content)
        path.chmod(0o755)

    def upload(self, status="succeed"):
        return subprocess.run(["bash", str(ROOT / "modules/upload.sh"), status, "", str(self.backup)],
                              env=self.env, capture_output=True, text=True)

    def captured(self):
        return json.loads(Path(self.env["CAPTURE"]).read_text())

    def assert_no_upload(self):
        self.assertFalse(Path(self.env["CAPTURE"]).exists())

    def test_zip_contents_and_legacy_object_name(self):
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.captured()
        self.assertEqual(data["args"][0], "copyto")
        self.assertRegex(data["args"][2], r"^testremote:bucket/prefix/myproject/\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z_myproject\.zip$")
        self.assertIn("--no-check-dest", data["args"])
        self.assertIn("--no-traverse", data["args"])
        self.assertEqual(set(data["entries"]), {"data.ibd", ".hidden", "empty/", "xtrabackup_checkpoints"})
        self.assertFalse(Path(data["args"][1]).exists())
        self.assertEqual(list((self.root / "staging").iterdir()), [])

    def test_legacy_gs_settings(self):
        self.env.pop("UPLOAD_DESTINATION")
        self.env.pop("UPLOAD_PROJECT_NAME")
        self.env.update(GS_BUCKET_NAME="existing-bucket", GS_PROJECT_NAME="existing-project",
                        GS_KEY_FILE="/run/secrets/gs_key_file")
        result = self.upload()
        self.assertEqual(result.returncode, 0, result.stderr)
        data = self.captured()
        self.assertTrue(data["args"][2].startswith("sidecar_gcs:existing-bucket/existing-project/"))
        self.assertEqual(data["config"]["RCLONE_CONFIG_SIDECAR_GCS_SERVICE_ACCOUNT_FILE"], "/run/secrets/gs_key_file")
        self.assertEqual(data["config"]["RCLONE_CONFIG_SIDECAR_GCS_NO_CHECK_BUCKET"], "true")
        self.assertEqual(data["config"]["RCLONE_CONFIG_SIDECAR_GCS_BUCKET_POLICY_ONLY"], "true")

    def test_legacy_gs_can_use_runtime_credentials(self):
        self.env.pop("UPLOAD_DESTINATION")
        self.env["GS_BUCKET_NAME"] = "existing-bucket"
        self.assertEqual(self.upload().returncode, 0)
        self.assertEqual(self.captured()["config"]["RCLONE_CONFIG_SIDECAR_GCS_ENV_AUTH"], "true")

    def test_explicit_destination_overrides_legacy_bucket(self):
        self.env.update(GS_BUCKET_NAME="ignored", GS_KEY_FILE="ignored")
        self.assertEqual(self.upload().returncode, 0)
        self.assertEqual(self.captured()["config"], {})

    def test_remote_root_preserves_relative_path_semantics(self):
        self.env["UPLOAD_DESTINATION"] = "testremote:"
        self.assertEqual(self.upload().returncode, 0)
        self.assertTrue(self.captured()["args"][2].startswith("testremote:myproject/"))

    def test_full_only_supports_both_checkpoint_names(self):
        for name in ("xtrabackup_checkpoints", "mariadb_backup_checkpoints"):
            with self.subTest(name=name):
                self.checkpoint.rename(self.backup / name)
                self.checkpoint = self.backup / name
                self.env["UPLOAD_FULLBACKUPS_ONLY"] = "true"
                self.assertEqual(self.upload().returncode, 0)
                Path(self.env["CAPTURE"]).unlink()
                self.checkpoint.write_text("backup_type = incremental\nto_lsn = 200\n")
                self.assertEqual(self.upload().returncode, 0)
                self.assert_no_upload()
                self.checkpoint.write_text("backup_type = full-backuped\nto_lsn = 100\n")

    def test_legacy_full_only_and_generic_override(self):
        self.checkpoint.write_text("backup_type = incremental\n")
        self.env["GS_FULLBACKUPS_ONLY"] = "true"
        self.assertEqual(self.upload().returncode, 0)
        self.assert_no_upload()
        self.env["UPLOAD_FULLBACKUPS_ONLY"] = "false"
        self.assertEqual(self.upload().returncode, 0)
        self.assertTrue(Path(self.env["CAPTURE"]).exists())

    def test_missing_checkpoint_fails_when_full_only(self):
        self.checkpoint.unlink()
        self.env["UPLOAD_FULLBACKUPS_ONLY"] = "true"
        self.assertNotEqual(self.upload().returncode, 0)
        self.assert_no_upload()

    def test_failed_backup_is_not_uploaded(self):
        self.assertNotEqual(self.upload("failed").returncode, 0)
        self.assert_no_upload()

    def test_missing_destination_fails_clearly(self):
        self.env.pop("UPLOAD_DESTINATION")
        result = self.upload()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("set UPLOAD_DESTINATION or GS_BUCKET_NAME", result.stderr)
        self.assert_no_upload()

    def test_invalid_full_only_setting_fails(self):
        self.env["UPLOAD_FULLBACKUPS_ONLY"] = "invalid"
        self.assertNotEqual(self.upload().returncode, 0)
        self.assert_no_upload()

    def test_upload_failure_propagates_and_cleans_temporary_zip(self):
        self.env["RCLONE_EXIT"] = "5"
        self.assertEqual(self.upload().returncode, 5)
        self.assertEqual(list((self.root / "staging").iterdir()), [])

    def test_zip_failure_prevents_upload(self):
        self.write_tool("zip", "#!/bin/bash\nexit 13\n")
        self.assertEqual(self.upload().returncode, 13)
        self.assert_no_upload()
        self.assertEqual(list((self.root / "staging").iterdir()), [])

    def test_staging_inside_backup_is_rejected(self):
        self.env["UPLOAD_TMP_DIR"] = str(self.backup / "staging")
        result = self.upload()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the backup", result.stderr)
        self.assert_no_upload()

    def run_backup(self):
        self.env.update(BACKUP_DIR=str(self.root / "backups"), INCREMENTAL="false",
                        DIR_DATE_PATTERN="test", COMPRESS_THREADS="0")
        self.write_tool("xtrabackup", '''#!/bin/bash
if [ "$1" = --version ]; then exit 0; fi
for arg in "$@"; do case "$arg" in --target-dir=*) target=${arg#*=} ;; esac; done
printf 'backup_type = full-backuped\\nto_lsn = 100\\n' > "$target/xtrabackup_checkpoints"
echo 'completed OK!'
exit "${BACKUP_EXIT:-0}"
''')
        command = f'bash "{ROOT / "scripts/backup.sh"}" && touch "{self.root / "rotation-ran"}"'
        return subprocess.run(["bash", "-c", command], env=self.env, capture_output=True, text=True)

    def test_core_uploads_before_rotation(self):
        result = self.run_backup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path(self.env["CAPTURE"]).exists())
        self.assertTrue((self.root / "rotation-ran").exists())

    def test_core_upload_failure_blocks_rotation(self):
        self.env["RCLONE_EXIT"] = "5"
        result = self.run_backup()
        self.assertEqual(result.returncode, 5, result.stderr)
        self.assertFalse((self.root / "rotation-ran").exists())

    def test_core_backup_failure_prevents_upload(self):
        self.env["BACKUP_EXIT"] = "23"
        self.assertEqual(self.run_backup().returncode, 23)
        self.assert_no_upload()
        self.assertFalse((self.root / "rotation-ran").exists())

    def test_upload_disabled_by_default(self):
        self.env.pop("UPLOAD_DESTINATION")
        self.assertEqual(self.run_backup().returncode, 0)
        self.assert_no_upload()
        self.assertTrue((self.root / "rotation-ran").exists())

    def test_custom_hook_is_preserved(self):
        hook = self.root / "custom hook"
        hook.write_text('#!/bin/bash\nprintf "%s" "$1" > "$BACKUP_DIR/hook-status"\n')
        hook.chmod(0o755)
        self.env["AFTER_BACKUP_SCRIPT"] = str(hook)
        self.assertEqual(self.run_backup().returncode, 0)
        self.assertEqual((self.root / "backups/hook-status").read_text(), "succeed")
        self.assertTrue(Path(self.env["CAPTURE"]).exists())

    def test_custom_hook_failure_prevents_upload_and_rotation(self):
        self.env["AFTER_BACKUP_SCRIPT"] = "/bin/false"
        self.assertNotEqual(self.run_backup().returncode, 0)
        self.assert_no_upload()
        self.assertFalse((self.root / "rotation-ran").exists())

    def test_legacy_node_hook_maps_to_builtin_upload(self):
        self.write_tool("node", "#!/bin/bash\nexit 99\n")
        self.env.pop("UPLOAD_DESTINATION")
        self.env.update(GS_BUCKET_NAME="existing-bucket", AFTER_BACKUP_SCRIPT="node /gs-upload")
        result = self.run_backup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.captured()["args"][2].startswith("sidecar_gcs:existing-bucket/"))


if __name__ == "__main__":
    unittest.main()
