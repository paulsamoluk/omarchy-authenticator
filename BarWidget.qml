import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Authenticator — TOTP codes generated locally by bin/otp (RFC 6238), listed in
// a popout so a 2FA code is two clicks away instead of a phone in another room.
//
// Secrets live in the login keyring through secret-tool (service
// "psamoluk.totp"); only account metadata is on disk, in a 0600 index. The
// widget never shows a code in the bar — the panel is the reveal — and nothing
// here touches the network.
//
// The helper is spawned once per code period (plus once when the panel opens),
// not per tick: the countdown is arithmetic on `expires_at`, so a 30 s code
// costs one short-lived python process every 30 s.
BarWidget {
  id: root
  moduleName: "psamoluk.totp"

  readonly property string icon: "\uF084" // nf-fa-key
  readonly property string helperPath: decodeURIComponent(String(Qt.resolvedUrl("bin/otp")).replace("file://", ""))

  // Shared with the panel.
  property var accounts: []
  property string backend: ""
  property string error: ""
  property bool busy: false
  property bool pendingRefresh: false
  // Session lock. Held for the lifetime of the shell process: a fresh session
  // (or a shell restart) asks again.
  property bool lockKnown: false
  property bool lockConfigured: false
  property bool unlocked: false
  property string lockError: ""
  readonly property int lockMinutes: (settings && Number(settings.lockMinutes) > 0) ? Number(settings.lockMinutes) : 15
  readonly property bool needsUnlock: lockConfigured && !unlocked
  property double nowMs: Date.now()
  readonly property double nowSec: nowMs / 1000

  readonly property int count: accounts.length
  readonly property int secondsLeft: Model.secondsLeft(soonest(), nowSec)
  readonly property bool showCountdown: settings && settings.showCountdown === true
  readonly property bool maskCodes: settings && settings.maskCodes === true

  function soonest() {
    var pick = null
    for (var i = 0; i < accounts.length; i++) {
      if (accounts[i].expiresAt <= 0) continue
      if (pick === null || accounts[i].expiresAt < pick.expiresAt) pick = accounts[i]
    }
    return pick
  }

  // ---------------------------------------------------------------------------
  // Shell.json entry
  // ---------------------------------------------------------------------------
  function persist(fields) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = { id: moduleName }
    if (settings) for (var key in settings) if (key !== "id") entry[key] = settings[key]
    for (var field in fields) entry[field] = fields[field]
    bar.shell.updateEntryInline(moduleName, entry)
  }

  function setMaskCodes(value) {
    persist({ maskCodes: value === true })
  }

  function setShowCountdown(value) {
    persist({ showCountdown: value === true })
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------
  function refresh() {
    if (!lockKnown) return
    if (needsUnlock) {
      accounts = []
      return
    }
    if (busy) {
      pendingRefresh = true
      return
    }
    busy = true
    listProc.command = [helperPath, "list", "--json"]
    listProc.running = true
  }

  function applyList(raw) {
    var parsed = Model.parseList(raw)
    accounts = parsed.accounts
    backend = parsed.backend
    error = parsed.ok ? "" : parsed.error
    nowMs = Date.now()
  }

  function copyCode(account) {
    if (!account || account.code === "") return
    copyProc.command = [helperPath, "copy", "--id", account.id]
    copyProc.running = true
  }

  function removeAccount(account) {
    if (!account) return
    removeProc.command = [helperPath, "remove", "--id", account.id]
    removeProc.running = true
  }

  function addUri(uri) {
    var text = String(uri || "").trim()
    if (text === "") return false
    addProc.command = [helperPath, "add-uri"]
    addProc.inputText = text
    addProc.running = true
    return true
  }

  // A bare base32 secret (what Google/Microsoft setup pages print next to the
  // QR code) with a label the user types. The secret still travels on stdin.
  function addSecret(label, secret) {
    var name = String(label || "").trim()
    var key = String(secret || "").replace(/\s+/g, "")
    if (name === "" || key === "") return false
    addProc.command = [helperPath, "add", "--label", name]
    addProc.inputText = key
    addProc.running = true
    return true
  }

  function touch() {
    if (unlocked) idleLock.restart()
  }

  function relock() {
    unlocked = false
    accounts = []
    lockError = ""
  }

  function refreshLockState() {
    lockStatusProc.running = true
  }

  function unlock(password) {
    var pw = String(password || "")
    if (pw === "") {
      lockError = "Enter the master password"
      return
    }
    lockError = ""
    verifyProc.inputText = pw
    verifyProc.running = true
  }

  function setPassword(password) {
    var pw = String(password || "")
    if (pw.length < 6) {
      lockError = "Use at least 6 characters"
      return
    }
    lockError = ""
    setLockProc.inputText = pw
    setLockProc.running = true
  }

  function clearPassword(password) {
    clearLockProc.inputText = String(password || "")
    clearLockProc.running = true
  }

  Process {
    id: lockStatusProc
    command: [helperPath, "lock", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.lockConfigured = JSON.parse(String(text || "{}")).configured === true
        } catch (e) {
          root.lockConfigured = false
        }
        if (!root.lockConfigured) root.unlocked = true
        root.lockKnown = true
        root.refresh()
      }
    }
  }

  Process {
    id: verifyProc
    command: [helperPath, "lock", "verify"]
    property string inputText: ""
    stdinEnabled: true
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { write(inputText + "\n"); inputText = "" }
    onExited: {
      if (exitCode === 0) {
        root.unlocked = true
        root.lockError = ""
        root.touch()
        root.refresh()
      } else {
        root.lockError = "Wrong password"
      }
    }
  }

  Process {
    id: setLockProc
    command: [helperPath, "lock", "set"]
    property string inputText: ""
    stdinEnabled: true
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { write(inputText + "\n"); inputText = "" }
    onExited: {
      if (exitCode === 0) {
        root.lockConfigured = true
        root.unlocked = true
        root.lockError = ""
        root.touch()
      } else {
        root.lockError = "Could not set the password"
      }
    }
  }

  Process {
    id: clearLockProc
    command: [helperPath, "lock", "clear"]
    property string inputText: ""
    stdinEnabled: true
    stderr: StdioCollector { waitForEnd: true }
    onStarted: { write(inputText + "\n"); inputText = "" }
    onExited: {
      if (exitCode === 0) {
        root.lockConfigured = false
        root.unlocked = true
        root.lockError = ""
      } else {
        root.lockError = "Wrong password"
      }
    }
  }

  // Idle re-lock: closing the panel keeps the session unlocked, but walking
  // away from an unlocked desktop for lockMinutes does not.
  Timer {
    id: idleLock
    interval: root.lockMinutes * 60 * 1000
    repeat: false
    onTriggered: root.relock()
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyList(String(text || ""))
    }
    onExited: {
      root.busy = false
      if (root.pendingRefresh) {
        root.pendingRefresh = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: copyProc
    onExited: root.refresh()
  }

  Process {
    id: removeProc
    stderr: StdioCollector { waitForEnd: true }
    onExited: root.refresh()
  }

  // The secret goes over stdin, never argv: an otpauth:// URI carries the key.
  Process {
    id: addProc
    property string inputText: ""
    stdinEnabled: true
    stderr: StdioCollector {
      waitForEnd: true
      property string message: ""
      onStreamFinished: message = String(text || "").trim()
    }
    onStarted: {
      write(inputText + "\n")
      inputText = ""
    }
    onExited: {
      root.addError = addProc.stderr.message
      root.addSucceeded = addProc.exitCode === 0
      root.refresh()
    }
  }

  property string addError: ""
  property bool addSucceeded: false

  // Five ticks a second is arithmetic only (the ring reads the clock); the
  // helper itself runs once per code period, when a countdown hits zero.
  Timer {
    interval: 200
    repeat: true
    running: root.count > 0
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.secondsLeft <= 0) root.refresh()
    }
  }

  // The keyring can be unlocked after login; pick keys up once it is.
  Timer {
    interval: 60000
    repeat: true
    running: root.count === 0
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    refreshLockState()
    refresh()
  }

  onSettingsChanged: {
    injectPanel()
    touch()
    idleLock.interval = lockMinutes * 60 * 1000
  }

  // ---------------------------------------------------------------------------
  // Panel wiring
  // ---------------------------------------------------------------------------
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  onBarChanged: injectPanel()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Row {
    id: row
    spacing: Style.space(4)

    BarIconButton {
      id: button
      bar: root.bar
      text: root.icon
      slotSize: Style.bar.statusSlot
      tooltipText: {
        if (root.error !== "") return "Authenticator — " + root.error
        if (root.count === 0) return "Authenticator — no accounts yet"
        return Model.metaLine(root.count, root.backend) + " · " + root.secondsLeft + "s"
      }
      onPressed: function(b) { root.togglePanel() }
    }

    Text {
      visible: root.showCountdown && root.count > 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(root.secondsLeft)
      color: root.bar ? root.bar.barForeground : Color.foreground
      opacity: root.secondsLeft <= 5 ? 1.0 : 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
