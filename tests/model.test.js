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
assert.equal(model.isValidDnsAddress("192.0.2.53"), true)
assert.equal(model.isValidDnsAddress("999.0.2.53"), false)
assert.equal(model.isValidDnsAddress("2001:db8::53"), true)
assert.equal(model.dnsForControlUrl('{"https://one.example":"192.0.2.53"}', "https://one.example/", ""), "192.0.2.53")
assert.equal(model.dnsForControlUrl("{}", "https://one.example", "198.51.100.53"), "198.51.100.53")

console.log("model tests passed")
