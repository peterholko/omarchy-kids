import QtQuick

Item {
  id: root
  property var problem: null
  property var board: null
  property var step: null
  function checked(row) { return board && board[row] && board[row][0] !== null ? String(board[row][0]) : "?" }
  Column {
    x: 32; y: 12; width: parent.width - 64; spacing: 14
    Text { text: "SHARE EQUALLY, THEN CHECK"; color: "#977B89"; font.pixelSize: 12; font.letterSpacing: 1.4 }
    Repeater {
      model: ["result", "product", "remainder"]
      delegate: Rectangle {
        required property string modelData
        width: parent.width; height: 64; radius: 12
        color: root.step && root.step.row === modelData ? "#E4EEE4" : "#FAF0F2"
        Text {
          x: 18; y: 9; color: "#977B89"; font.pixelSize: 11
          text: modelData === "result" ? "EQUAL GROUPS" : modelData === "product" ? "MULTIPLY TO CHECK" : "SUBTRACT: NOTHING LEFT OVER"
        }
        Text {
          x: 18; y: 27; color: "#594355"; font.pixelSize: 25
          text: !root.problem ? "" : modelData === "result" ? root.problem.a + " ÷ " + root.problem.b + " = " + root.checked("result")
            : modelData === "product" ? root.checked("result") + " × " + root.problem.b + " = " + root.checked("product")
            : root.problem.a + " − " + root.checked("product") + " = " + root.checked("remainder")
        }
      }
    }
  }
}
