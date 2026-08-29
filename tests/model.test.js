const assert = require("node:assert/strict")
const model = require("../Model.js")

const prefs = model.parsePrefs(JSON.stringify({
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
assert.equal(model.parsePrefs("not json").ok, false)

console.log("model tests passed")
