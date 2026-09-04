// Hard limits for hostile/oversized Tailscale output. JSON parsing happens
// only after these bounds are enforced by the calling layer; these constants
// are shared with QML for display/error messages and with Node tests.
var MAX_STATUS_INPUT = 1048576      // 1 MiB
var MAX_ACCOUNTS_INPUT = 262144     // 256 KiB
var MAX_PREFS_INPUT = 65536         // 64 KiB
var MAX_EXIT_NODE_LIST_INPUT = 262144
var MAX_PEERS = 20000
var MAX_EXIT_NODES = 5000
var MAX_ACCOUNTS = 200
var MAX_MULLVAD_NODES = 5000
var MAX_STRING_LENGTH = 4096
var MAX_IP_LIST = 16
var MAX_TAGS = 256

function capString(value, max) {
  var text = String(value || "")
  var limit = max === undefined || max === null ? MAX_STRING_LENGTH : Number(max)
  if (text.length > limit) text = text.substring(0, limit)
  return text
}

function capStringArray(value, max) {
  var list = Array.isArray(value) ? value : []
  var limit = max === undefined || max === null ? MAX_IP_LIST : Number(max)
  if (list.length > limit) list = list.slice(0, limit)
  var result = []
  for (var i = 0; i < list.length; i++) result.push(capString(list[i]))
  return result
}

function capTags(value) {
  var list = Array.isArray(value) ? value : []
  if (list.length > MAX_TAGS) list = list.slice(0, MAX_TAGS)
  var result = []
  for (var i = 0; i < list.length; i++) result.push(capString(list[i], MAX_STRING_LENGTH))
  return result
}

function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  var limit = Math.min(ips.length, MAX_IP_LIST)
  for (var i = 0; i < limit; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function filterIPv6(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  var limit = Math.min(ips.length, MAX_IP_LIST)
  for (var i = 0; i < limit; i++) {
    var ip = String(ips[i] || "")
    if (/^fd7a:115c:a1e0:/i.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortDnsName(name) {
  var clean = cleanDnsName(name)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return shortDnsName(dnsName) || host || "Unknown"
}

function isMullvadHost(name) {
  var value = String(name || "").toLowerCase()
  var suffix = ".mullvad.ts.net"
  return value.length > suffix.length && value.indexOf(suffix) === value.length - suffix.length
}

function isMullvadPeer(peer) {
  var hostName = String((peer && peer.HostName) || "")
  var dnsName = cleanDnsName((peer && peer.DNSName) || "")
  return isMullvadHost(dnsName) || isMullvadHost(hostName)
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  if (value === "mullvad") return "󰖂"
  return "󰟀"
}

function accountLabel(account) {
  if (!account) return "Unknown account"
  if (account.nickname) return String(account.nickname)
  if (account.tailnet) return String(account.tailnet)
  if (account.account) return String(account.account)
  return String(account.id || "Unknown account")
}

function loginPlan(needsLogin, authUrl) {
  var url = String(authUrl || "").trim()
  if (needsLogin === true && /^https?:\/\//.test(url)) {
    return { authUrl: url, command: [] }
  }
  return { authUrl: "", command: ["tailscale", "up"] }
}

// Taildrop is a tailnet feature the admin can turn off, so the button for it
// only makes sense when this profile actually carries the capability.
function hasFileSharing(self) {
  var capability = "https://tailscale.com/cap/file-sharing"
  var capMap = (self && self.CapMap) || null
  if (capMap && capMap[capability] !== undefined) return true
  var capabilities = (self && self.Capabilities) || []
  for (var i = 0; i < capabilities.length; i++) {
    if (String(capabilities[i]) === capability) return true
  }
  return false
}

// Tailscale grades every peer itself — offline, wrong owner, an OS without
// Taildrop, no peer API — so take its word when the status carries one, and
// fall back to same-owner for daemons too old to say.
function isTaildropTarget(peer, selfUserId) {
  var target = peer && peer.TaildropTarget
  if (typeof target === "number" && target !== 0) return target === 1
  var owner = String((peer && peer.UserID) || "")
  return owner !== "" && owner === String(selfUserId || "")
}

function peerFromStatus(id, peer) {
  return {
    id: capString(id),
    HostName: displayHostName(capString(peer.HostName), capString(peer.DNSName)),
    UserID: capString(peer.UserID),
    TaildropTarget: typeof peer.TaildropTarget === "number" ? peer.TaildropTarget : 0,
    DNSName: cleanDnsName(capString(peer.DNSName)),
    DisplayName: displayHostName(capString(peer.HostName), capString(peer.DNSName)),
    TailscaleIPs: filterIPv4(peer.TailscaleIPs || []),
    TailscaleIPv6: filterIPv6(peer.TailscaleIPs || []),
    Online: peer.Online === true,
    OS: capString(peer.OS, 128),
    Tags: capTags(peer.Tags),
    ExitNodeOption: peer.ExitNodeOption === true,
    ExitNode: peer.ExitNode === true,
    Mullvad: isMullvadPeer(peer)
  }
}

function sliceTableColumn(line, start, end) {
  var text = String(line || "")
  if (start < 0 || start >= text.length) return ""
  if (end < 0) return text.substring(start).trim()
  return text.substring(start, Math.min(end, text.length)).trim()
}

function parseExitNodeList(raw) {
  var text = String(raw || "")
  if (text.length > MAX_EXIT_NODE_LIST_INPUT) return []
  var lines = text.split(/\r?\n/)
  var header = ""
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*IP\s+HOSTNAME\s+COUNTRY\s+CITY\s+STATUS\s*$/.test(lines[i])) {
      header = lines[i]
      headerIndex = i
      break
    }
  }
  if (headerIndex === -1) return []

  var ipStart = header.indexOf("IP")
  var hostStart = header.indexOf("HOSTNAME")
  var countryStart = header.indexOf("COUNTRY")
  var cityStart = header.indexOf("CITY")
  var statusStart = header.indexOf("STATUS")
  var byHost = {}

  for (var j = headerIndex + 1; j < lines.length; j++) {
    if (Object.keys(byHost).length >= MAX_MULLVAD_NODES) break
    var line = lines[j]
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue

    var ip = sliceTableColumn(line, ipStart, hostStart)
    var host = sliceTableColumn(line, hostStart, countryStart)
    var country = sliceTableColumn(line, countryStart, cityStart)
    var city = sliceTableColumn(line, cityStart, statusStart)
    var status = sliceTableColumn(line, statusStart, -1)
    if (!isMullvadHost(host)) continue

    byHost[host] = {
      id: "mullvad:" + host,
      HostName: capString(host),
      DNSName: capString(host),
      DisplayName: capString((city && city !== "Any" ? city + ", " : "") + country),
      TailscaleIPs: ip ? [capString(ip, 64)] : [],
      TailscaleIPv6: [],
      Online: true,
      OS: "mullvad",
      Tags: [],
      ExitNodeOption: true,
      ExitNode: status !== "" && status !== "-",
      Mullvad: true,
      Country: capString(country, 128),
      City: capString(city, 128),
      Status: capString(status, 64)
    }
  }

  var result = []
  for (var hostName in byHost) result.push(byHost[hostName])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.DisplayName).localeCompare(String(b.DisplayName))
  })
  return result
}

function mullvadRegionOptions(nodes) {
  var byRegion = {}
  var values = Array.isArray(nodes) ? nodes : []
  for (var i = 0; i < values.length; i++) {
    var node = values[i] || {}
    if (node.Mullvad !== true) continue
    var country = String(node.Country || "").trim()
    var city = String(node.City || "").trim()
    if (country === "") continue
    if (city === "" || city === "Any") continue

    var key = country + "\n" + city
    if (byRegion[key]) continue

    var option = {}
    for (var propertyName in node) option[propertyName] = node[propertyName]
    option.id = "mullvad-region:" + key
    option.DisplayName = city + ", " + country
    option.Country = country
    option.City = city
    option.MullvadRegion = true
    byRegion[key] = option
  }

  var result = []
  for (var name in byRegion) result.push(byRegion[name])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.City).localeCompare(String(b.City))
  })
  return result
}

function mullvadCountryOptions(nodes) {
  return mullvadRegionOptions(nodes)
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }
  if (text.length > MAX_STATUS_INPUT) return { ok: false, unavailable: true, message: "Status error", error: "Tailscale status output exceeded the safety limit" }

  try {
    var data = JSON.parse(text)
    var backendState = String(data.BackendState || "Unknown")
    var self = data.Self || {}
    var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || [])
    var peers = []
    var exitNodes = []
    var rawPeers = data.Peer || {}

    for (var id in rawPeers) {
      if (peers.length >= MAX_PEERS || exitNodes.length >= MAX_EXIT_NODES) {
        return { ok: false, unavailable: true, message: "Status error", error: "Tailscale status exceeded peer/exit-node safety limits" }
      }
      var peer = rawPeers[id] || {}
      var normalized = peerFromStatus(id, peer)
      if (normalized.Mullvad) continue
      if (normalized.Online) {
        peers.push(normalized)
        if (normalized.ExitNodeOption) exitNodes.push(normalized)
      }
    }

    peers.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })
    exitNodes.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    return {
      ok: true,
      unavailable: false,
      backendState: capString(backendState, 128),
      running: backendState === "Running",
      needsLogin: backendState === "NeedsLogin",
      authUrl: capString(data.AuthURL, 1024),
      selfName: displayHostName(capString(self.HostName), capString(self.DNSName)),
      selfDnsName: cleanDnsName(capString(self.DNSName)),
      selfIp: selfIps.length > 0 ? selfIps[0] : "",
      selfUserId: capString(self.UserID, 128),
      fileSharing: hasFileSharing(self),
      peers: peers,
      exitNodes: exitNodes
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse tailscale status" }
  }
}

function parseAccounts(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }
  if (text.length > MAX_ACCOUNTS_INPUT) return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }

  try {
    var parsed = JSON.parse(text)
    var next = []
    var selected = null
    if (parsed && typeof parsed.length === "number") {
      for (var i = 0; i < parsed.length && next.length < MAX_ACCOUNTS; i++) {
        var rawAccount = parsed[i] || {}
        var account = {
          id: capString(rawAccount.id || rawAccount.ID, 512),
          nickname: capString(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name),
          tailnet: capString(rawAccount.tailnet || rawAccount.Tailnet),
          account: capString(rawAccount.account || rawAccount.Account || rawAccount.loginName || rawAccount.LoginName || rawAccount.user || rawAccount.User),
          selected: rawAccount.selected === true || rawAccount.Selected === true
        }
        next.push(account)
        if (account.selected === true) selected = account
      }
    }
    return {
      accounts: next,
      selectedAccountId: selected ? String(selected.id || "") : "",
      selectedAccountLabel: selected ? accountLabel(selected) : ""
    }
  } catch (e) {
    return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }
  }
}

function parsePrefs(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "Empty Tailscale preferences" }
  if (text.length > MAX_PREFS_INPUT) return { ok: false, error: "Tailscale preferences output exceeded the safety limit" }
  try {
    var data = JSON.parse(text)
    var autoUpdate = data.AutoUpdate || {}
    var appConnector = data.AppConnector || {}
    return {
      ok: true,
      acceptDns: data.CorpDNS === true,
      acceptRoutes: data.RouteAll === true,
      allowLanAccess: data.ExitNodeAllowLANAccess === true,
      shieldsUp: data.ShieldsUp === true,
      runSsh: data.RunSSH === true,
      runWebClient: data.RunWebClient === true,
      advertiseExitNode: Array.isArray(data.AdvertiseRoutes) && data.AdvertiseRoutes.indexOf("0.0.0.0/0") !== -1,
      advertiseConnector: appConnector.Advertise === true,
      updateCheck: autoUpdate.Check === true,
      autoUpdate: autoUpdate.Apply === true,
      reportPosture: data.PostureChecking === true,
      hostname: capString(data.Hostname),
      operatorUser: capString(data.OperatorUser, 256),
      controlUrl: normalizeControlUrl(capString(data.ControlURL, 2048)),
      exitNodeId: capString(data.ExitNodeID, 512),
      exitNodeActive: String(data.ExitNodeID || "") !== ""
    }
  } catch (e) {
    return { ok: false, error: "Failed to parse Tailscale preferences" }
  }
}

function normalizeControlUrl(value) {
  var text = String(value || "").trim()
  while (text.length > 0 && text.charAt(text.length - 1) === "/") text = text.slice(0, -1)
  return text
}

function normalizeControlUrlInput(value) {
  var text = String(value || "").trim()
  if (text === "") return ""
  // Convenience: allow users to type headscale.example.com without a scheme.
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(text)) text = "https://" + text
  return normalizeControlUrl(text)
}

function isValidControlUrl(value) {
  var text = normalizeControlUrl(value)
  return /^https?:\/\/[^\s/]+(?::[0-9]{1,5})?(?:\/[^\s]*)?$/.test(text)
}

function isValidDnsAddress(value) {
  var text = String(value || "").trim()
  if (text.length === 0 || text.length > 45) return false

  var ipv4 = /^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$/
  if (ipv4.test(text)) return true

  // IPv6: hex digits and colons only, no zone/prefix, sane length.
  if (text.indexOf(":") === -1 || !/^[0-9a-fA-F:]+$/.test(text)) return false
  var doubleColon = text.indexOf("::")
  if (doubleColon !== -1 && text.indexOf("::", doubleColon + 2) !== -1) return false
  if (doubleColon === -1 && (text.charAt(0) === ":" || text.charAt(text.length - 1) === ":")) return false
  var groups = text.split(":")
  var colons = groups.length - 1
  return colons >= 2 && colons <= 7
}

function parseDnsMap(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
  } catch (e) {
    return {}
  }
}

function dnsForControlUrl(rawMap, controlUrl, fallback) {
  var map = parseDnsMap(rawMap)
  var key = normalizeControlUrl(controlUrl)
  var value = String(map[key] || "").trim()
  return value !== "" ? value : String(fallback || "").trim()
}

function dnsMode(acceptDns, manageExitNodeDns) {
  if (acceptDns === true) return "tailscale"
  return manageExitNodeDns === true ? "custom" : "local"
}

if (typeof module !== "undefined") {
  module.exports = {
    MAX_STATUS_INPUT: MAX_STATUS_INPUT,
    MAX_ACCOUNTS_INPUT: MAX_ACCOUNTS_INPUT,
    MAX_PREFS_INPUT: MAX_PREFS_INPUT,
    MAX_EXIT_NODE_LIST_INPUT: MAX_EXIT_NODE_LIST_INPUT,
    MAX_PEERS: MAX_PEERS,
    MAX_EXIT_NODES: MAX_EXIT_NODES,
    MAX_ACCOUNTS: MAX_ACCOUNTS,
    MAX_MULLVAD_NODES: MAX_MULLVAD_NODES,
    MAX_STRING_LENGTH: MAX_STRING_LENGTH,
    capString: capString,
    capStringArray: capStringArray,
    capTags: capTags,
    filterIPv4: filterIPv4,
    filterIPv6: filterIPv6,
    cleanDnsName: cleanDnsName,
    shortDnsName: shortDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    accountLabel: accountLabel,
    loginPlan: loginPlan,
    hasFileSharing: hasFileSharing,
    isTaildropTarget: isTaildropTarget,
    isMullvadPeer: isMullvadPeer,
    peerFromStatus: peerFromStatus,
    parseExitNodeList: parseExitNodeList,
    mullvadRegionOptions: mullvadRegionOptions,
    mullvadCountryOptions: mullvadCountryOptions,
    parseStatus: parseStatus,
    parseAccounts: parseAccounts,
    parsePrefs: parsePrefs,
    normalizeControlUrl: normalizeControlUrl,
    normalizeControlUrlInput: normalizeControlUrlInput,
    isValidControlUrl: isValidControlUrl,
    isValidDnsAddress: isValidDnsAddress,
    parseDnsMap: parseDnsMap,
    dnsForControlUrl: dnsForControlUrl,
    dnsMode: dnsMode
  }
}
