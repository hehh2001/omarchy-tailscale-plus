const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')
const { spawnSync } = require('node:child_process')
const Model = require('../Model.js')
const source = fs.readFileSync(require.resolve('../Service.qml'), 'utf8')
function fn(name) {
  const match = source.match(new RegExp('^  function ' + name + '\\([^]*?^  }', 'm'))
  assert.ok(match, name)
  return match[0]
}
function callback(process) {
  const block = source.slice(source.indexOf('    id: ' + process + '\n'))
  const match = block.match(/    onExited: (function\(exitCode\) \{[^]*?^    })/m)
  return '(' + match[1] + ')(exitCode)'
}
function harness() {
  const c = { Model, Date: { now: () => 100000 }, installed: true, running: true,
    _statusValid: true, _prefsValid: true, _networkGeneration: 0,
    exitNodeActive: true, exitNodeDns: '192.0.2.53', dnsMode: 'custom', dnsContext: 'profile-a',
    _dnsOwned: false, _lastDnsAttemptMs: 0, networkActionBusy: false,
    prefsProcess: {running:false}, statusProcess:{running:false}, dnsStatusProcess:{running:false},
    dnsProcess:{running:false}, settingProcess:{running:false},
    timeoutBin:'/usr/bin/timeout',bashBin:'/usr/bin/bash',resolvectlBin:'/usr/bin/resolvectl',
    calls:[],startDnsHelper(enable, resolver){c.calls.push([enable,resolver]);c._lastDnsAttemptMs=c.Date.now()},
    delayedRefresh:{restart(){}},actionStatusTimer:{restart(){}},
    elideStatus: x=>x, finishDnsModeChange(){c.calls.push(['mode'])} }
  c.root=c
  vm.createContext(c)
  vm.runInContext(fn('boundedCommand')+'\n'+fn('checkCustomDns')+'\n'+fn('beginNetworkAction'),c)
  return c
}
const ready = JSON.stringify([{ifname:'tailscale0',defaultRoute:true,servers:[{addressString:'192.0.2.53'}],searchDomains:[{name:'.',routeOnly:true}]}])
const missing = JSON.stringify([{ifname:'tailscale0',defaultRoute:true,servers:[],searchDomains:[]}])
assert.equal(Model.resolvedDnsState(ready,'192.0.2.53'),'ready')
assert.equal(Model.resolvedDnsState(missing,'192.0.2.53'),'missing')
assert.equal(Model.resolvedDnsState('truncated','192.0.2.53'),'unknown')
assert.equal(Model.resolvedDnsState(ready.replace('192.0.2.53','2001:db8::53'),'2001:0db8:0:0:0:0:0:0053'),'ready')
for (const invalid of ['1:2:3','12345::1','1::2::3','1:2:3:4:5:6:7:8::',':::','192.0.2.53;id']) assert.equal(Model.isValidDnsAddress(invalid),false,invalid)
for (const valid of ['::','::1','2001:db8::53','1:2:3:4:5:6:7:8','1:2:3:4:5:6:7::']) assert.equal(Model.isValidDnsAddress(valid),true,valid)
let c=harness()
c.checkCustomDns()
assert.equal(c.dnsStatusProcess.running,true)
function dnsResult(c,text,context='profile-a',code=0){c.context=context;c.exitCode=code;c.dnsStatusStdout={text};vm.runInContext(callback('dnsStatusProcess'),c)}
dnsResult(c,ready);assert.equal(c.calls.length,0)
dnsResult(c,missing);assert.equal(c.calls.length,1)
dnsResult(c,missing);assert.equal(c.calls.length,1,'backoff after DNS loss')
c.Date.now=()=>131000;dnsResult(c,missing);assert.equal(c.calls.length,2,'retry transient failure')
c.Date.now=()=>162000;dnsResult(c,ready);dnsResult(c,missing);assert.equal(c.calls.length,3,'second network loss in same session')
c.Date.now=()=>193000;dnsResult(c,missing,'previous-profile');assert.equal(c.calls.length,3,'discard old probe')
c.beginNetworkAction();dnsResult(c,missing);assert.equal(c.calls.length,3,'no mutation based on stale prefs')
c=harness();c.networkActionBusy=true;c.checkCustomDns();assert.equal(c.dnsStatusProcess.running,false)
c=harness();c.dnsMode='tailscale';c.checkCustomDns();assert.equal(c.dnsStatusProcess.running,false,'do not overwrite Tailscale DNS')
c=harness();c.running=false;c._dnsOwned=true;c.checkCustomDns();assert.equal(c.calls[0][0],false,'release owned DNS when stopped')
c=harness();c._dnsThenMode=true;c.context='profile-a';c.enabling=false;c.exitCode=0;c.dnsStdout={text:''};c.dnsStderr={text:''};vm.runInContext(callback('dnsProcess'),c);assert.deepEqual(c.calls,[['mode']],'DNS release precedes DNS enable')
c=harness();c._dnsThenMode=true;c.context='profile-a';c.enabling=false;c.exitCode=1;c.dnsStdout={text:''};c.dnsStderr={text:'permission denied'};vm.runInContext(callback('dnsProcess'),c);assert.equal(c.calls.length,0);assert.equal(c.dnsError,'permission denied')
const offline=Model.parseStatus(JSON.stringify({BackendState:'Running',ExitNodeStatus:{ID:'20',Online:false},Peer:{key:{ID:'20',Online:false,ExitNode:true,ExitNodeOption:true,HostName:'gateway'}}}))
assert.equal(offline.exitNodes.length,1);assert.equal(offline.peers.length,0);assert.equal(offline.exitNodeOnline,false)
assert.equal(Model.parsePrefs('{"ExitNodeID":"20"}').exitNodeActive,true)
assert.equal(Model.parsePrefs('{"ExitNodeIP":"100.64.0.1"}').exitNodeActive,true)
assert.equal(Model.parsePrefs('{}').exitNodeActive,false)
// Exercise the real command wrapper with harmless child processes.
c=harness()
function run(args){const command=c.boundedCommand(2,'/usr/bin/node',args,129);return spawnSync(command[0],command.slice(1),{encoding:'utf8',timeout:5000})}
let result=run(['-e','process.exit(7)']);assert.equal(result.status,7,'pipeline must preserve command failure')
result=run(['-e','process.stdout.write(process.argv[1])','$(id); `id`; literal']);assert.equal(result.stdout,'$(id); `id`; literal','argv must never become shell code')
result=run(['-e','process.stdout.write("x".repeat(100000));process.stderr.write("e".repeat(100000))']);assert.ok(result.stdout.length<=129);assert.ok(result.stderr.length<=65536)
result=run(['-e','setInterval(()=>{},1000)']);assert.equal(result.status,124,'timeout must terminate command')
console.log('recovery, DNS transitions, stale results, IPv6, and process-boundary tests passed')
const helper = fs.readFileSync(require.resolve('../scripts/omarchy-tailscale-plus-dns'),'utf8')
const validators = ['valid_ipv4','valid_ipv6'].map(name => helper.match(new RegExp('^'+name+'\\(\\) \\{[^]*?^}', 'm'))[0]).join('\n')
for (const [value,valid] of [['192.0.2.53',true],['192.0.2.53.',false],['01.2.3.4',false],['::',true],['2001:db8::53',true],['12345::1',false],['1:2:3',false],['1::2::3',false],['1:2:3:4:5:6:7:8',true]]) {
  const result=spawnSync('/usr/bin/bash',['-c',validators+'\nvalid_ipv4 "$1" || valid_ipv6 "$1"','test',value])
  assert.equal(result.status===0,valid,'root helper validation: '+value)
}
console.log('root helper address validation passed')
