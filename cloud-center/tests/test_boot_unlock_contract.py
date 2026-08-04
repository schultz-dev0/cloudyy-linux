from pathlib import Path
import unittest

REPO_ROOT = Path(__file__).resolve().parents[2]
SESSION_START = REPO_ROOT / "bin/cloudyy-session-start"
PLYMOUTH_SCRIPT = REPO_ROOT / "install/assets/plymouth/cloudyy/cloudyy.script"
PLYMOUTH_META = REPO_ROOT / "install/assets/plymouth/cloudyy/cloudyy.plymouth"
MKINIT_DROPIN = REPO_ROOT / "install/assets/mkinitcpio/cloudyy.conf"
COLD_HOOK = REPO_ROOT / "install/assets/mkinitcpio/hooks/cloudyy-coldboot"
ENCRYPT_CONTRACT = REPO_ROOT / "install/assets/cloudyy-encrypt-contract.md"

COLD_BOOT_MARKER = "/run/cloudyy/cold-boot"


class BootUnlockContractTests(unittest.TestCase):
    def test_session_start_skips_lock_only_with_cold_boot_marker(self):
        source = SESSION_START.read_text(encoding="utf-8")

        self.assertIn(COLD_BOOT_MARKER, source)
        self.assertIn("cloudyy-lock --wait", source)
        self.assertIn("keyring-unlock.cred", source)
        self.assertIn("gnome-keyring-daemon", source)

        rm_at = source.find(f'rm -f "$cold_boot_marker"')
        if rm_at < 0:
            rm_at = source.find(f"rm -f {COLD_BOOT_MARKER}")
        unlock_at = source.find("gnome-keyring-daemon")
        lock_at = source.find("cloudyy-lock --wait")

        self.assertGreaterEqual(rm_at, 0, "must remove cold-boot marker")
        self.assertGreaterEqual(unlock_at, 0, "must unlock keyring on cold boot")
        self.assertLess(rm_at, unlock_at, "clear marker before keyring unlock")
        self.assertLess(unlock_at, lock_at, "keyring path must precede lock --wait (else branch)")

    def test_plymouth_theme_uses_locked_palette_and_no_hint(self):
        script = PLYMOUTH_SCRIPT.read_text(encoding="utf-8")
        meta = PLYMOUTH_META.read_text(encoding="utf-8")
        self.assertIn("112533", script)
        self.assertIn("1a3548", script)
        self.assertIn("2a4a63", script)
        self.assertIn("8fa3b5", script)
        self.assertIn("e6eef4", script)
        self.assertIn("CLOUDYY", script)
        self.assertNotRegex(script, r"(?i)enter disk password")
        self.assertIn("Name=cloudyy", meta)

    def test_mkinitcpio_dropin_has_plymouth_encrypt_and_coldboot(self):
        conf = MKINIT_DROPIN.read_text(encoding="utf-8")
        self.assertIn("plymouth", conf)
        self.assertIn("encrypt", conf)
        self.assertIn("cloudyy-coldboot", conf)
        self.assertIn("/etc/vconsole.conf", conf)
        hook = COLD_HOOK.read_text(encoding="utf-8")
        self.assertIn("/run/cloudyy/cold-boot", hook)

    def test_encrypt_contract_documents_dual_mode_and_one_password(self):
        text = ENCRYPT_CONTRACT.read_text(encoding="utf-8")
        self.assertIn("ISO", text)
        self.assertIn("existing", text.lower())
        self.assertIn("keyring-unlock.cred", text)
        self.assertIn("LUKS", text)


if __name__ == "__main__":
    unittest.main()
