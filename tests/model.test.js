const assert = require("node:assert/strict")
const model = require("../Model.js")

const prefs = model.parsePrefs(JSON.stringify({
  ControlURL: "https://headscale.example.com/",
  RouteAll: true,
  ExitNodeID: "20",
  ExitNodeAllowLANAccess: true,
  CorpDNS: false,
  RunSSH: true,
  RunWebClient: false,
  ShieldsUp: true,
  AdvertiseRoutes: ["0.0.0.0/0", "::/0"],
  AutoUpdate: { Check: true, Apply: false },
  PostureChecking: true,
  Hostname: "test-node",
  OperatorUser: "alice"
}))

assert.equal(prefs.ok, true)
assert.equal(prefs.exitNodeActive, true)
assert.equal(prefs.allowLanAccess, true)
assert.equal(prefs.acceptDns, false)
assert.equal(prefs.runSsh, true)
assert.equal(prefs.shieldsUp, true)
assert.equal(prefs.advertiseExitNode, true)
assert.equal(prefs.autoUpdate, false)
assert.equal(prefs.hostname, "test-node")
assert.equal(prefs.controlUrl, "https://headscale.example.com")
assert.equal(model.parsePrefs("not json").ok, false)
assert.equal(model.isValidControlUrl("https://headscale.example.com"), true)
assert.equal(model.isValidControlUrl("javascript:alert(1)"), false)
assert.equal(model.normalizeControlUrlInput("headscale.example.com"), "https://headscale.example.com")
assert.equal(model.normalizeControlUrlInput("http://hs.example.com/"), "http://hs.example.com")
assert.equal(model.normalizeControlUrlInput(""), "")
assert.equal(model.isValidDnsAddress("192.0.2.53"), true)
assert.equal(model.isValidDnsAddress("999.0.2.53"), false)
assert.equal(model.isValidDnsAddress("2001:db8::53"), true)
assert.equal(model.dnsForControlUrl('{"https://one.example":"192.0.2.53"}', "https://one.example/", ""), "192.0.2.53")
assert.equal(model.dnsForControlUrl("{}", "https://one.example", "198.51.100.53"), "198.51.100.53")
assert.equal(model.dnsMode(true, true), "tailscale")
assert.equal(model.dnsMode(true, false), "tailscale")
assert.equal(model.dnsMode(false, true), "custom")
assert.equal(model.dnsMode(false, false), "local")

// Security hardening: oversized/truncated inputs must be rejected.
assert.equal(model.parseStatus("x".repeat(model.MAX_STATUS_INPUT + 1)).ok, false)
assert.equal(model.parsePrefs("x".repeat(model.MAX_PREFS_INPUT + 1)).ok, false)
assert.equal(model.parseAccounts("x".repeat(model.MAX_ACCOUNTS_INPUT + 1)).accounts.length, 0)
assert.equal(model.parseAccounts(JSON.stringify(Array.from({ length: model.MAX_ACCOUNTS + 10 }, () => ({ id: "a" })))).accounts.length, model.MAX_ACCOUNTS)
assert.equal(model.capString("abcde", 3), "abc")
assert.equal(model.isValidDnsAddress("2001:db8::53"), true)
assert.equal(model.isValidDnsAddress("2001:db8::53/64"), false)
assert.equal(model.isValidDnsAddress("192.0.2.53:53"), false)
assert.equal(model.isValidDnsAddress("2001:db8::53%eth0"), false)
assert.equal(model.isValidDnsAddress("a".repeat(46)), false)

console.log("model tests passed")
