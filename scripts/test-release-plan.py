#!/usr/bin/env python3
"""Exercise release planning in temporary Git repos without calling GitHub."""
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1]


class ReleasePlanTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="luma-release-plan-")
        self.root = Path(self.temporary.name)
        for directory in ["scripts", "Packaging", "bin"]:
            (self.root / directory).mkdir()
        for name in ["release-common.sh", "ci-release-plan.sh"]:
            shutil.copy2(SOURCE / "scripts" / name, self.root / "scripts" / name)
        with (self.root / "Packaging/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleShortVersionString": "0.2.1", "CFBundleVersion": "1"}, output)
        self.env = os.environ | {
            "GIT_AUTHOR_NAME": "Luma Release Test", "GIT_COMMITTER_NAME": "Luma Release Test",
            "GIT_AUTHOR_EMAIL": "test@example.invalid", "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "GITHUB_OUTPUT": str(self.root / "outputs"), "GITHUB_EVENT_NAME": "push",
            "GITHUB_REF": "refs/heads/main", "GITHUB_REF_NAME": "main", "GITHUB_REF_TYPE": "branch",
            "GH_REPO": "example/Luma", "INPUT_VERSION": "", "INPUT_PUBLISH": "true",
            "LUMA_TEST_VERSION": "0.2.1", "LUMA_TEST_RELEASE": "absent",
            "LUMA_TEST_CALLS": str(self.root / "calls"),
        }
        fake = self.root / "bin/gh"
        fake.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$LUMA_TEST_CALLS"
case "$LUMA_TEST_RELEASE" in
  complete) printf 'Luma-%s-universal.dmg\\nLuma-%s-universal.dmg.sha256\\n' "$LUMA_TEST_VERSION" "$LUMA_TEST_VERSION" ;;
  incomplete) printf 'Luma-%s-universal.dmg\\n' "$LUMA_TEST_VERSION" ;;
  draft) printf '__draft__\\n' ;;
  error) printf 'HTTP 503: service unavailable\\n' >&2; exit 1 ;;
  *) printf 'release not found\\n' >&2; exit 1 ;;
esac
''')
        fake.chmod(0o755)
        self.git("init", "-b", "main")
        self.git("add", "scripts", "Packaging")
        self.git("commit", "-m", "Initial test source")
        self.initial_sha = self.git("rev-parse", "HEAD")

    def tearDown(self):
        self.temporary.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, env=self.env, stderr=subprocess.DEVNULL, text=True).strip()

    def plan(self, **changes):
        env = self.env | changes
        result = subprocess.run(["bash", "scripts/ci-release-plan.sh"], cwd=self.root, env=env, capture_output=True, text=True)
        output = self.root / "outputs"
        values = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
        return result, values

    def test_main_creates_missing_release(self):
        result, plan = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plan["publish"], "true")
        self.assertEqual(plan["release_tag"], "v0.2.1")
        self.assertEqual(plan["source_sha"], self.initial_sha)

    def test_complete_version_and_draft_are_preserved(self):
        for state in ["complete", "draft"]:
            result, plan = self.plan(LUMA_TEST_RELEASE=state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plan["publish"], "false")

    def test_updated_application_version_publishes_a_new_tag(self):
        with (self.root / "Packaging/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleShortVersionString": "0.3.0"}, output)
        result, plan = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plan["release_tag"], "v0.3.0")
        self.assertEqual(plan["publish"], "true")

    def test_pull_request_never_publishes_or_queries_releases(self):
        result, plan = self.plan(GITHUB_EVENT_NAME="pull_request", GITHUB_REF="refs/pull/1/merge")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plan["publish"], "false")
        self.assertFalse((self.root / "calls").exists())

    def test_manual_publish_and_build_only(self):
        for flag in ["true", "false"]:
            result, plan = self.plan(GITHUB_EVENT_NAME="workflow_dispatch", INPUT_PUBLISH=flag, INPUT_VERSION="0.3.0-rc.1")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plan["publish"], flag)
            self.assertEqual(plan["release_tag"], "v0.3.0-rc.1")

    def test_explicit_tag_can_refresh_assets(self):
        result, plan = self.plan(GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v0.2.1", GITHUB_REF="refs/tags/v0.2.1", LUMA_TEST_RELEASE="complete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plan["publish"], "true")
        self.assertFalse((self.root / "calls").exists())

    def test_published_release_event_can_attach_assets(self):
        result, plan = self.plan(GITHUB_EVENT_NAME="release", GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v0.2.1", LUMA_TEST_RELEASE="complete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(plan["publish"], "true")

    def test_missing_or_incomplete_release_rebuilds_tagged_commit(self):
        self.git("tag", "v0.2.1")
        (self.root / "later.txt").write_text("Later unversioned changes")
        self.git("add", "later.txt")
        self.git("commit", "-m", "Later changes")
        for state in ["absent", "incomplete"]:
            self.git("checkout", "main")
            result, plan = self.plan(LUMA_TEST_RELEASE=state)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plan["publish"], "true")
            self.assertEqual(plan["source_sha"], self.initial_sha)
            self.assertEqual(self.git("rev-parse", "HEAD"), self.initial_sha)

    def test_network_error_does_not_masquerade_as_missing_release(self):
        result, plan = self.plan(LUMA_TEST_RELEASE="error")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(plan, {})

    def test_invalid_version_stops_before_github(self):
        result, _ = self.plan(GITHUB_EVENT_NAME="workflow_dispatch", INPUT_VERSION="bad/version")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.root / "calls").exists())


if __name__ == "__main__":
    unittest.main()
