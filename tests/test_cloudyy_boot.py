from __future__ import annotations

import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/cloudyy-boot"

EFI_OUTPUT = r"""BootCurrent: 0005
Timeout: 1 seconds
BootOrder: 0005,0006,0000,0004,0001,0002
Boot0000* Windows Boot Manager  HD(4,GPT,2e3f1244-629d-4280-80bb-27fa0a667a80,0x73df7000,0x64000)/\EFI\MICROSOFT\BOOT\BOOTMGFW.EFI
Boot0001* Limine        HD(1,GPT,ca073969-2566-4072-b396-9750271817d2,0x800,0x400000)/\EFI\limine\limine_x64.efi
Boot0002* Windows Boot Manager  VenHw(99e275e7-75a0-4b37-a2e6-c5385e6c00cb)
Boot0004* ubuntu        HD(4,GPT,2e3f1244-629d-4280-80bb-27fa0a667a80,0x73df7000,0x64000)/\EFI\ubuntu\shimx64.efi0000424f
Boot0005* UEFI OS       HD(1,GPT,b2c8a0ed-14e0-4dd7-bb93-ba8d2e2292e4,0x800,0x200000)/\EFI\BOOT\BOOTX64.EFI0000424f
Boot0006* UEFI OS       HD(1,GPT,ca073969-2566-4072-b396-9750271817d2,0x800,0x400000)/\EFI\BOOT\BOOTX64.EFI0000424f
"""
EFI_RENUMBERED_OUTPUT = EFI_OUTPUT.replace("Boot0000*", "Boot0008*")

LSBLK_OUTPUT = """\
/dev/sda
/dev/sda4 /dev/sda 2e3f1244-629d-4280-80bb-27fa0a667a80
/dev/sdb
/dev/sdb1 /dev/sdb b2c8a0ed-14e0-4dd7-bb93-ba8d2e2292e4
/dev/nvme1n1
/dev/nvme1n1p1 /dev/nvme1n1 ca073969-2566-4072-b396-9750271817d2
"""


class CloudyyBootTest(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp_dir.cleanup)
        self.home = Path(self.temp_dir.name)
        self.fake_bin = self.home / "bin"
        self.fake_bin.mkdir()
        self.config = self.home / "boot-targets"
        self.efi_vars = self.home / "efivars"
        self.efi_vars.mkdir()
        self.state = self.home / "boot-next"
        self.calls = self.home / "calls"

        self._write_executable(
            "efibootmgr",
            f"""#!/usr/bin/bash
set -euo pipefail
if [[ ${{1:-}} == --bootnext ]]; then
  if [[ ${{FAKE_EFI_IGNORE_SET:-0}} != 1 ]]; then
    printf '%s\n' "$2" >"$FAKE_EFI_STATE"
  fi
  exit 0
fi
if [[ ${{1:-}} == --delete-bootnext ]]; then
  /usr/bin/rm -f "$FAKE_EFI_STATE"
  exit 0
fi
if [[ -f "$FAKE_EFI_STATE" ]]; then
  printf 'BootNext: %s\n' "$(<"$FAKE_EFI_STATE")"
fi
if [[ ${{FAKE_EFI_RENUMBER:-0}} == 1 ]]; then
/usr/bin/cat <<'EOF'
{EFI_RENUMBERED_OUTPUT.rstrip()}
EOF
else
/usr/bin/cat <<'EOF'
{EFI_OUTPUT.rstrip()}
EOF
fi
if [[ ${{FAKE_EFI_DUPLICATE:-0}} == 1 ]]; then
  printf '%s\n' 'Boot0007* Windows duplicate  HD(4,GPT,2e3f1244-629d-4280-80bb-27fa0a667a80,0x73df7000,0x64000)/\\EFI\\MICROSOFT\\BOOT\\BOOTMGFW.EFI'
fi
""",
        )
        self._write_executable(
            "lsblk",
            f"""#!/usr/bin/bash
set -euo pipefail
if [[ " $* " == *" -rpn "* ]]; then
  /usr/bin/cat <<'EOF'
{LSBLK_OUTPUT.rstrip()}
EOF
  exit 0
fi
case "${{@: -1}}" in
  /dev/sda)
    [[ " $* " == *" -dnro "* ]] && printf '%s\n' 'Samsung\\x20SSD 1.8T' || printf 'Samsung SSD 1.8T\n'
    ;;
  /dev/sdb) printf 'Portable SSD 1.8T\n' ;;
  /dev/nvme1n1) printf 'NVMe Disk 1.8T\n' ;;
esac
""",
        )
        self._write_executable(
            "sudo",
            """#!/usr/bin/bash
set -euo pipefail
printf 'sudo %s\n' "$*" >>"$FAKE_CALLS"
exec "$@"
""",
        )
        self._write_executable(
            "systemctl",
            """#!/usr/bin/bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >>"$FAKE_CALLS"
if [[ ${FAKE_SYSTEMCTL_FAIL:-0} == 1 ]]; then
  printf 'reboot denied\n' >&2
  exit 1
fi
""",
        )

    def _write_executable(self, name: str, content: str) -> None:
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(content), encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def _run(
        self,
        *args: str,
        input_text: str = "",
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update({
            "CLOUDYY_BOOT_CONFIG": str(self.config),
            "CLOUDYY_BOOT_EFIVARS_DIR": str(self.efi_vars),
            "FAKE_EFI_STATE": str(self.state),
            "FAKE_CALLS": str(self.calls),
            "PATH": f"{self.fake_bin}:{env['PATH']}",
        })
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            input=input_text,
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )

    def test_configure_saves_stable_user_named_targets(self):
        result = self._run(
            "configure",
            input_text="windows\nomarchy\n\narch\n\n",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Boot0005", result.stdout)
        self.assertIn("/dev/sdb1", result.stdout)
        self.assertIn("Samsung SSD", result.stdout)
        self.assertIn("current", result.stdout.lower())
        self.assertIn("unsupported", result.stdout.lower())
        self.assertEqual(
            self.config.read_text(encoding="utf-8"),
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n"
            "omarchy\tca073969-2566-4072-b396-9750271817d2"
            "\t\\efi\\limine\\limine_x64.efi\tLimine\n"
            "arch\tb2c8a0ed-14e0-4dd7-bb93-ba8d2e2292e4"
            "\t\\efi\\boot\\bootx64.efi\tUEFI OS\n",
        )
        saved = self.config.read_text(encoding="utf-8")
        self.assertNotIn("Boot000", saved)
        self.assertNotIn("/dev/sd", saved)

    def test_set_resolves_signature_and_sets_verified_bootnext_without_reboot(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n",
            encoding="utf-8",
        )

        result = self._run("windows", "--set")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(encoding="utf-8"), "0000\n")
        self.assertIn("BootNext is set to windows (Boot0000)", result.stdout)
        self.assertEqual(
            self.calls.read_text(encoding="utf-8"),
            "sudo efibootmgr --bootnext 0000\n",
        )

    def test_now_reboots_after_setting_and_verifying_bootnext(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "omarchy\tca073969-2566-4072-b396-9750271817d2"
            "\t\\efi\\limine\\limine_x64.efi\tLimine\n",
            encoding="utf-8",
        )

        result = self._run("omarchy", "--now")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(encoding="utf-8"), "0001\n")
        self.assertEqual(
            self.calls.read_text(encoding="utf-8"),
            "sudo efibootmgr --bootnext 0001\n"
            "systemctl reboot\n",
        )

    def test_list_resolves_configured_aliases_against_current_entries(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n"
            "arch\tb2c8a0ed-14e0-4dd7-bb93-ba8d2e2292e4"
            "\t\\efi\\boot\\bootx64.efi\tUEFI OS\n",
            encoding="utf-8",
        )

        result = self._run("list")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("windows", result.stdout)
        self.assertIn("Boot0000", result.stdout)
        self.assertIn("arch", result.stdout)
        self.assertIn("Boot0005", result.stdout)
        self.assertFalse(self.calls.exists())

    def test_clear_removes_and_verifies_pending_bootnext(self):
        self.state.write_text("0001\n", encoding="utf-8")

        result = self._run("clear")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.state.exists())
        self.assertIn("Cleared pending BootNext (Boot0001)", result.stdout)
        self.assertEqual(
            self.calls.read_text(encoding="utf-8"),
            "sudo efibootmgr --delete-bootnext\n",
        )

    def test_now_does_not_reboot_when_firmware_does_not_verify_bootnext(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "omarchy\tca073969-2566-4072-b396-9750271817d2"
            "\t\\efi\\limine\\limine_x64.efi\tLimine\n",
            encoding="utf-8",
        )

        result = self._run(
            "omarchy",
            "--now",
            extra_env={"FAKE_EFI_IGNORE_SET": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not verify BootNext", result.stderr)
        self.assertEqual(
            self.calls.read_text(encoding="utf-8"),
            "sudo efibootmgr --bootnext 0001\n",
        )

    def test_ambiguous_signature_fails_without_changing_firmware(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n",
            encoding="utf-8",
        )

        result = self._run(
            "windows",
            "--now",
            extra_env={"FAKE_EFI_DUPLICATE": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ambiguous", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_configure_rejects_aliases_reserved_for_commands(self):
        result = self._run(
            "configure",
            input_text="list\nwindows\n\n\n\n\n",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("reserved", result.stdout.lower())
        self.assertIn("windows\t2e3f1244", self.config.read_text(encoding="utf-8"))
        self.assertNotIn("\nlist\t", self.config.read_text(encoding="utf-8"))

    def test_set_resolves_new_boot_number_after_firmware_renumbering(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n",
            encoding="utf-8",
        )

        result = self._run(
            "windows",
            "--set",
            extra_env={"FAKE_EFI_RENUMBER": "1"},
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(encoding="utf-8"), "0008\n")

    def test_alias_without_mode_makes_no_firmware_change(self):
        result = self._run("windows")

        self.assertEqual(result.returncode, 2)
        self.assertFalse(self.state.exists())
        self.assertFalse(self.calls.exists())

    def test_clear_without_pending_bootnext_is_a_noop(self):
        result = self._run("clear")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No pending BootNext", result.stdout)
        self.assertFalse(self.calls.exists())

    def test_now_checks_reboot_command_before_changing_firmware(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n",
            encoding="utf-8",
        )
        (self.fake_bin / "systemctl").unlink()

        result = self._run(
            "windows",
            "--now",
            extra_env={"PATH": str(self.fake_bin)},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("systemctl", result.stderr)
        self.assertFalse(self.state.exists())
        self.assertFalse(self.calls.exists())

    def test_now_reports_verified_bootnext_when_reboot_command_fails(self):
        self.config.write_text(
            "# cloudyy-boot-targets-v1\n"
            "windows\t2e3f1244-629d-4280-80bb-27fa0a667a80"
            "\t\\efi\\microsoft\\boot\\bootmgfw.efi\tWindows Boot Manager\n",
            encoding="utf-8",
        )

        result = self._run(
            "windows",
            "--now",
            extra_env={"FAKE_SYSTEMCTL_FAIL": "1"},
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(encoding="utf-8"), "0000\n")
        self.assertIn("BootNext remains set", result.stderr)


if __name__ == "__main__":
    unittest.main()
