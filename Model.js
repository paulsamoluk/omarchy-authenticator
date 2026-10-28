.pragma library

// Helpers shared by the widget and the panel. Pure functions over the JSON the
// helper prints — no state, no side effects.

function parseList(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { backend: "", accounts: [], ok: false, error: "" }
  try {
    var data = JSON.parse(text)
    var accounts = []
    var list = data.accounts || []
    for (var i = 0; i < list.length; i++) {
      var a = list[i] || {}
      accounts.push({
        id: String(a.id || ""),
        label: String(a.label || a.id || "account"),
        issuer: String(a.issuer || ""),
        code: String(a.code || ""),
        digits: Number(a.digits) > 0 ? Number(a.digits) : 6,
        period: Number(a.period) > 0 ? Number(a.period) : 30,
        store: String(a.store || ""),
        expiresAt: Number(a.expires_at) || 0,
        error: String(a.error || "")
      })
    }
    return { backend: String(data.backend || ""), accounts: accounts, ok: true, error: "" }
  } catch (e) {
    return { backend: "", accounts: [], ok: false, error: "helper output was not JSON" }
  }
}

// 123456 -> "123 456"; 12345678 -> "1234 5678"
function spaced(code) {
  var text = String(code || "")
  if (text.length < 6) return text
  var half = Math.ceil(text.length / 2)
  return text.slice(0, half) + " " + text.slice(half)
}

function masked(code) {
  var text = String(code || "")
  if (text === "") return ""
  return text.replace(/[0-9]/g, "•")
}

function secondsLeft(account, nowSeconds) {
  if (!account || !account.expiresAt) return 0
  return Math.max(0, Math.round(account.expiresAt - nowSeconds))
}

function soonestExpiry(accounts) {
  var soonest = 0
  for (var i = 0; i < accounts.length; i++) {
    var at = accounts[i].expiresAt
    if (at > 0 && (soonest === 0 || at < soonest)) soonest = at
  }
  return soonest
}

function subtitle(account) {
  if (!account) return ""
  var issuer = String(account.issuer || "")
  var label = String(account.label || "")
  if (issuer !== "" && label.toLowerCase().indexOf(issuer.toLowerCase()) === 0) return ""
  return issuer
}

function metaLine(count, backend) {
  var who = count === 1 ? "1 account" : count + " accounts"
  var where = backend === "keyring" ? "login keyring" : backend === "file" ? "local file (0600)" : "no store yet"
  return who + " · " + where
}

function progressFraction(account, nowSeconds) {
  if (!account || account.period <= 0) return 0
  return Math.max(0, Math.min(1, secondsLeft(account, nowSeconds) / account.period))
}
