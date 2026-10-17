from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[3]
SOURCE_SHA = "github.event.workflow_run.head_sha || github.sha"
ARTIFACT_MODE = "github.event_name == 'pull_request' || vars.PUBLISH_DOCKER == ''"


class ContainerArtifactIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        workflows = REPO / ".github" / "workflows"
        cls.build = yaml.safe_load((workflows / "docker_build.yml").read_text())
        cls.test = yaml.safe_load((workflows / "docker_test.yml").read_text())
        cls.steps = cls.test["jobs"]["Docker_Test"]["steps"]
        cls.verify = next(
            step
            for step in cls.steps
            if step.get("name") == "Verify artifact image revision"
        )
        cls.start = next(
            step for step in cls.steps if step.get("name") == "Start container"
        )

    def test_build_tags_use_the_full_commit(self) -> None:
        metadata = next(
            step
            for step in self.build["jobs"]["Docker_Build"]["steps"]
            if step.get("name") == "Docker meta"
        )
        self.assertIn("type=sha,format=long", metadata["with"]["tags"].splitlines())

    def test_loaded_image_and_source_use_the_same_commit(self) -> None:
        env = self.test["jobs"]["Docker_Test"]["env"]
        self.assertEqual(
            env["image_tag"],
            "${{ format('sha-{0}{1}', "
            + SOURCE_SHA
            + ", inputs.os == 'alpine' && '-alpine' || '') }}",
        )
        self.assertEqual(
            self.verify["env"]["expected_revision"], "${{ " + SOURCE_SHA + " }}"
        )
        self.assertEqual(self.verify["if"], "${{ " + ARTIFACT_MODE + " }}")
        load_index = next(
            index
            for index, step in enumerate(self.steps)
            if step.get("name") == "Load artifact"
        )
        self.assertLess(load_index, self.steps.index(self.verify))
        self.assertLess(self.steps.index(self.verify), self.steps.index(self.start))

    def test_artifact_start_cannot_pull_a_registry_fallback(self) -> None:
        self.assertEqual(
            self.start["env"]["pull_policy"],
            "${{ (" + ARTIFACT_MODE + ") && 'never' || 'missing' }}",
        )
        self.assertIn('--pull="$pull_policy"', self.start["run"])

    def run_revision_check(
        self, revision: str, present: bool = True
    ) -> subprocess.CompletedProcess:
        bash = shutil.which("bash")
        if not bash:
            self.skipTest("Bash is required to exercise the Linux container workflow")
        stub = """docker() {
    [[ "$1" == image && "$2" == inspect && "${!#}" == "$image_name" ]] || return 90
    [[ "$mock_present" == yes ]] || return 1
    printf '%s\\n' "$mock_revision"
}
"""
        return subprocess.run(
            [bash, "-euo", "pipefail", "-c", stub + self.verify["run"]],
            env={
                "image_name": "ghcr.io/example/server:sha-" + "a" * 40,
                "expected_revision": "a" * 40,
                "mock_revision": revision,
                "mock_present": "yes" if present else "no",
            },
            capture_output=True,
            text=True,
            check=False,
        )

    def test_matching_loaded_revision_passes(self) -> None:
        self.assertEqual(self.run_revision_check("a" * 40).returncode, 0)

    def test_wrong_loaded_revision_fails_closed(self) -> None:
        result = self.run_revision_check("b" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match the source commit", result.stdout)

    def test_missing_loaded_image_fails_closed(self) -> None:
        self.assertNotEqual(
            self.run_revision_check("a" * 40, present=False).returncode, 0
        )


if __name__ == "__main__":
    unittest.main()
