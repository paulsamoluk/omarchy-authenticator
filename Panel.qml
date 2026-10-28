import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Authenticator panel — the reveal. Codes, countdowns and copy-on-click;
// adding takes an otpauth:// URI or a bare base32 secret, and the widget hands
// it to bin/otp over stdin so the secret never lands in argv.
//
// State and every side effect belong to BarWidget.qml; this is a view that
// calls back through `hostWidget`. The countdown language is deliberate: one
// accent colour, used only for "this code is about to change" and "you just
// copied it", so the panel stays readable at a glance.
Panel {
  id: root
  moduleName: "psamoluk.totp"
  ipcTarget: "psamoluk.totp"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var host: hostWidget
  readonly property var barIdentity: hostWidget || root
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var accounts: host ? (host.accounts || []) : []
  readonly property int count: accounts.length
  readonly property bool masked: host ? host.maskCodes === true : false
  readonly property double nowSec: host ? (host.nowSec || 0) : 0

  property int cursorIndex: 0
  property string notice: ""
  property string pendingRemoveId: ""
  property string copiedId: ""
  property bool showAdd: false

  // Seconds until the soonest code rolls, for the hero ring and its meta line.
  readonly property int soonestLeft: {
    var best = -1
    for (var i = 0; i < accounts.length; i++) {
      var left = Model.secondsLeft(accounts[i], nowSec)
      if (left <= 0 && accounts[i].expiresAt <= 0) continue
      if (best < 0 || left < best) best = left
    }
    return best < 0 ? 0 : best
  }
  readonly property real soonestFraction: {
    for (var i = 0; i < accounts.length; i++) {
      var a = accounts[i]
      if (a.expiresAt > 0 && Model.secondsLeft(a, nowSec) === soonestLeft) return Model.progressFraction(a, nowSec)
    }
    return 0
  }
  readonly property bool soonestUrgent: count > 0 && soonestLeft <= 5

  function codeText(account) {
    if (!account) return ""
    if (account.code === "") return account.error !== "" ? "error" : "------"
    return Model.spaced(account.code)
  }

  function draft() { return String(uriField.text || "").trim() }

  function looksLikeUri(text) { return text.indexOf("otpauth://") === 0 }

  // Setup pages print the key as base32 next to the QR code; accept that too.
  function looksLikeSecret(text) { return /^[A-Za-z2-7][A-Za-z2-7\s=-]{15,}$/.test(text) }

  readonly property bool labelNeeded: draft() !== "" && !looksLikeUri(draft())

  function moveCursor(delta) {
    if (count === 0) return
    cursorIndex = Math.max(0, Math.min(count - 1, cursorIndex + delta))
    ensureVisible(cursorIndex)
  }

  function ensureVisible(index) {
    var rowHeight = Style.space(62) + Style.space(6)
    var top = index * rowHeight
    var bottom = top + rowHeight
    if (top < codeScroller.contentY) codeScroller.contentY = top
    else if (bottom > codeScroller.contentY + codeScroller.height)
      codeScroller.contentY = bottom - codeScroller.height
  }

  function activateCursor() { copyAt(cursorIndex) }

  function copyAt(index) {
    if (index < 0 || index >= count) return
    var account = accounts[index]
    if (!account || account.code === "") return
    pendingRemoveId = ""
    if (host && host.copyCode) host.copyCode(account)
    copiedId = account.id
    copyFlash.restart()
    notice = "Copied " + account.label + " — clipboard clears in 60 s"
  }

  function toggleMask() {
    if (host && host.setMaskCodes) host.setMaskCodes(!masked)
  }

  function askRemove(index) {
    if (index < 0 || index >= count) return
    var account = accounts[index]
    if (!account) return
    if (pendingRemoveId === account.id) {
      pendingRemoveId = ""
      notice = "Removed " + account.label
      if (host && host.removeAccount) host.removeAccount(account)
      return
    }
    pendingRemoveId = account.id
    notice = "Click × again to remove " + account.label
  }

  function submitAdd() {
    var text = draft()
    if (text === "") {
      notice = "Paste an otpauth:// URI, or the secret and a name."
      return
    }
    notice = "Adding…"
    if (looksLikeUri(text)) {
      if (host && host.addUri) host.addUri(text)
      uriField.text = ""
      return
    }
    if (!looksLikeSecret(text)) {
      notice = "That is neither an otpauth:// URI nor a base32 secret."
      return
    }
    var name = String(labelField.text || "").trim()
    if (name === "") {
      notice = "Name this account first."
      Qt.callLater(function() { labelField.forceActiveFocus() })
      return
    }
    notice = "Adding…"
    if (host && host.addSecret) host.addSecret(name, text)
    uriField.text = ""
    labelField.text = ""
  }

  function addLabel() {
    var who = count === 1 ? "1 account" : count + " accounts"
    var where = host && host.backend === "keyring" ? "login keyring" : "local file"
    if (count === 0) return who + " · " + where
    return who + " · next in " + soonestLeft + "s"
  }

  onOpenedChanged: {
    if (!opened) {
      pendingRemoveId = ""
      copiedId = ""
      return
    }
    cursorIndex = 0
    notice = ""
    if (host && host.refresh) host.refresh()
    reveal.restart()
  }

  Timer {
    id: copyFlash
    interval: 1400
    repeat: false
    onTriggered: root.copiedId = ""
  }

  Connections {
    target: root.host
    ignoreUnknownSignals: true
    function onAddErrorChanged() {
      if (!root.host) return
      if (root.host.addError && root.host.addError !== "") {
        root.notice = String(root.host.addError).replace(/^otp:\s*/, "")
        root.showAdd = true
      } else if (root.host.addSucceeded) {
        root.notice = "Account added."
        root.showAdd = false
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: uriField.activeFocus
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: root.activateCursor()
      onReturnRequested: root.activateCursor()
      onTextKey: function(text) {
        if (text === "a" || text === "A" || text === "/") {
          root.showAdd = true
          Qt.callLater(function() { uriField.forceActiveFocus() })
        } else if (text === "m" || text === "M") {
          root.toggleMask()
        }
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        // Opacity only: the panel card is positioned by the host, so animating
        // its geometry would fight the fitted height.
        opacity: 0
        NumberAnimation {
          id: reveal
          target: content
          property: "opacity"
          to: 1
          duration: 200
          easing.type: Easing.OutCubic
        }
        onHeightChanged: if (root.opened && content.opacity < 1) content.opacity = 1

        PanelHero {
          width: parent.width
          iconComponent: heroRing
          title: "Authenticator"
          meta: root.addLabel()
          detail: ""
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        // ------------------------------ toolbar ------------------------------
        Item {
          width: parent.width
          implicitHeight: Math.max(codesHeader.implicitHeight, tools.implicitHeight)

          PanelSectionHeader {
            id: codesHeader
            text: root.count === 0 ? "GET STARTED" : "CODES"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          Row {
            id: tools
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Rectangle {
              visible: root.count > 0
              anchors.verticalCenter: parent.verticalCenter
              width: countBadge.implicitWidth + Style.space(10)
              height: countBadge.implicitHeight + Style.space(2)
              radius: Style.cornerRadius
              color: Util.alpha(root.barForeground, 0.07)
              border.width: 1
              border.color: Util.alpha(root.barForeground, 0.10)

              Text {
                id: countBadge
                anchors.centerIn: parent
                text: String(root.count)
                color: Util.alpha(root.barForeground, 0.7)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            PanelActionButton {
              iconText: root.masked ? "\uF06E" : "\uF070"
              foreground: root.barForeground
              fontSize: Style.font.caption
              tooltipText: root.masked ? "Reveal codes" : "Hide codes"
              onClicked: root.toggleMask()
            }

            Button {
              text: root.showAdd ? "Cancel" : "Add account"
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              foreground: root.barForeground
              bordered: true
              onClicked: {
                root.showAdd = !root.showAdd
                if (root.showAdd) Qt.callLater(function() { uriField.forceActiveFocus() })
              }
            }
          }
        }

        // ------------------------------- add card ----------------------------
        Rectangle {
          id: addCard
          width: parent.width
          visible: root.showAdd || root.count === 0
          height: addColumn.implicitHeight + Style.space(18)
          radius: Style.cornerRadius
          color: Util.alpha(root.barForeground, 0.04)
          border.width: 1
          border.color: Util.alpha(root.barForeground, 0.12)
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          Column {
            id: addColumn
            anchors.fill: parent
            anchors.margins: Style.space(9)
            spacing: Style.space(6)

            Row {
              width: parent.width
              spacing: Style.space(8)
              visible: root.labelNeeded

              TextField {
                id: labelField
                width: parent.width
                height: Style.space(30)
                foreground: root.barForeground
                selectByMouse: true
                placeholderText: "Name this account (e.g. GitHub)"
                onAccepted: root.submitAdd()
                onTextEdited: if (root.notice !== "") root.notice = ""
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: uriField
                width: parent.width - addButton.width - parent.spacing
                height: Style.space(30)
                foreground: root.barForeground
                selectByMouse: true
                placeholderText: root.labelNeeded
                  ? "paste the base32 secret"
                  : "otpauth://totp/Issuer:you?secret=…  (or just the secret)"
                onAccepted: root.submitAdd()
                onTextEdited: if (root.notice !== "") root.notice = ""
                Keys.onEscapePressed: keyCatcher.forceActiveFocus()
              }

              Button {
                id: addButton
                text: "Add"
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                foreground: root.barForeground
                bordered: true
                onClicked: root.submitAdd()
              }
            }

            Text {
              width: parent.width
              visible: root.count === 0
              wrapMode: Text.WordWrap
              text: "Paste the otpauth:// URI from the service's QR code, or just the base32 secret and a name. The secret goes to your login keyring — never into this widget's files."
              color: Util.alpha(root.barForeground, 0.55)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // -------------------------------- codes ------------------------------
        Flickable {
          id: codeScroller
          width: parent.width
          height: Math.min(codesColumn.implicitHeight, Style.space(6 * 68))
          contentHeight: codesColumn.implicitHeight
          contentWidth: width
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          visible: root.count > 0

          Column {
          id: codesColumn
          width: codeScroller.width
          spacing: Style.space(6)

          Repeater {
            model: root.accounts

            delegate: Item {
              id: rowItem
              required property var modelData
              required property int index

              width: content.width
              height: Style.space(62)

              readonly property bool selected: index === root.cursorIndex
              readonly property bool copied: root.copiedId === modelData.id
              readonly property bool armed: root.pendingRemoveId === modelData.id
              readonly property int secsLeft: Model.secondsLeft(modelData, root.nowSec)
              readonly property real fraction: Model.progressFraction(modelData, root.nowSec)
              readonly property bool urgent: secsLeft <= 5
              readonly property color tint: copied || urgent ? Color.accent : root.barForeground

              // Codes roll every 30 s and the model is rebuilt with them, so a
              // short fade reads as "this is a new code" without any timer.
              opacity: 0
              Component.onCompleted: intro.start()
              NumberAnimation {
                id: intro
                target: rowItem
                property: "opacity"
                to: 1
                duration: 220
                easing.type: Easing.OutCubic
              }

              Rectangle {
                id: card
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Util.alpha(root.barForeground,
                                  mouse.containsMouse ? 0.10 : rowItem.selected ? 0.08 : 0.045)
                border.width: rowItem.selected || rowItem.copied ? 1 : 0
                border.color: rowItem.copied ? Color.accent : Util.alpha(Color.accent, 0.55)
                Behavior on color { ColorAnimation { duration: 130 } }

                Rectangle {
                  anchors.fill: parent
                  radius: parent.radius
                  opacity: rowItem.selected || rowItem.copied ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 160 } }
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Util.alpha(Color.accent, 0.13) }
                    GradientStop { position: 0.45; color: Util.alpha(Color.accent, 0.0) }
                  }
                }
              }

              // Countdown as a fuse along the card's bottom edge: one glance
              // reads every code's remaining life at the same place.
              Rectangle {
                anchors.left: card.left
                anchors.right: card.right
                anchors.bottom: card.bottom
                anchors.leftMargin: Style.space(18)
                anchors.rightMargin: Style.space(14)
                anchors.bottomMargin: Style.space(6)
                height: 2
                radius: 1
                color: Util.alpha(root.barForeground, 0.08)

                Rectangle {
                  width: parent.width * rowItem.fraction
                  height: parent.height
                  radius: parent.radius
                  color: rowItem.copied || rowItem.urgent ? Color.accent : Util.alpha(root.barForeground, 0.5)
                  Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.Linear } }
                  Behavior on color { ColorAnimation { duration: 200 } }
                }
              }

              // Accent edge: the one bit of colour that marks the live row.
              Rectangle {
                width: Math.max(2, Style.space(2))
                height: parent.height - Style.space(16)
                radius: width / 2
                anchors.left: parent.left
                anchors.leftMargin: Style.space(7)
                anchors.verticalCenter: parent.verticalCenter
                color: rowItem.copied ? Color.accent : Util.alpha(Color.accent, 0.75)
                opacity: (mouse.containsMouse || rowItem.selected || rowItem.copied) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
              }

              // Label block
              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(18)
                anchors.right: codeBlock.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: rowItem.modelData.label
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: Model.subtitle(rowItem.modelData) !== "" || rowItem.modelData.error !== ""
                  text: rowItem.modelData.error !== ""
                    ? rowItem.modelData.error.replace(/^otp:\s*/, "")
                    : Model.subtitle(rowItem.modelData)
                  color: Util.alpha(root.barForeground, 0.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              // Code + countdown
              Column {
                id: codeBlock
                anchors.right: removeButton.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Row {
                  anchors.right: parent.right
                  spacing: Style.space(6)

                  OpticalGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uF00C"
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    color: Color.accent
                    opacity: rowItem.copied ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                  }

                  Text {
                    id: codeLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.masked
                      ? Model.masked(rowItem.modelData.code)
                      : root.codeText(rowItem.modelData)
                    color: rowItem.copied ? Color.accent : root.barForeground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    font.letterSpacing: Style.space(1)
                    Behavior on color { ColorAnimation { duration: 150 } }
                  }
                }

                Text {
                  id: seconds
                  anchors.right: parent.right
                  text: rowItem.secsLeft + "s"
                  color: rowItem.urgent ? Color.accent : Util.alpha(root.barForeground, 0.38)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                  Behavior on color { ColorAnimation { duration: 150 } }
                }
              }

              PanelActionButton {
                id: removeButton
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                iconText: rowItem.armed ? "\uF00D" : "\uF00D"
                foreground: rowItem.armed ? Color.accent : root.barForeground
                fontSize: Style.font.caption
                opacity: rowItem.armed ? 1 : (mouse.containsMouse || rowItem.selected ? 0.7 : 0)
                tooltipText: rowItem.armed ? "Click again to confirm" : "Remove account"
                onClicked: root.askRemove(rowItem.index)
                Behavior on opacity { NumberAnimation { duration: 130 } }
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.rightMargin: removeButton.width + Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.cursorIndex = rowItem.index
                  root.copyAt(rowItem.index)
                }
              }
            }
          }
          }
        }

        // -------------------------------- notice -----------------------------
        Rectangle {
          width: parent.width
          visible: root.notice !== ""
          height: visible ? noticeText.implicitHeight + Style.space(10) : 0
          radius: Style.cornerRadius
          color: Util.alpha(root.barForeground, 0.05)

          Text {
            id: noticeText
            anchors.centerIn: parent
            width: parent.width - Style.space(16)
            horizontalAlignment: Text.AlignHCenter
            text: root.notice
            color: Util.alpha(root.barForeground, 0.78)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Click to copy  ·  ↑↓ move  ·  M hides  ·  Esc closes"
          color: Util.alpha(root.barForeground, 0.35)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // The hero ring: the soonest code's countdown wrapped around the key.
  Component {
    id: heroRing

    Item {
      implicitWidth: Style.space(42)
      implicitHeight: Style.space(42)

      Ring {
        anchors.fill: parent
        thickness: Math.max(2, Style.space(2))
        progress: root.soonestFraction
        color: root.soonestUrgent ? Color.accent : Util.alpha(root.barForeground, 0.8)
        trackColor: Util.alpha(root.barForeground, 0.12)
      }

      OpticalGlyph {
        anchors.centerIn: parent
        text: "\uF084"
        fontFamily: root.fontFamily
        fontSize: Math.round(Style.font.display * 0.8)
        color: root.barForeground
      }
    }
  }
}
