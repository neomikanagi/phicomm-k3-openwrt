-- SPDX-License-Identifier: GPL-2.0-only
-- Called only while AdGuard Home is stopped; parse YAML, never regex-edit live config.
local yaml = require('lyaml')
local input, output = assert(arg[1]), assert(arg[2])
local f = assert(io.open(input, 'r'))
local config = assert(yaml.load(f:read('*a')))
f:close()
assert(type(config) == 'table', 'Invalid AdGuard config')
assert(type(config.users) == 'table' and #config.users > 0,
    'Complete the AdGuard wizard and set an administrator password first')
for _, user in ipairs(config.users) do
    assert(type(user.password) == 'string' and user.password:match('^%$2[aby]%$'),
        'An authenticated AdGuard administrator is required')
end
assert(type(config.dns) == 'table', 'No DNS configuration')
assert(config.dns.port == 5353 or config.dns.port == 53,
    'Wizard DNS port must be 5353 (or an already activated 53)')
config.dns.port = 53
-- DHCPv6/RA can advertise the router's IPv6 DNS too. Keep the frontend dual-stack;
-- the official firewall continues to reject unsolicited WAN DNS traffic.
config.dns.bind_hosts = {'0.0.0.0', '::'}
config.dns.upstream_dns = {'127.0.0.1:5053'}
config.dns.upstream_dns_file = ''
config.dns.fallback_dns = {}
config.dns.bootstrap_dns = {'1.1.1.1', '9.9.9.9'}
config.dns.local_ptr_upstreams = {'127.0.0.1:5053'}
config.dns.use_private_ptr_resolvers = true
config.dns.cache_size = 4194304
-- Avoid a DNS loop from AGH's upstream to itself, and avoid NAND query-log writes.
config.querylog = config.querylog or {}
config.querylog.enabled = false
config.statistics = config.statistics or {}
config.statistics.enabled = false
config.dhcp = config.dhcp or {}
config.dhcp.enabled = false
local out = assert(io.open(output, 'w'))
assert(out:write(yaml.dump({config})))
assert(out:close())
