"""Run the real activation shell with isolated mock UCI/services; never touch a router."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
import yaml
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
base = pathlib.Path(os.environ['MOCK_ROOT'])
statefile = base / 'state.json'
state = json.loads(statefile.read_text())
if name == 'uci':
    args = [a for a in args if a != '-q']
    action = args[0]
    if action == 'get':
        if args[1] not in state: sys.exit(1)
        value = state[args[1]]
        print(' '.join(value) if isinstance(value, list) else value)
    elif action == 'set':
        key, val = args[1].split('=', 1); state[key] = val
    elif action == 'add_list':
        key, val = args[1].split('=', 1); state.setdefault(key, []).append(val)
    elif action == 'del_list':
        key, val = args[1].split('=', 1)
        if val in state.get(key, []):
            state[key].remove(val)
            if not state[key]: del state[key]
    elif action == 'export':
        print(json.dumps({k: v for k, v in state.items() if k.startswith(args[1] + '.')}))
    elif action == 'import':
        state = {k: v for k, v in state.items() if not k.startswith(args[1] + '.')}
        state.update(json.load(sys.stdin))
    elif action != 'commit':
        sys.exit(2)
    statefile.write_text(json.dumps(state))
elif name == 'lua':
    # Native lyaml semantics are covered separately by adguard_config_test.lua.
    config = yaml.safe_load(pathlib.Path(args[1]).read_text())
    if not config.get('users'): sys.exit(1)
    config['dns']['port'] = 53
    config['dns']['upstream_dns'] = ['127.0.0.1:5053']
    pathlib.Path(args[2]).write_text(yaml.safe_dump(config))
elif name == 'dig':
    if os.environ.get('FAIL_DNS') == '1': sys.exit(1)
    print('203.0.113.1')
elif name == 'sleep':
    pass
else:
    with (base / 'services.log').open('a') as out:
        out.write(name + ' ' + ' '.join(args) + '\n')
    if args == ['enabled']: sys.exit(1)
    if args == ['running']: sys.exit(0)
'''


class ActivationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        (self.base / 'bin').mkdir()
        for name in ('uci', 'lua', 'dig', 'sleep', 'adguardhome', 'passwall2', 'dnsmasq'):
            path = self.base / 'bin' / name
            path.write_text(MOCK)
            path.chmod(0o700)
        self.config = self.base / 'adguardhome.yaml'
        self.config.write_text(yaml.safe_dump({
            'users': [{'name': 'owner', 'password': '$2a$10$test'}],
            'dns': {'port': 5353}
        }))
        self.initial = {
            'dhcp.@dnsmasq[0].port': '53',
            'dhcp.@dnsmasq[0].server': '9.9.9.9',
            'passwall2.@global[0].enabled': '1',
            'passwall2.@global[0].dns_redirect': '1',
            'passwall2.@global[0].acl_enable': '0',
        }
        self.set_state(self.initial)
        text = (ROOT / 'files/usr/sbin/k3-adguard').read_text()
        text = text.replace('/etc/adguardhome/adguardhome.yaml', str(self.config))
        text = text.replace('/tmp/k3-adguard.', str(self.base / 'transaction.'))
        for name in ('passwall2', 'adguardhome', 'dnsmasq'):
            text = text.replace('/etc/init.d/' + name, str(self.base / 'bin' / name))
        self.script = self.base / 'activate.sh'
        self.script.write_text(text)
        self.env = dict(os.environ, MOCK_ROOT=str(self.base),
                        PATH=str(self.base / 'bin') + ':' + os.environ['PATH'])

    def set_state(self, state):
        (self.base / 'state.json').write_text(json.dumps(state))

    def state(self):
        return json.loads((self.base / 'state.json').read_text())

    def run_script(self, command, **env):
        return subprocess.run(['sh', str(self.script), command],
                              env={**self.env, **env}, capture_output=True, text=True)

    def test_enable_and_disable(self):
        result = self.run_script('enable')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state()['dhcp.@dnsmasq[0].port'], '5053')
        self.assertEqual(self.state()['passwall2.@global[0].dns_redirect'], '0')
        self.assertEqual(self.state()['dhcp.@dnsmasq[0].server'], '9.9.9.9')
        self.assertEqual(yaml.safe_load(self.config.read_text())['dns']['port'], 53)
        result = self.run_script('disable')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state()['dhcp.@dnsmasq[0].port'], '53')

    def test_clients_keep_dns_after_dnsmasq_leaves_port_53(self):
        # dnsmasq only advertises itself over DHCP while listening on port 53.
        self.assertEqual(self.run_script('enable').returncode, 0)
        self.assertEqual(self.state()['dhcp.lan.dhcp_option'], ['6,0.0.0.0'])
        self.assertEqual(self.run_script('enable').returncode, 0)
        self.assertEqual(self.state()['dhcp.lan.dhcp_option'], ['6,0.0.0.0'])
        self.assertEqual(self.run_script('disable').returncode, 0)
        self.assertNotIn('dhcp.lan.dhcp_option', self.state())

    def test_owner_dns_option_is_preserved(self):
        state = {**self.initial, 'dhcp.lan.dhcp_option': ['6,192.168.1.2']}
        self.set_state(state)
        self.assertEqual(self.run_script('enable').returncode, 0)
        self.assertEqual(self.state()['dhcp.lan.dhcp_option'], ['6,192.168.1.2'])
        self.assertEqual(self.run_script('disable').returncode, 0)
        self.assertEqual(self.state()['dhcp.lan.dhcp_option'], ['6,192.168.1.2'])

    def test_dns_failure_restores_configuration(self):
        old_yaml = self.config.read_text()
        result = self.run_script('enable', FAIL_DNS='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('restored', result.stderr)
        self.assertEqual(self.state(), self.initial)
        self.assertEqual(self.config.read_text(), old_yaml)
        self.assertFalse(list(self.base.glob('transaction.*')))

    def test_uninitialized_adguard_is_rejected(self):
        self.config.write_text('users: []\ndns: {port: 5353}\n')
        result = self.run_script('enable')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state(), self.initial)

    def test_acl_is_not_silently_deleted(self):
        state = {**self.initial, 'passwall2.@global[0].acl_enable': '1'}
        self.set_state(state)
        result = self.run_script('enable')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state(), state)
        self.assertIn('ACL', result.stderr)

    def test_custom_port_is_not_overwritten(self):
        state = {**self.initial, 'dhcp.@dnsmasq[0].port': '5354'}
        self.set_state(state)
        result = self.run_script('enable')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state(), state)


if __name__ == '__main__':
    unittest.main()
