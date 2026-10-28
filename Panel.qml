import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Authenticator panel — the reveal. Codes, countdowns and copy-on-click;
// adding takes an otpauth:// URI pasted from the service's setup page, and the
// widget hands it to bin/otp over stdin so the secret never lands in argv.
//
// State and every side effect belong to BarWidget.qml; this is a view that
// calls back through `hostWidget`.
Panel {
  id: root
  moduleName: "psamoluk.totp"
  ipcTarget: "psamoluk.totp"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var host: hostWidget
  readonly property var barIdentity: hostWidget || root
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string home: Quickshell.env("HOME") || ""

  readonly property var accounts: host ? (host.accounts || []) : []
  readonly property int count: accounts.length
  readonly property bool masked: host ? host.maskCodes === true : false
  readonly property double nowSec: host ? (host.nowSec || 0) : 0

  property int cursorIndex: 0
  property string notice: ""
  property string pendingRemoveId: ""
  property bool showAdd: false

  function codeText(account) {
    if (!account) return ""
    if (account.code === "") return account.error !== "" ? "error" : "------"
    return Model.spaced(account.code)
  }

  function moveCursor(delta) {
    if (count === 0) return
    var next = Math.max(0, Math.min(count - 1, cursorIndex + delta))
    cursorIndex = next
  }

  function activateCursor() { copyAt(cursorIndex) }

  function copyAt(index) {
    if (index < 0 || index >= count) return
    var account = accounts[index]
    if (!account || account.code === "") return
    pendingRemoveId = ""
    if (host && host.copyCode) host.copyCode(account)
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
    var uri = String(uriField.text || "").trim()
    if (uri === "") {
      notice = "Paste an otpauth:// URI first."
      return
    }
    if (uri.indexOf("otpauth://") !== 0) {
      notice = "That does not look like an otpauth:// URI."
      return
    }
    notice = ""
    if (host && host.addUri) host.addUri(uri)
    uriField.text = ""
  }

  onOpenedChanged: {
    if (!opened) {
      pendingRemoveId = ""
      return
    }
    cursorIndex = 0
    notice = ""
    if (host && host.refresh) host.refresh()
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

        PanelHero {
          width: parent.width
          iconComponent: heroGlyph
          title: "Authenticator"
          meta: Model.metaLine(root.count, host ? host.backend : "")
          detail: ""
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(codesHeader.implicitHeight, maskButton.implicitHeight)

          PanelSectionHeader {
            id: codesHeader
            text: "CODES"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          Row {
            id: maskButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

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

        // ------------------------------ add row ------------------------------
        Row {
          width: parent.width
          visible: root.showAdd || root.count === 0
          spacing: Style.space(8)

          TextField {
            id: uriField
            width: parent.width - addButton.width - parent.spacing
            height: Style.space(30)
            foreground: root.barForeground
            selectByMouse: true
            placeholderText: "otpauth://totp/Issuer:you?secret=…  (paste from the service)"
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
          text: "No accounts yet. Paste the otpauth:// URI your service shows next to its QR code — the secret is stored in your login keyring, never in the widget's files."
          color: Util.alpha(root.barForeground, 0.62)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ------------------------------- codes -------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.count > 0

          Repeater {
            model: root.accounts

            delegate: Item {
              id: rowItem
              required property var modelData
              required property int index

              width: content.width
              height: rowBody.implicitHeight + Style.space(14)

              readonly property bool selected: index === root.cursorIndex
              readonly property int secsLeft: Model.secondsLeft(modelData, root.nowSec)
              readonly property real fraction: Model.progressFraction(modelData, root.nowSec)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Util.alpha(root.barForeground, rowItem.selected ? 0.09 : 0.04)
                border.width: rowItem.selected ? Math.max(1, Style.space(1)) : 0
                border.color: Color.accent
              }

              Row {
                id: rowBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(10)

                Column {
                  width: parent.width - codeBlock.width - removeButton.width - parent.spacing * 2
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
                    color: Util.alpha(root.barForeground, 0.55)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Column {
                  id: codeBlock
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)

                  Text {
                    anchors.right: parent.right
                    text: root.masked ? Model.masked(rowItem.modelData.code) : root.codeText(rowItem.modelData)
                    color: root.barForeground
                    font.family: Style.font.monospace ? Style.font.monospace : root.fontFamily
                    font.pixelSize: Style.font.title
                    font.letterSpacing: Style.space(1)
                  }

                  // Countdown: the bar empties as the code expires.
                  Rectangle {
                    anchors.right: parent.right
                    width: Style.space(120)
                    height: Math.max(3, Style.space(3))
                    radius: height / 2
                    color: Util.alpha(root.barForeground, 0.18)

                    Rectangle {
                      width: parent.width * rowItem.fraction
                      height: parent.height
                      radius: parent.radius
                      color: rowItem.secsLeft <= 5 ? Color.accent : Util.alpha(root.barForeground, 0.55)
                    }
                  }
                }

                PanelActionButton {
                  id: removeButton
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "\uF00D"
                  foreground: root.barForeground
                  fontSize: Style.font.caption
                  tooltipText: root.pendingRemoveId === rowItem.modelData.id ? "Click again to confirm" : "Remove account"
                  onClicked: root.askRemove(rowItem.index)
                }
              }

              MouseArea {
                anchors.fill: parent
                anchors.rightMargin: removeButton.width
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

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.notice !== ""
          text: root.notice
          color: Util.alpha(root.barForeground, 0.8)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Click to copy  ·  M hides  ·  Esc closes"
          color: Util.alpha(root.barForeground, 0.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Component {
    id: heroGlyph

    Item {
      implicitWidth: heroGlyphMetrics.advanceWidth + Style.space(12)
      implicitHeight: Math.round(Style.font.display * 1.35)

      TextMetrics {
        id: heroGlyphMetrics
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.display)
        text: "\uF084"
      }

      OpticalGlyph {
        anchors.centerIn: parent
        text: "\uF084"
        fontFamily: root.fontFamily
        fontSize: Style.font.display
        color: root.barForeground
      }
    }
  }
}
