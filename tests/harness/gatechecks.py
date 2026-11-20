from pathlib import Path

from fixture import Fixture


class GateChecks(Fixture):
    """The shipped gate permits explicit installation; the closed seam still refuses writes."""

    def shipped(self, *args, code=0):
        return self.run_cli("harness-closed", *args, code=code)

    def test_shipped_gate_installs_and_removes(self):
        result = self.run_cli("harness-shipped", "install", *self.options)
        manifest = Path(result["manifest"])
        self.assertTrue(manifest.is_file())
        self.run_cli("harness-shipped", "remove", *self.options)
        self.assertFalse(manifest.exists())

    def snapshot(self):
        return {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}

    def test_inspection_still_answers_with_the_gate_closed(self):
        self.hook_source(command="true")
        self.write(self.source / "skills/one/SKILL.md", "one")
        before = self.snapshot()
        plan = self.shipped("plan", *self.options)
        self.assertEqual(len(plan["skillCandidates"]), 1)
        self.shipped("status", *self.options)
        self.assertEqual(self.snapshot(), before)

    def test_install_and_remove_refuse_and_write_nothing(self):
        self.hook_source(command="true")
        self.write(self.source / "skills/one/SKILL.md", "one")
        hook = self.shipped("plan", *self.options)["hooks"][0]["id"]
        before = self.snapshot()
        self.shipped("install", *self.options, "--hook", hook, "--skill", "one", code=1)
        self.shipped("remove", *self.options, code=1)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.state.exists())
        self.assertFalse((self.target / "hooks.json").exists())

    def test_tools_install_and_remove_refuse_and_write_nothing(self):
        options = ["--source-home", str(self.source), "--target-home", str(self.target),
                   "--skills-root", str(self.skills), "--state-root", str(self.state)]
        before = self.snapshot()
        self.shipped("tools", "install", *options, code=1)
        self.shipped("tools", "remove", *options, code=1)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.skills.exists())

    def test_record_and_migrate_apply_refuse_with_the_reason(self):
        file = self.root / "result.json"
        self.write(file, {"scope": "user"})
        before = self.snapshot()
        message = self.shipped("record", "--file", file, "--state-root", self.state, code=2)
        self.assertIn("disabled in Phase 1", message)
        message = self.shipped("migrate", *self.options, "--apply", code=2)
        self.assertIn("disabled in Phase 1", message)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.state.exists())

    def test_the_opened_gate_is_what_the_other_checks_drive(self):
        # The same install the shipped CLI refuses lands once the gate is open.
        result = self.run_cli("harness", "install", *self.options)
        self.assertTrue(Path(result["manifest"]).is_file())
