"""Exercise collection with synthetic rootfs/TRX fixtures, NOT a real firmware test."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = (
    'luci-app-passwall2 luci-i18n-passwall2-zh-cn xray-core dnsmasq-full '
    'adguardhome lyaml kmod-brcmfmac brcmfmac-firmware-4366c0-pcie '
    'kmod-nft-tproxy kmod-nft-socket'
).split()


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.build = self.base / 'build'
        self.target = self.build / 'bin/targets/bcm53xx/generic'
        self.target.mkdir(parents=True)
        self.out = self.base / 'output'
        for repo in (self.build, self.build / 'feeds/packages'):
            repo.mkdir(parents=True, exist_ok=True)
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c',
                            'user.email=test@invalid.example', 'commit', '-q',
                            '--allow-empty', '-m', 'fixture'], check=True)
        self.version = json.loads((ROOT / 'sources.lock.json').read_text())['openwrt']['version']
        # No version in upstream build filename: this differs from release server naming.
        self.image_name = 'openwrt-bcm53xx-generic-phicomm_k3-squashfs.trx'
        (self.target / self.image_name).write_bytes(b'HDR0' + b'fixture' * 20)
        self.metadata = {
            'version_number': self.version,
            'profiles': {'phicomm_k3': {'supported_devices': ['phicomm,k3'], 'images': [{
                'filesystem': 'squashfs', 'type': 'trx', 'name': self.image_name
            }]}}
        }
        self.save_metadata()
        self.manifest = self.target / 'openwrt-bcm53xx-generic.manifest'
        self.manifest.write_text(''.join(p + ' - 1\n' for p in PACKAGES))
        rootfs = self.build / 'build_dir/target-arm_cortex-a9_musl_eabi/root-bcm53xx'
        for relative in (
            'usr/bin/AdGuardHome', 'usr/bin/xray', 'usr/sbin/k3-adguard', 'usr/sbin/k3-check',
            'usr/share/k3/adguard-config.lua', 'etc/uci-defaults/99-k3', 'etc/k3-sources.json',
            'lib/firmware/brcm/brcmfmac4366c-pcie.bin'
        ):
            path = rootfs / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        (rootfs / 'etc/k3-wireless-variant').write_text('official\n')
        (self.build / '.config').write_text('fixture\n')
        (self.build / 'feeds.conf').write_text('fixture\n')

    def save_metadata(self):
        (self.target / 'profiles.json').write_text(json.dumps(self.metadata))

    def collect(self):
        return subprocess.run(['bash', str(ROOT / 'scripts/collect.sh'), str(self.build),
                               'official', str(self.out)], capture_output=True, text=True)

    def test_source_filename_and_repeatable_checksums(self):
        for _ in range(2):
            result = self.collect()
            self.assertEqual(result.returncode, 0, result.stderr)
            subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=self.out,
                           check=True, capture_output=True)
        self.assertTrue((self.out / f'k3-openwrt-{self.version}-official-squashfs.trx').exists())
        self.assertIn('HARDWARE UNTESTED', (self.out / 'STATUS.txt').read_text())

    def test_wrong_board_is_not_collected(self):
        self.metadata['profiles']['phicomm_k3']['supported_devices'] = ['phicomm,k3c']
        self.save_metadata()
        self.assertNotEqual(self.collect().returncode, 0)

    def test_missing_required_package_is_not_collected(self):
        self.manifest.write_text('xray-core - 1\n')
        self.assertNotEqual(self.collect().returncode, 0)


if __name__ == '__main__':
    unittest.main()
