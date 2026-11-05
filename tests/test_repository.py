"""Offline contract checks. No network requests and no router writes."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class RepositoryTests(unittest.TestCase):
    def test_sources_are_immutable_https(self):
        lock = json.loads((ROOT / "sources.lock.json").read_text())
        for name in ("openwrt", "passwall2", "passwall_packages"):
            self.assertRegex(lock[name]["commit"], r"^[a-f0-9]{40}$")
            self.assertTrue(lock[name]["url"].startswith("https://"))
        self.assertRegex(lock["build"]["go"], r"^1\.[0-9]+$")
        self.assertRegex(lock["wifi_firmware"]["sha256"], r"^[a-f0-9]{64}$")
        self.assertIn("bc9a70326996cc80bee5e09d5e48108c92095acf", lock["wifi_firmware"]["url"])

    def test_required_config_and_negative_cases(self):
        config = (ROOT / "config/k3.config").read_text()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config"
            def check(text):
                path.write_text(text)
                return subprocess.run(["bash", str(ROOT / "scripts/validate-config.sh"), str(path)],
                                      capture_output=True).returncode
            self.assertEqual(check(config), 0)
            self.assertNotEqual(check(config.replace("CONFIG_PACKAGE_adguardhome=y", "")), 0)
            self.assertNotEqual(check(config.replace("CONFIG_PACKAGE_kmod-usb-net-ipheth=y", "")), 0)
            self.assertNotEqual(check(config + "CONFIG_PACKAGE_dnsmasq=y\n"), 0)
            self.assertNotEqual(check(config + "CONFIG_TARGET_bcm53xx_generic_DEVICE_asus_rt-ac88u=y\n"), 0)

    def test_usb_uplink_drivers_are_selected(self):
        config = (ROOT / "config/k3.config").read_text()
        for package in (
            # SIM sticks and modems
            "usb-modeswitch", "kmod-usb-net-rndis", "kmod-usb-net-cdc-ether", "kmod-usb-net-cdc-ncm",
            "kmod-usb-net-huawei-cdc-ncm", "kmod-usb-net-qmi-wwan", "kmod-usb-net-cdc-mbim",
            "kmod-usb-serial-option", "kmod-usb-serial-wwan", "kmod-usb-acm",
            "uqmi", "umbim", "comgt", "comgt-ncm",
            "luci-proto-3g", "luci-proto-qmi", "luci-proto-mbim", "luci-proto-ncm",
            # iPhone
            "kmod-usb-net-ipheth", "usbmuxd",
        ):
            self.assertIn(f"CONFIG_PACKAGE_{package}=y\n", config)
        # Feed packages only exist in the build tree when explicitly installed.
        prepare = (ROOT / "scripts/prepare.sh").read_text()
        for package in ("luci-proto-3g", "luci-proto-qmi", "luci-proto-mbim", "luci-proto-ncm", "usbmuxd"):
            self.assertIn(package, prepare)

    def test_only_the_replacement_wifi_firmware_is_built(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build.yml").read_text())
        self.assertNotIn("strategy", workflow["jobs"]["build"])
        collect = (ROOT / "scripts/collect.sh").read_text()
        self.assertIn(".wifi_firmware.sha256", collect)
        self.assertIn("sha256sum -c -", collect)

    def test_workflow_no_secrets_no_paid_runner(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build.yml").read_text())
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(workflow["jobs"]["build"]["needs"], "test")
        for job in workflow["jobs"].values():
            self.assertEqual(job["runs-on"], "ubuntu-24.04")
            for step in job["steps"]:
                if "uses" in step:
                    self.assertRegex(step["uses"], r"@[a-f0-9]{40}$")
        self.assertNotIn("secrets.", (ROOT / ".github/workflows/build.yml").read_text())

    def test_selective_feeds_and_hidden_translation_default(self):
        prepare = (ROOT / "scripts/prepare.sh").read_text()
        self.assertNotIn('./scripts/feeds install -a', prepare)
        self.assertIn('./scripts/feeds install -p luci luci luci-ssl', prepare)
        self.assertIn('CONFIG_LUCI_LANG_zh_Hans=y', (ROOT / 'config/k3.config').read_text())
        workflow = (ROOT / '.github/workflows/build.yml').read_text()
        self.assertIn('diagnostics/build.config', workflow)
        self.assertIn('tee prepare.log', workflow)
        self.assertIn('K3_GO_VERSION=$(lock .build.go)', prepare)
        self.assertIn('./scripts/feeds update -i packages', prepare)
        self.assertIn('touch feeds/packages/lang/golang/golang/Makefile', prepare)
        self.assertIn('./scripts/feeds install -p packages "golang$K3_GO_VERSION"', prepare)

    def test_firstboot_leaves_wifi_to_official_defaults(self):
        firstboot = (ROOT / "files/etc/uci-defaults/99-k3").read_text()
        self.assertIn("global[0].enabled='0'", firstboot)
        # Radios register asynchronously, and hostapd already reuses the FullMAC interface.
        self.assertNotIn("wifi config", firstboot)
        self.assertNotIn("uci set wireless", firstboot)
        self.assertIn("adguardhome.config.memlimit='104857600'", firstboot)
        self.assertNotIn("adguardhome.config.memlimit='100'", firstboot)

    def test_firstboot_does_not_reset_retained_user_configuration(self):
        script = (ROOT / 'files/etc/uci-defaults/99-k3').read_text()
        self.assertIn('k3.settings.initialized)" = 1 ] && exit 0', script)
        self.assertIn("uci set k3.settings.initialized='1'", script)
        self.assertLess(script.index('&& exit 0'), script.index("hostname='K3-OpenWrt'"))

    def test_dns_activation_guards_and_recovery(self):
        script = (ROOT / "files/usr/sbin/k3-adguard").read_text()
        for guard in ("acl_enable", "Custom dnsmasq port", "trap cleanup EXIT", "previous DNS configuration restored"):
            self.assertIn(guard, script)
        self.assertIn("port='5053'", script)
        self.assertIn("port='53'", script)
        self.assertIn("+short @127.0.0.1 -p 5053", script)
        self.assertIn("+short @127.0.0.1 openwrt.org", script)

    def test_untested_label_and_checksum(self):
        script = (ROOT / "scripts/collect.sh").read_text()
        self.assertIn("HARDWARE UNTESTED", script)
        self.assertIn("sha256sum -- * > SHA256SUMS", script)
        self.assertIn("48445230", script)
        self.assertIn("104857600", script)


if __name__ == "__main__":
    unittest.main()
