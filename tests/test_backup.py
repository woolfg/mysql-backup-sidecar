"""Regression tests for tool discovery, backup status and rotation gating."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class BackupTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sidecar-unit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in ("date", "dirname", "mkdir", "mktemp", "tee", "cat", "rm", "mv", "ls", "grep", "cut"):
            (self.bin / tool).symlink_to(Path("/usr/bin") / tool)
        self.env = dict(os.environ, PATH=str(self.bin), BACKUP_DIR=str(self.root / "backups"),
                        INCREMENTAL="false", DIR_DATE_PATTERN="test", COMPRESS_THREADS="1",
                        MYSQL_PASSWORD='literal $(touch SHOULD_NOT_EXIST) `whoami` " password',
                        DATABASES_EXCLUDE="db1 db2.table1")
        for key in ("BEFORE_BACKUP_SCRIPT", "AFTER_BACKUP_SCRIPT", "MYSQL_PASSWORD_FILE"):
            self.env.pop(key, None)
        self.env["ARGS_FILE"] = str(self.root / "args")

    def tool(self, name, status=0):
        path = self.bin / name
        path.write_text(f'''#!/bin/bash
if [ "$1" = --version ]; then echo '{name} version'; exit 0; fi
printf '%s\\n' "$@" > "$ARGS_FILE"
for arg in "$@"; do
    case "$arg" in --target-dir=*) target=${{arg#*=}} ;; esac
done
printf 'backup_type = full-backuped\\nto_lsn = 100\\n' > "$target/${{CHECKPOINT_NAME:-xtrabackup_checkpoints}}"
# A misleading success string must never override a failing exit status.
echo 'completed OK!'
exit {status}
''')
        path.chmod(0o755)

    def run_backup(self, rotate=False):
        command = f'/bin/bash "{SCRIPTS / "backup.sh"}"'
        if rotate:
            command += f' && touch "{self.root / "rotation-ran"}"'
            (self.bin / "touch").symlink_to("/usr/bin/touch")
        return subprocess.run(["/bin/bash", "-c", command], env=self.env, cwd=self.root,
                              capture_output=True, text=True)

    def test_each_binary_name(self):
        for name in ("xtrabackup", "mariadb-backup", "mariabackup"):
            with self.subTest(name=name):
                self.tool(name)
                self.env["DIR_DATE_PATTERN"] = name
                result = self.run_backup()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"{name} version", result.stdout)
                (self.bin / name).unlink()

    def test_modern_mariadb_name_preferred_to_alias(self):
        self.tool("mariadb-backup")
        self.tool("mariabackup", status=17)
        self.assertEqual(self.run_backup().returncode, 0)

    def test_missing_binary_fails_clearly(self):
        result = self.run_backup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No backup tool found", result.stderr)

    def test_incremental_uses_either_checkpoint_name(self):
        self.tool("mariadb-backup")
        for name in ("xtrabackup_checkpoints", "mariadb_backup_checkpoints"):
            with self.subTest(name=name):
                self.env["CHECKPOINT_NAME"] = name
                self.env["BACKUP_DIR"] = str(self.root / name)
                self.env["DIR_DATE_PATTERN"] = "full-" + name
                self.env["INCREMENTAL"] = "false"
                self.assertEqual(self.run_backup().returncode, 0)
                self.env["DIR_DATE_PATTERN"] = "inc-" + name
                self.env["INCREMENTAL"] = "true"
                self.env["FULL_BACKUP_DATE_RESULT"] = "never"
                result = self.run_backup()
                self.assertEqual(result.returncode, 0, result.stderr)
                args = (self.root / "args").read_text().splitlines()
                self.assertIn(f"--incremental-basedir={self.root / name / 'current' / ('full-' + name)}", args)

    def test_failed_modern_checkpoint_is_ignored(self):
        self.tool("mariadb-backup", status=23)
        self.env["CHECKPOINT_NAME"] = "mariadb_backup_checkpoints"
        self.assertEqual(self.run_backup().returncode, 23)
        target = self.root / "backups/current/test"
        self.assertTrue((target / "mariadb_backup_checkpoints.failed").exists())
        command = f'source "{SCRIPTS / "functions.sh"}"; full_backups'
        result = subprocess.run(["/bin/bash", "-c", command], capture_output=True, text=True,
                                env=dict(self.env, target_dir=str(target.parent)))
        self.assertEqual(result.stdout, "")

    def test_rotation_preserves_old_full_and_incremental_without_recent_full(self):
        self.tool("mariadb-backup")
        for name in ("xtrabackup_checkpoints", "mariadb_backup_checkpoints"):
            with self.subTest(name=name):
                backup_dir = self.root / name
                for directory, kind, lsn in (("full", "full-backuped", 100), ("incremental", "incremental", 200)):
                    path = backup_dir / "current" / directory
                    path.mkdir(parents=True)
                    (path / name).write_text(f"backup_type = {kind}\nto_lsn = {lsn}\n")
                    old = time.time() - 4 * 86400
                    os.utime(path, (old, old))
                env = dict(self.env, PATH=f"{self.bin}:/usr/bin:/bin", BACKUP_DIR=str(backup_dir),
                           INCREMENTAL="true", DELETE_OLDER_DAYS="1")
                result = subprocess.run(["/bin/bash", str(SCRIPTS / "rotate.sh")], env=env,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Skipping deletion from current directory", result.stdout)
                self.assertTrue((backup_dir / "current/full" / name).exists())
                self.assertTrue((backup_dir / "current/incremental" / name).exists())

    def test_failure_prevents_rotation_and_invalidates_checkpoints(self):
        self.tool("mariadb-backup", status=23)
        hook = self.root / "after hook"
        hook.write_text('#!/bin/bash\nprintf "%s" "$1" > "$BACKUP_DIR/hook-status"\n')
        hook.chmod(0o755)
        self.env["AFTER_BACKUP_SCRIPT"] = str(hook)
        result = self.run_backup(rotate=True)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertFalse((self.root / "rotation-ran").exists())
        target = self.root / "backups/current/test"
        self.assertFalse((target / "xtrabackup_checkpoints").exists())
        self.assertTrue((self.root / "backups/current/test/xtrabackup_checkpoints.failed").exists())
        self.assertEqual((self.root / "backups/hook-status").read_text(), "failed")

    def test_success_and_literal_arguments(self):
        self.tool("xtrabackup")
        result = self.run_backup(rotate=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "args").read_text().splitlines()
        self.assertIn("--password=" + self.env["MYSQL_PASSWORD"], args)
        self.assertIn("--databases-exclude=db1 db2.table1", args)
        self.assertIn("--compress-threads=1", args)
        self.assertTrue((self.root / "rotation-ran").exists())
        self.assertFalse((self.root / "SHOULD_NOT_EXIST").exists())

    def test_logging_failure_prevents_rotation(self):
        self.tool("xtrabackup")
        (self.bin / "tee").unlink()
        tee = self.bin / "tee"
        tee.write_text('#!/bin/bash\ncat >/dev/null\nexit 9\n')
        tee.chmod(0o755)
        self.assertEqual(self.run_backup(rotate=True).returncode, 9)
        self.assertFalse((self.root / "rotation-ran").exists())

    def test_before_hook_failure_prevents_backup(self):
        self.tool("xtrabackup")
        self.env["BEFORE_BACKUP_SCRIPT"] = "/bin/false"
        self.assertNotEqual(self.run_backup().returncode, 0)
        self.assertFalse((self.root / "args").exists())

    def test_after_hook_failure_prevents_rotation(self):
        self.tool("xtrabackup")
        self.env["AFTER_BACKUP_SCRIPT"] = "/bin/false"
        self.assertNotEqual(self.run_backup(rotate=True).returncode, 0)
        self.assertFalse((self.root / "rotation-ran").exists())

    def legacy_node_hook(self):
        node = self.bin / "node"
        node.write_text('#!/bin/bash\nprintf "%s\\n" "$@" > "$HOOK_ARGS_FILE"\nexit "${HOOK_EXIT:-0}"\n')
        node.chmod(0o755)
        self.env["HOOK_ARGS_FILE"] = str(self.root / "hook-args")

    def test_legacy_google_storage_after_hook_command(self):
        self.tool("xtrabackup")
        self.legacy_node_hook()
        self.env["AFTER_BACKUP_SCRIPT"] = "node /gs-upload"
        result = self.run_backup(rotate=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "hook-args").read_text().splitlines()
        self.assertEqual(args[0:2], ["/gs-upload", "succeed"])
        self.assertIn("completed OK!", args[2])
        self.assertEqual(args[3], str(self.root / "backups/current/test"))
        self.assertTrue((self.root / "rotation-ran").exists())

    def test_legacy_hook_failure_prevents_rotation(self):
        self.tool("xtrabackup")
        self.legacy_node_hook()
        self.env.update(AFTER_BACKUP_SCRIPT="node /gs-upload", HOOK_EXIT="37")
        result = self.run_backup(rotate=True)
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertFalse((self.root / "rotation-ran").exists())

    def test_legacy_before_hook_command(self):
        self.tool("xtrabackup")
        self.legacy_node_hook()
        self.env["BEFORE_BACKUP_SCRIPT"] = "node /before-script"
        result = self.run_backup()
        self.assertEqual(result.returncode, 0, result.stderr)
        args = (self.root / "hook-args").read_text().splitlines()
        self.assertEqual(args, ["/before-script", str(self.root / "backups/current/test")])

    def test_existing_backup_is_not_overwritten(self):
        self.tool("xtrabackup")
        self.assertEqual(self.run_backup().returncode, 0)
        result = self.run_backup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not empty", result.stderr)
        self.assertTrue((self.root / "backups/current/test/xtrabackup_checkpoints").exists())

    def test_legacy_backup_directory_variable(self):
        self.tool("xtrabackup")
        self.env["BACKUP"] = self.env.pop("BACKUP_DIR")
        self.assertEqual(self.run_backup().returncode, 0)
        self.assertTrue((self.root / "backups/current/test/xtrabackup_checkpoints").exists())


if __name__ == "__main__":
    unittest.main()
