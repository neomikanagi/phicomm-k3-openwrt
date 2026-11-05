local yaml = require('lyaml')
local function run(config, expect_ok)
    local path = os.tmpname()
    local out = path .. '.out'
    local f = assert(io.open(path, 'w'))
    f:write(yaml.dump({config})); f:close()
    arg = {path, out}
    local ok = pcall(dofile, 'files/usr/share/k3/adguard-config.lua')
    assert(ok == expect_ok, 'Unexpected config validation result')
    if ok then
        local reader = assert(io.open(out, 'r'))
        local result = yaml.load(reader:read('*a')); reader:close()
        assert(result.dns.port == 53)
        assert(result.dns.upstream_dns[1] == '127.0.0.1:5053')
        assert(#result.dns.fallback_dns == 0)
        assert(result.dns.upstream_dns_file == '')
        assert(result.querylog.enabled == false)
        assert(result.statistics.enabled == false)
        assert(result.dhcp.enabled == false)
        assert(result.http.address == '192.168.1.1:3000')
        assert(result.users[1].name == 'owner')
        assert(result.dns.bind_hosts[1] == '0.0.0.0')
        assert(result.dns.bind_hosts[2] == '::')
        os.remove(out)
    end
    os.remove(path)
end
local function fixture()
    return {
        users = {{name = 'owner', password = '$2a$10$dummyhash'}},
        dns = {port = 5353, bind_hosts = {'0.0.0.0'}, upstream_dns_file = '/tmp/old'},
        http = {address = '192.168.1.1:3000'},
        querylog = {enabled = true}, statistics = {enabled = true}, dhcp = {enabled = true}
    }
end
run(fixture(), true)
local c = fixture(); c.users = {}; run(c, false)
c = fixture(); c.users[1].password = ''; run(c, false)
c = fixture(); c.dns.port = 54; run(c, false)
c = fixture(); c.dns.port = 53; run(c, true)
print('AdGuard YAML validation and round-trip tests passed')
