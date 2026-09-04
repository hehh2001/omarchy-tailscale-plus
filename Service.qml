import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string selfUserId: ""
  property bool fileSharing: false
  property string authUrl: ""
  property var peers: []
  property var exitNodes: []
  property var tailnetExitNodes: []
  property var mullvadExitNodes: []
  property var mullvadRegions: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string switchingAccountId: ""
  property string settingExitNodeId: ""
  property bool accountsAccessDenied: false
  property string actionStatus: ""
  property string lastError: ""
  property bool acceptDns: false
  property bool acceptRoutes: false
  property bool allowLanAccess: false
  property bool shieldsUp: false
  property bool runSsh: false
  property bool runWebClient: false
  property bool advertiseExitNode: false
  property bool updateCheck: false
  property bool autoUpdate: false
  property bool reportPosture: false
  property string hostname: ""
  property string operatorUser: ""
  property string controlUrl: ""
  property bool exitNodeActive: false
  // Desired exit node for self-heal: if Tailscale is running but the chosen
  // exit node disappears after a reconnect/idle, the next refresh reapplies it.
  property string desiredExitNodeId: ""
  property string desiredExitNodeTarget: ""
  property double lastExitNodeSelfHealMs: 0
  readonly property int exitNodeSelfHealBackoffMs: 30000
  property string changingSetting: ""
  readonly property bool manageExitNodeDns: setting("manageExitNodeDns", false) === true
  readonly property string configuredLoginServer: Model.normalizeControlUrl(setting("loginServer", "https://controlplane.tailscale.com"))
  readonly property string exitNodeDnsMap: String(setting("exitNodeDnsMap", "{}") || "{}")
  readonly property string exitNodeDns: Model.dnsForControlUrl(exitNodeDnsMap, controlUrl, setting("exitNodeDns", ""))
  // Fixed, reviewed root helper path. Never user-configurable.
  readonly property string dnsHelperPath: "/usr/local/libexec/omarchy-tailscale-plus-dns"
  readonly property string dnsMode: Model.dnsMode(acceptDns, manageExitNodeDns)

  // Trusted absolute executables. No runtime lookup through PATH.
  readonly property string tailscaleBin: "/usr/bin/tailscale"
  readonly property string timeoutBin: "/usr/bin/timeout"
  readonly property string bashBin: "/usr/bin/bash"
  readonly property string headBin: "/usr/bin/head"
  readonly property string sudoBin: "/usr/bin/sudo"
  readonly property string pkexecBin: "/usr/bin/pkexec"
  readonly property string browserBin: Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-launch-browser"
  readonly property string taildropSendBin: Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-tailscale-send"
  readonly property string wlCopyBin: "/usr/bin/wl-copy"
  readonly property string resolvectlBin: "/usr/bin/resolvectl"

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || prefsProcess.running || mullvadExitNodesProcess.running || accountsProcess.running || actionProcess.running || loginProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running || settingProcess.running || dnsProcess.running || logoutProcess.running
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _mullvadExitNodesOutput: ""
  property string _mullvadExitNodesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property string _loginProgressText: ""
  readonly property bool loginBusy: loginProcess.running
  readonly property string loginProgress: _loginProgressText
  property double _lastAccountsRefreshMs: 0
  property string _switchOutput: ""
  property string _switchError: ""
  property string _exitNodeOutput: ""
  property string _exitNodeError: ""
  property string _operatorOutput: ""
  property string _operatorError: ""
  property string _prefsOutput: ""
  property string _prefsError: ""
  property string _settingOutput: ""
  property string _settingError: ""
  property string _dnsOutput: ""
  property string _dnsError: ""
  property bool _pendingExitNodeEnable: false
  property string _pendingDnsMode: ""
  property string _pendingDnsResolver: ""
  property string _logoutOutput: ""
  property string _logoutError: ""
  // Pending control-server switch: empty string means official Tailscale.
  property string _pendingSwitchServer: ""
  property bool _pendingSwitchActive: false
  // If Tailscale operator is not authorized yet, authorize first, then continue
  // with the login that triggered it (empty string means official Tailscale).
  property string _pendingLoginAfterOperator: ""
  property bool _pendingLoginAfterOperatorActive: false

  // Build a read-only poll command that is bounded in time (timeout), stdout
  // bytes (head -c) and stderr bytes (head -c via process substitution).
  // Arguments here are fixed literals only; never pass user-controlled strings
  // through this helper.
  function cappedPollCommand(args, maxBytes, seconds) {
    var timeout = seconds === undefined || seconds === null ? "20" : String(seconds)
    var limit = String(maxBytes || 262144)
    var joined = Array.isArray(args) ? args.join(" ") : String(args || "")
    return [root.bashBin, "-c",
      "exec " + root.timeoutBin + " " + timeout + " " + root.tailscaleBin + " " + joined
        + " 2> >(exec " + root.headBin + " -c 65536 >&2)"
        + " | " + root.headBin + " -c " + limit]
  }

  function boundedCommand(seconds, base, args) {
    var list = [root.timeoutBin, String(seconds === undefined || seconds === null ? 15 : seconds), base]
    if (Array.isArray(args)) list = list.concat(args)
    return list
  }

  function stopProcess(proc) {
    if (!proc || !proc.running) return
    try {
      proc.signal(15) // SIGTERM; commands are also wrapped with timeout as a second layer.
    } catch (e) { /* ignore */ }
    proc.running = false
  }

  signal dnsModeAccepted(string mode)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function filterIPv4(ips) {
    return Model.filterIPv4(ips)
  }

  function cleanDnsName(name) {
    return Model.cleanDnsName(name)
  }

  function shortDnsName(name) {
    return Model.shortDnsName(name)
  }

  function displayHostName(hostName, dnsName) {
    return Model.displayHostName(hostName, dnsName)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function accountLabel(account) {
    return Model.accountLabel(account)
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached([root.bashBin, "-c", "printf %s " + Util.shellQuote(text) + " | " + root.wlCopyBin])
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function peerAddress(peer) {
    if (!peer) return ""
    if (peer.DNSName) return cleanDnsName(peer.DNSName)
    if (peer.HostName) return String(peer.HostName)
    var ips = filterIPv4(peer.TailscaleIPs || [])
    return ips.length > 0 ? ips[0] : ""
  }

  function canSendFiles(peer) {
    if (!fileSharing || !running || !peer) return false
    return Model.isTaildropTarget(peer, selfUserId)
  }

  function sendFile(peer) {
    if (!canSendFiles(peer)) return
    var target = peerAddress(peer)
    if (target === "") return
    Quickshell.execDetached([root.taildropSendBin, target])
  }

  function refresh(forceAccounts) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true)
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["/usr/bin/test", "-x", root.tailscaleBin]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts(forceAccounts) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = root.cappedPollCommand(["status", "--json"], Model.MAX_STATUS_INPUT, 20)
      statusProcess.running = true
      launched = true
    }
    if (!prefsProcess.running) {
      _prefsOutput = ""
      _prefsError = ""
      prefsProcess.command = root.cappedPollCommand(["debug", "prefs"], Model.MAX_PREFS_INPUT, 20)
      prefsProcess.running = true
      launched = true
    }
    if (!mullvadExitNodesProcess.running) {
      _mullvadExitNodesOutput = ""
      _mullvadExitNodesError = ""
      mullvadExitNodesProcess.command = root.cappedPollCommand(["exit-node", "list"], Model.MAX_EXIT_NODE_LIST_INPUT, 20)
      mullvadExitNodesProcess.running = true
      launched = true
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      _accountsOutput = ""
      _accountsError = ""
      _lastAccountsRefreshMs = now
      accountsProcess.command = root.cappedPollCommand(["switch", "--list", "--json"], Model.MAX_ACCOUNTS_INPUT, 20)
      accountsProcess.running = true
      launched = true
    }
    // Arm on the launch that needs watching and leave it alone after that.
    // Restarting it every refresh pushes the deadline out ahead of a hung
    // process forever once the refresh interval is shorter than the timeout,
    // and refreshIntervalSec goes down to five seconds.
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    selfUserId = ""
    fileSharing = false
    authUrl = ""
    peers = []
    exitNodes = []
    tailnetExitNodes = []
    mullvadExitNodes = []
    mullvadRegions = []
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
    switchingAccountId = ""
    settingExitNodeId = ""
    accountsAccessDenied = false
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse tailscale status"
      console.warn("tailscale", lastError)
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) openAuthUrlFrom(authUrl, false)
    selfName = parsed.selfName
    selfDnsName = parsed.selfDnsName
    selfIp = parsed.selfIp
    selfUserId = parsed.selfUserId
    fileSharing = parsed.fileSharing
    peers = parsed.running ? parsed.peers : []
    tailnetExitNodes = parsed.running ? parsed.exitNodes : []
    exitNodes = parsed.running ? tailnetExitNodes.concat(mullvadRegions) : []

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Stopped") {
      statusText = "Disconnected"
    } else {
      statusText = backendState
    }
    lastError = ""
  }

  function parseAccounts(raw) {
    var parsed = Model.parseAccounts(raw)
    accounts = parsed.accounts
    selectedAccountId = parsed.selectedAccountId
    selectedAccountLabel = parsed.selectedAccountLabel
    accountsAccessDenied = false
  }

  function parsePrefs(raw) {
    var parsed = Model.parsePrefs(raw)
    if (!parsed.ok) {
      lastError = parsed.error || "Could not read Tailscale settings"
      return
    }
    acceptDns = parsed.acceptDns
    acceptRoutes = parsed.acceptRoutes
    allowLanAccess = parsed.allowLanAccess
    shieldsUp = parsed.shieldsUp
    runSsh = parsed.runSsh
    runWebClient = parsed.runWebClient
    advertiseExitNode = parsed.advertiseExitNode
    updateCheck = parsed.updateCheck
    autoUpdate = parsed.autoUpdate
    reportPosture = parsed.reportPosture
    hostname = parsed.hostname
    operatorUser = parsed.operatorUser
    controlUrl = parsed.controlUrl
    exitNodeActive = parsed.exitNodeActive
    Qt.callLater(function() { root.maybeRestoreExitNode() })
  }

  function setBooleanPreference(key, flag, value) {
    if (!installed || settingProcess.running) return
    changingSetting = String(key || "")
    _settingOutput = ""
    _settingError = ""
    settingProcess.command = root.boundedCommand(15, root.tailscaleBin, ["set", "--" + flag + "=" + (value ? "true" : "false")])
    settingProcess.running = true
  }

  function setDnsMode(mode, resolver) {
    var next = String(mode || "")
    var requestedResolver = resolver === undefined || resolver === null ? String(exitNodeDns || "") : String(resolver || "").trim()
    if (!installed || settingProcess.running || dnsProcess.running) return
    if (next !== "tailscale" && next !== "custom" && next !== "local") return
    if (next === "custom" && requestedResolver === "") {
      lastError = "Configure an exit-node DNS server before enabling custom DNS"
      actionStatus = lastError
      actionStatusTimer.restart()
      return
    }
    if (next === "custom" && !Model.isValidDnsAddress(requestedResolver)) {
      lastError = "Exit-node DNS must be a canonical IPv4 or IPv6 address"
      actionStatus = lastError
      actionStatusTimer.restart()
      return
    }
    changingSetting = "dnsMode"
    _pendingDnsMode = next
    _pendingDnsResolver = requestedResolver
    _settingOutput = ""
    _settingError = ""
    settingProcess.command = root.boundedCommand(15, root.tailscaleBin, ["set", "--accept-dns=" + (next === "tailscale" ? "true" : "false")])
    settingProcess.running = true
  }

  function startDnsHelper(enable, resolver) {
    if (dnsProcess.running) return
    var dns = resolver === undefined || resolver === null ? String(exitNodeDns || "") : String(resolver || "")
    _dnsOutput = ""
    _dnsError = ""
    if (enable) {
      if (dns === "") return
      if (!Model.isValidDnsAddress(dns)) {
        lastError = "Exit-node DNS must be a canonical IPv4 or IPv6 address"
        actionStatus = lastError
        actionStatusTimer.restart()
        return
      }
      dnsProcess.request = "on " + dns + "\n"
    } else {
      dnsProcess.request = "off\n"
    }
    // No argv: the sudoers rule allows the fixed helper path with no arguments
    // and the action/resolver arrive on stdin.
    dnsProcess.command = root.boundedCommand(15, root.sudoBin, ["-n", root.dnsHelperPath])
    dnsProcess.running = true
  }

  function applyCustomDns(resolver) {
    if (dnsMode !== "custom" || !exitNodeActive) return
    var dns = String(resolver || "")
    startDnsHelper(dns !== "", dns)
  }
  function toggleAcceptRoutes() { setBooleanPreference("acceptRoutes", "accept-routes", !acceptRoutes) }
  function toggleAllowLanAccess() { setBooleanPreference("allowLanAccess", "exit-node-allow-lan-access", !allowLanAccess) }
  function toggleShieldsUp() { setBooleanPreference("shieldsUp", "shields-up", !shieldsUp) }
  function toggleRunSsh() { setBooleanPreference("runSsh", "ssh", !runSsh) }
  function toggleRunWebClient() { setBooleanPreference("runWebClient", "webclient", !runWebClient) }
  function toggleAdvertiseExitNode() { setBooleanPreference("advertiseExitNode", "advertise-exit-node", !advertiseExitNode) }
  function toggleUpdateCheck() { setBooleanPreference("updateCheck", "update-check", !updateCheck) }
  function toggleAutoUpdate() { setBooleanPreference("autoUpdate", "auto-update", !autoUpdate) }
  function toggleReportPosture() { setBooleanPreference("reportPosture", "report-posture", !reportPosture) }
  function normalizeControlUrl(value) { return Model.normalizeControlUrl(value) }
  function normalizeControlUrlInput(value) { return Model.normalizeControlUrlInput(value) }
  function isValidControlUrl(value) { return Model.isValidControlUrl(value) }
  function isValidDnsAddress(value) { return Model.isValidDnsAddress(value) }

  function loginArgsForServer(server) {
    var normalized = Model.normalizeControlUrlInput(server)
    // Use `up`, not `login`: after logout the `up` command prints the browser
    // auth URL (or connects immediately when an authkey is already valid).
    // `tailscale login` can authenticate silently without emitting a URL,
    // which is why the official page did not open.
    var args = ["up"]
    if (normalized !== "") args.push("--login-server=" + normalized)
    args.push("--accept-dns=" + (dnsMode === "tailscale" ? "true" : "false"))
    args.push("--accept-routes=" + (acceptRoutes ? "true" : "false"))
    args.push("--operator=" + userName)
    return args
  }

  function startLoginForServer(server) {
    var normalized = Model.normalizeControlUrlInput(server)
    if (normalized !== "" && !Model.isValidControlUrl(normalized)) {
      lastError = "Login server must be a valid http:// or https:// URL"
      actionStatus = lastError
      actionStatusTimer.restart()
      return false
    }
    // `tailscale up` needs the operator privilege unless it is run as root.
    // If the current user is not the operator yet, authorize through pkexec
    // first and continue with this login after the polkit prompt succeeds.
    if (operatorUser !== userName && !operatorProcess.running && !loginProcess.running && !logoutProcess.running) {
      _pendingLoginAfterOperator = normalized
      _pendingLoginAfterOperatorActive = true
      actionStatus = "Authorizing Tailscale operator to start login…"
      authorizeTailscaleOperator()
      return false
    }
    _loginOutput = ""
    _loginError = ""
    _loginInProgress = true
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    actionStatus = normalized === ""
      ? "Starting official Tailscale login…"
      : "Starting login for " + normalized + "…"
    _loginProgressText = normalized === ""
      ? "Connecting to official Tailscale control server…"
      : "Connecting to " + normalized + "…"
    loginProcess.command = root.boundedCommand(600, root.tailscaleBin, root.loginArgsForServer(normalized))
    loginProcess.running = true
    loginTimeoutTimer.restart()
    return true
  }

  function loginToServer(value) {
    if (!installed || loginProcess.running || logoutProcess.running) return false
    return startLoginForServer(value)
  }

  function clearPendingExitNodeState() {
    desiredExitNodeId = ""
    desiredExitNodeTarget = ""
    lastExitNodeSelfHealMs = 0
  }

  function cancelPendingLogin() {
    _loginInProgress = false
    _loginUrlOpened = true
    _loginProgressText = ""
    loginTimeoutTimer.stop()
    root.stopProcess(root.loginProcess)
    _pendingLoginAfterOperator = ""
    _pendingLoginAfterOperatorActive = false
  }

  // Switch to a different control server. Empty `value` means official
  // Tailscale (no --login-server). Tailscale requires logging out before it
  // can bind to another control server, so we chain logout → login.
  function switchTailnet(value) {
    var normalized = Model.normalizeControlUrlInput(value)
    if (!installed) return false
    if (logoutProcess.running) return false
    // If the user is switching again while a previous login is still waiting
    // for browser auth, cancel that login first so the click is not ignored.
    if (loginProcess.running) cancelPendingLogin()
    if (normalized !== "" && !Model.isValidControlUrl(normalized)) {
      lastError = "Login server must be a valid http:// or https:// URL"
      actionStatus = lastError
      actionStatusTimer.restart()
      return false
    }

    clearPendingExitNodeState()
    _pendingSwitchServer = normalized
    _pendingSwitchActive = true
    _logoutOutput = ""
    _logoutError = ""

    // A machine already bound to a control server (even if tailscaled is
    // stopped) must log out first; otherwise login stays bound to the old one.
    // needsLogin means there is no active session to log out from.
    if (running || (!needsLogin && controlUrl !== "")) {
      actionStatus = normalized === ""
        ? "Logging out, then switching to official Tailscale…"
        : "Logging out, then switching to " + normalized + "…"
      logoutProcess.command = root.boundedCommand(30, root.tailscaleBin, ["logout"])
      logoutProcess.running = true
    } else {
      _pendingSwitchActive = false
      _pendingSwitchServer = ""
      return startLoginForServer(normalized)
    }
    return true
  }

  function continuePendingSwitch() {
    if (!_pendingSwitchActive) return
    _pendingSwitchActive = false
    var server = _pendingSwitchServer
    _pendingSwitchServer = ""
    startLoginForServer(server)
  }

  function parseMullvadExitNodes(raw) {
    mullvadExitNodes = Model.parseExitNodeList(raw)
    mullvadRegions = Model.mullvadRegionOptions(mullvadExitNodes)
    exitNodes = running ? tailnetExitNodes.concat(mullvadRegions) : []
  }

  function toggleTailscale() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    // No progress status here — the greyed icon and hero line already convey
    // the optimistic off; only surface a message if the command fails.
    _desired = 0
    runAction([root.tailscaleBin, "down"])
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    var plan = Model.loginPlan(needsLogin, authUrl)
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrlFrom(plan.authUrl, true)
      return
    }
    _loginOutput = ""
    _loginError = ""
    if (needsLogin) actionStatus = "Starting Tailscale login…"
    else _desired = 1
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    var upArgs = plan.command.length > 1 ? plan.command.slice(1) : ["up"]
    loginProcess.command = root.boundedCommand(30, root.tailscaleBin, upArgs)
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running) return
    if (needsLogin || controlUrl === "") {
      actionStatus = "Saved connection needs authentication…"
      loginToServer(configuredLoginServer)
      return
    }
    _switchOutput = ""
    _switchError = ""
    switchingAccountId = accountId
    switchProcess.command = root.boundedCommand(20, root.tailscaleBin, ["switch", accountId])
    switchProcess.running = true
  }

  function exitNodeTarget(peer) {
    if (!peer) return ""
    if (peer.Mullvad === true) {
      var mullvadIps = filterIPv4(peer.TailscaleIPs || [])
      if (mullvadIps.length > 0) return mullvadIps[0]
    }
    return peerAddress(peer)
  }

  function setExitNode(peer) {
    if (!installed || !running || !peer || exitNodeProcess.running) return
    var target = exitNodeTarget(peer)
    if (target === "" || peer.ExitNode === true) return
    desiredExitNodeId = String(peer.id || target)
    desiredExitNodeTarget = target
    lastExitNodeSelfHealMs = Date.now()
    changeExitNode(target, true, desiredExitNodeId)
  }

  function clearExitNode() {
    if (!installed || !running || exitNodeProcess.running || !exitNodeActive) return
    desiredExitNodeId = ""
    desiredExitNodeTarget = ""
    lastExitNodeSelfHealMs = 0
    changeExitNode("", false, "exit:none")
  }

  function findExitNodePeer(id) {
    var wanted = String(id || "")
    if (wanted === "") return null
    var pools = [tailnetExitNodes, mullvadRegions, peers]
    for (var p = 0; p < pools.length; p++) {
      var list = Array.isArray(pools[p]) ? pools[p] : []
      for (var i = 0; i < list.length; i++) {
        var item = list[i] || {}
        if (String(item.id || "") === wanted) return item
      }
    }
    return null
  }

  // After an idle timeout/reconnect Tailscale may come back without the exit
  // node route. Reapply the user's last selection on a later refresh (throttled).
  function maybeRestoreExitNode() {
    if (!installed || !running || desiredExitNodeId === "") return
    if (exitNodeActive || exitNodeProcess.running || settingProcess.running) return
    var now = Date.now()
    if (now - lastExitNodeSelfHealMs < exitNodeSelfHealBackoffMs) return
    lastExitNodeSelfHealMs = now
    var peer = findExitNodePeer(desiredExitNodeId)
    var target = peer ? exitNodeTarget(peer) : desiredExitNodeTarget
    if (target !== "") changeExitNode(target, true, desiredExitNodeId)
  }

  function changeExitNode(target, enable, id) {
    _exitNodeOutput = ""
    _exitNodeError = ""
    settingExitNodeId = String(id || "")
    _pendingExitNodeEnable = enable === true
    var args = ["set", "--exit-node=" + target]
    // Custom exit-node DNS and Tailscale-managed DNS are mutually exclusive.
    // Keep accept-dns disabled after disconnect as well so the local uplink
    // resolver can take over when the helper reverts tailscale0.
    if (dnsMode === "custom") args.push("--accept-dns=false")
    exitNodeProcess.command = root.boundedCommand(20, root.tailscaleBin, args)
    exitNodeProcess.running = true
  }

  function authorizeTailscaleOperator() {
    if (!installed || operatorProcess.running || userName === "") return
    _operatorOutput = ""
    _operatorError = ""
    actionStatus = "Authorizing Tailscale operator..."
    operatorProcess.command = root.boundedCommand(60, root.pkexecBin, [root.tailscaleBin, "set", "--operator=" + userName])
    operatorProcess.running = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = root.boundedCommand(20, command[0], command.slice(1))
    actionProcess.running = true
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      // Turning on ended up needing browser auth — stop pretending we're up.
      _desired = -1
      _loginUrlOpened = true
      _loginInProgress = false
      loginTimeoutTimer.stop()
      _loginProgressText = "Authentication page opened — complete sign-in in the browser…"
      Quickshell.execDetached([root.browserBin, url])
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(text, false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every poll is skipped while its own process is still running, so one that
    // never exits — tailscale can hang on a network that is coming and going —
    // silently stops the panel refreshing at all, and it stays stopped. Reap
    // anything still running well inside the refresh interval so the next tick
    // starts clean.
    //
    // This watchdog intentionally covers only the recurring poll processes.
    // Action/login/logout/switch processes already carry their own `timeout`
    // wrapper and must not be killed by a 15s refresh watchdog (e.g. browser
    // authentication can legitimately take longer than 15 seconds).
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      root.stopProcess(statusProcess)
      root.stopProcess(prefsProcess)
      root.stopProcess(mullvadExitNodesProcess)
      root.stopProcess(accountsProcess)
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return
      // Do not kill `tailscale up` here: the command has its own 600s timeout.
      // Just surface that the control server is slow/unreachable so the user
      // sees progress instead of thinking the click did nothing.
      if (!root.openAuthUrlFrom(root.authUrl, true)) {
        root._loginProgressText = "Control server is not responding yet — still trying (up to 10 minutes)…"
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = stderr.trim()
      }
    }
  }

  Process {
    id: prefsProcess
    running: false
    command: []
    stdout: StdioCollector { id: prefsStdout; waitForEnd: true; onStreamFinished: root._prefsOutput = text }
    stderr: StdioCollector { id: prefsStderr; waitForEnd: true; onStreamFinished: root._prefsError = text }
    onExited: function(exitCode) {
      var stdout = String(prefsStdout.text || root._prefsOutput || "")
      var stderr = String(prefsStderr.text || root._prefsError || "")
      if (exitCode === 0) root.parsePrefs(stdout)
      else root.lastError = elideStatus(stderr || "Could not read Tailscale settings")
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountsStdout; waitForEnd: true; onStreamFinished: root._accountsOutput = text }
    stderr: StdioCollector { id: accountsStderr; waitForEnd: true; onStreamFinished: root._accountsError = text }
    onExited: function(exitCode) {
      var stdout = String(accountsStdout.text || root._accountsOutput || "")
      var stderr = String(accountsStderr.text || root._accountsError || "")
      if (exitCode === 0) root.parseAccounts(stdout)
      else {
        root.parseAccounts("")
        if (/profiles access denied/i.test(stderr) || /profiles access denied/i.test(stdout)) {
          root.accountsAccessDenied = true
          root.lastError = "Authorize Tailscale operator to show connections"
        } else {
          root.lastError = elideStatus(stderr || stdout || "Could not list Tailscale connections")
        }
      }
    }
  }

  Process {
    id: mullvadExitNodesProcess
    running: false
    command: []
    stdout: StdioCollector { id: mullvadExitNodesStdout; waitForEnd: true; onStreamFinished: root._mullvadExitNodesOutput = text }
    stderr: StdioCollector { id: mullvadExitNodesStderr; waitForEnd: true; onStreamFinished: root._mullvadExitNodesError = text }
    onExited: function(exitCode) {
      var stdout = String(mullvadExitNodesStdout.text || root._mullvadExitNodesOutput || "")
      if (exitCode === 0) root.parseMullvadExitNodes(stdout)
      else root.parseMullvadExitNodes("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = elideStatus(stderr || stdout || "Tailscale command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined, true)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root._loginProgressText = ""
        var detail = combined || "tailscale up failed"
        if (exitCode === 124 || /timed out|context canceled/i.test(detail)) {
          detail = "Could not reach the control server or the login timed out"
        }
        root.lastError = elideStatus(detail)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
        root._loginProgressText = ""
      } else if (exitCode === 0) {
        // Authentication completed and tailscale up exited successfully.
        root._loginProgressText = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: logoutProcess
    running: false
    command: []
    stdout: StdioCollector { id: logoutStdout; waitForEnd: true; onStreamFinished: root._logoutOutput = text }
    stderr: StdioCollector { id: logoutStderr; waitForEnd: true; onStreamFinished: root._logoutError = text }
    onExited: function(exitCode) {
      var stdout = String(logoutStdout.text || root._logoutOutput || "")
      var stderr = String(logoutStderr.text || root._logoutError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Tailscale logout failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        root._pendingSwitchActive = false
        root._pendingSwitchServer = ""
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastAccountsRefreshMs = 0
        if (root._pendingSwitchActive) root.continuePendingSwitch()
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: switchProcess
    running: false
    command: []
    stdout: StdioCollector { id: switchStdout; waitForEnd: true; onStreamFinished: root._switchOutput = text }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true; onStreamFinished: root._switchError = text }
    onExited: function(exitCode) {
      var stdout = String(switchStdout.text || root._switchOutput || "")
      var stderr = String(switchStderr.text || root._switchError || "")
      if (exitCode !== 0) {
        if (/profile not found|no such profile/i.test(stderr + "\n" + stdout)) {
          root.lastError = "Saved connection expired; starting a fresh login"
          root.actionStatus = root.lastError
          Qt.callLater(function() { root.loginToServer(root.configuredLoginServer) })
        } else {
          root.lastError = elideStatus(stderr || stdout || "Account switch failed")
          root.actionStatus = root.lastError
          actionStatusTimer.restart()
        }
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastAccountsRefreshMs = 0
      }
      root.switchingAccountId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: exitNodeProcess
    running: false
    command: []
    stdout: StdioCollector { id: exitNodeStdout; waitForEnd: true; onStreamFinished: root._exitNodeOutput = text }
    stderr: StdioCollector { id: exitNodeStderr; waitForEnd: true; onStreamFinished: root._exitNodeError = text }
    onExited: function(exitCode) {
      var stdout = String(exitNodeStdout.text || root._exitNodeOutput || "")
      var stderr = String(exitNodeStderr.text || root._exitNodeError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Exit node selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        if (root.dnsMode === "custom") root.startDnsHelper(root._pendingExitNodeEnable, root.exitNodeDns)
      }
      root.settingExitNodeId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: settingProcess
    running: false
    command: []
    stdout: StdioCollector { id: settingStdout; waitForEnd: true; onStreamFinished: root._settingOutput = text }
    stderr: StdioCollector { id: settingStderr; waitForEnd: true; onStreamFinished: root._settingError = text }
    onExited: function(exitCode) {
      var stdout = String(settingStdout.text || root._settingOutput || "")
      var stderr = String(settingStderr.text || root._settingError || "")
      var requestedDnsMode = root._pendingDnsMode
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Tailscale setting failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        if (requestedDnsMode !== "") {
          root.dnsModeAccepted(requestedDnsMode)
          root.startDnsHelper(requestedDnsMode === "custom" && root.exitNodeActive, root._pendingDnsResolver)
        }
      }
      root._pendingDnsMode = ""
      root._pendingDnsResolver = ""
      root.changingSetting = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: dnsProcess
    running: false
    command: []
    property string request: ""
    stdinEnabled: true
    onStarted: {
      write(request)
      request = ""
    }
    stdout: StdioCollector { id: dnsStdout; waitForEnd: true; onStreamFinished: root._dnsOutput = text }
    stderr: StdioCollector { id: dnsStderr; waitForEnd: true; onStreamFinished: root._dnsError = text }
    onExited: function(exitCode) {
      var stdout = String(dnsStdout.text || root._dnsOutput || "")
      var stderr = String(dnsStderr.text || root._dnsError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Exit-node DNS helper is not installed or authorized")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: operatorProcess
    running: false
    command: []
    stdout: StdioCollector { id: operatorStdout; waitForEnd: true; onStreamFinished: root._operatorOutput = text }
    stderr: StdioCollector { id: operatorStderr; waitForEnd: true; onStreamFinished: root._operatorError = text }
    onExited: function(exitCode) {
      var stdout = String(operatorStdout.text || root._operatorOutput || "")
      var stderr = String(operatorStderr.text || root._operatorError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Tailscale authorization failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
        root._pendingLoginAfterOperator = ""
        root._pendingLoginAfterOperatorActive = false
      } else {
        root.accountsAccessDenied = false
        root.operatorUser = root.userName
        root.lastError = ""
        root.actionStatus = "Tailscale operator authorized"
        actionStatusTimer.restart()
        root._lastAccountsRefreshMs = 0
        if (root._pendingLoginAfterOperatorActive) {
          var server = root._pendingLoginAfterOperator
          root._pendingLoginAfterOperator = ""
          root._pendingLoginAfterOperatorActive = false
          root.startLoginForServer(server)
        }
      }
      delayedRefresh.restart()
    }
  }
}
