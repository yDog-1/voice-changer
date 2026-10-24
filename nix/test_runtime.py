"""Exercise runtime data placement without installing Python wheels or using a GPU."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNTIME = Path(__file__).with_name("runtime.sh")


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="voice changer ")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / "source"
        for name in (
            "server/MMVCServerSIO.py", "nix/requirements.in",
            "nix/requirements.lock", "nix/build-requirements.lock",
            "client/demo/dist/index.html",
        ):
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("packaged\n")
            path.chmod(0o444)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.python = self.bin / "fake-python"
        self.python.write_text(
            '#!/usr/bin/env bash\n'
            '[[ "${1:-}" == -c ]] && exit 0\n'
            'printf "%s\\n" "$PWD" "$@" > "$TEST_LOG"\n'
        )
        self.python.chmod(0o755)
        uv = self.bin / "uv"
        uv.write_text(
            '#!/usr/bin/env bash\nset -eu\n'
            'if [[ "$1" == venv ]]; then\n'
            '  venv="${@: -1}"\n'
            '  mkdir -p "$venv/bin"\n'
            '  cp "$TEST_PYTHON" "$venv/bin/python"\n'
            'fi\n'
        )
        uv.chmod(0o755)
        pactl = self.bin / "pactl"
        pactl.write_text("#!/usr/bin/env bash\nexit 0\n")
        pactl.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("VOICE_CHANGER_")
            and key not in ("XDG_DATA_HOME", "VIRTUAL_ENV")
        }
        self.env.update(
            HOME=str(self.base / "home"),
            PATH=f"{self.bin}:{self.env['PATH']}",
            VOICE_CHANGER_SOURCE=str(self.source),
            TEST_PYTHON=str(self.python),
            TEST_LOG=str(self.base / "invocation"),
        )

    def run_runtime(self, action, *args):
        return subprocess.run(
            ["bash", str(RUNTIME), action, *args], cwd=self.base,
            env=self.env, text=True, capture_output=True,
        )

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_default_setup_start_and_repeat_setup_preserve_data(self):
        root = self.base / "home/.local/share/voice-changer"
        self.assert_success(self.run_runtime("setup"))
        self.assertTrue((root / ".venv/bin/python").is_file())
        settings = root / "server/stored_setting.json"
        settings.write_text('{"gain": 2}')
        model = root / "server/model_dir/0/model.pth"
        model.parent.mkdir(parents=True)
        model.write_bytes(b"model")
        (root / "server/MMVCServerSIO.py").write_text("old code")
        self.assert_success(self.run_runtime("setup"))
        self.assertEqual(settings.read_text(), '{"gain": 2}')
        self.assertEqual(model.read_bytes(), b"model")
        self.assertEqual((root / "server/MMVCServerSIO.py").read_text(), "packaged\n")
        self.assert_success(self.run_runtime("start", "-p", "18889"))
        invocation = (self.base / "invocation").read_text().splitlines()
        self.assertEqual(invocation[0], str(root / "server"))
        self.assertEqual(invocation[-2:], ["-p", "18889"])

    def test_xdg_data_home(self):
        self.env["XDG_DATA_HOME"] = str(self.base / "custom data")
        self.assert_success(self.run_runtime("setup"))
        root = self.base / "custom data/voice-changer"
        self.assertTrue((root / "client/demo/dist/index.html").is_file())
        self.assert_success(self.run_runtime("doctor"))
        self.assertIn(str(root / "nix/doctor.py"), (self.base / "invocation").read_text())

    def test_explicit_checkout_is_not_overwritten(self):
        root = self.source
        self.env["VOICE_CHANGER_ROOT"] = str(root)
        (root / "server/MMVCServerSIO.py").chmod(0o644)
        (root / "server/MMVCServerSIO.py").write_text("local code")
        del self.env["VOICE_CHANGER_SOURCE"]
        self.assert_success(self.run_runtime("setup"))
        self.assertEqual((root / "server/MMVCServerSIO.py").read_text(), "local code")
        self.assert_success(self.run_runtime("start"))
        self.assertFalse((self.base / "home/.local/share/voice-changer").exists())

    def test_uninitialized_start_reports_setup_without_creating_data(self):
        result = self.run_runtime("start")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("voice-changer-setup", result.stderr)
        self.assertFalse((self.base / "home").exists())

    def test_lock_requires_checkout_instead_of_using_default_data(self):
        result = self.run_runtime("lock")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / "home").exists())
        self.env["VOICE_CHANGER_ROOT"] = str(self.source)
        self.assert_success(self.run_runtime("lock"))


if __name__ == "__main__":
    unittest.main()
