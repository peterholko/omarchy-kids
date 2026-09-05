import QtQuick
import QtQuick.Window
import Quickshell

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  readonly property var schoolService: shell && typeof shell.serviceFor === "function"
    ? shell.serviceFor("omarchy.school-mode") : null
  readonly property bool schoolAllowed: !schoolService || !schoolService.schoolMode
    || schoolService.isAllowed("omarchy-number-grove.desktop")

  function open(payloadJson) {
    rewards.refresh()
    opened = true
    game.reset()
    Qt.callLater(function() { game.forceActiveFocus() })
  }
  function close() {
    game.reset()
    opened = false
  }
  RewardBridge {
    id: rewards
    omarchyPath: root.omarchyPath
    onReply: function(token, result) { game.acceptReward(token, result) }
  }
  FloatingWindow {
    id: win
    // A shell-owned application must also obey School Mode's app allowlist.
    visible: root.opened && root.schoolAllowed
    title: "Number Grove"
    color: "#F4F1E6"
    implicitWidth: 1040
    implicitHeight: 760
    minimumSize: Qt.size(780, 570)
    onClosed: root.close()
    GameView {
      id: game
      anchors.fill: parent
      windowActive: Window.active && root.opened
      rewardAvailable: rewards.available
      rewardNote: rewards.note
      rewardGrade: rewards.grade
      rewardQuestions: rewards.questions
      rewardMinutes: rewards.minutes
      onRewardRequest: function(token, kind, questionId, value) { rewards.request(token, kind, questionId, value) }
      onCancelRewards: rewards.cancel()
      onQuitRequested: root.close()
    }
  }
}
