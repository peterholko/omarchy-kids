import QtQuick

Item {
  id: root
  property var problem: null
  property var board: null
  property var step: null
  readonly property int columns: problem ? problem.columns : 3
  readonly property real cellWidth: Math.min(72, (width - 116) / columns)
  readonly property real gridX: (width - cellWidth * columns) / 2 + 42
  readonly property int partialCount: problem ? problem.partials.length : 0
  readonly property int answerY: partialCount ? 150 + partialCount * 34 : 140
  readonly property string carryKey: problem && problem.operation === "subtract" ? "regroup"
    : step && step.multiplier >= 0 ? "carry" + step.multiplier : "sumCarry"
  readonly property var placeLabels: ["1", "10", "100", "1,000", "10,000", "100,000"]
  function value(row, column) { return board && board[row] && board[row][column] !== null ? String(board[row][column]) : "" }

  Repeater {
    model: root.columns
    delegate: Text {
      required property int index
      x: root.gridX + index * root.cellWidth; y: 0; width: root.cellWidth
      text: root.placeLabels[root.columns - index - 1]; horizontalAlignment: Text.AlignHCenter
      color: "#977B89"; font.pixelSize: 11
    }
  }
  Text {
    x: 0; y: 22; width: root.gridX - 14; horizontalAlignment: Text.AlignRight
    text: root.carryKey === "regroup" ? "regroup" : root.carryKey === "sumCarry" ? "sum carry" : "row carry"
    color: "#477B72"; font.pixelSize: 12
  }
  Repeater {
    model: root.columns
    delegate: Text {
      required property int index
      x: root.gridX + index * root.cellWidth; y: 20; width: root.cellWidth
      text: root.value(root.carryKey, root.columns - index - 1)
      horizontalAlignment: Text.AlignHCenter; color: "#477B72"; font.pixelSize: 19; font.bold: true
    }
  }
  Repeater {
    model: ["top", "bottom"]
    delegate: Item {
      id: operandRow
      required property string modelData
      required property int index
      x: root.gridX; y: 47 + index * 38; width: root.cellWidth * root.columns; height: 36
      Text { x: -28; y: 0; text: modelData === "bottom" && root.problem ? root.problem.symbol : ""; color: "#664C5B"; font.pixelSize: 28 }
      Repeater {
        model: root.columns
        delegate: Text {
          required property int index
          readonly property int column: root.columns - index - 1
          x: index * root.cellWidth; width: root.cellWidth
          text: root.value(operandRow.modelData, column); horizontalAlignment: Text.AlignHCenter
          color: operandRow.modelData === "bottom" && root.step && root.step.multiplier === column ? "#A34E73" : "#544553"
          font.pixelSize: 29; font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace"
          font.strikeout: operandRow.modelData === "top" && root.value("regroup", column) !== ""
        }
      }
    }
  }
  Rectangle { x: root.gridX - 32; y: 125; width: root.cellWidth * root.columns + 38; height: 2; color: "#B39AA5" }
  Repeater {
    model: root.partialCount
    delegate: Item {
      required property int index
      readonly property string rowKey: "partial" + index
      y: 134 + index * 34; width: root.width; height: 32
      Text { x: root.gridX - 28; y: 0; visible: index === root.partialCount - 1; text: "+"; color: "#967585"; font.pixelSize: 25 }
      Text {
        x: 0; width: root.gridX - 44; horizontalAlignment: Text.AlignRight
        text: "× " + (root.problem ? Math.floor(root.problem.b / Math.pow(10, index)) % 10 * Math.pow(10, index) : 0)
        color: "#967585"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter
      }
      Repeater {
        model: root.columns
        delegate: Rectangle {
          required property int index
          readonly property int column: root.columns - index - 1
          x: root.gridX + index * root.cellWidth; width: root.cellWidth - 2; height: 31; radius: 6
          color: root.step && root.step.row === rowKey && (root.step.column < 0 || root.step.column === column) ? "#F6E6ED" : "transparent"
          Text { anchors.centerIn: parent; text: root.value(rowKey, column) || "·"; color: root.value(rowKey, column) ? "#735168" : "#DACDD3"; font.pixelSize: 25; font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace" }
        }
      }
    }
  }
  Rectangle { visible: root.partialCount > 0; x: root.gridX - 32; y: root.answerY - 9; width: root.cellWidth * root.columns + 38; height: 2; color: "#B39AA5" }
  Text { x: 0; y: root.answerY + 10; width: root.gridX - 15; horizontalAlignment: Text.AlignRight; text: "answer"; color: "#477B72"; font.pixelSize: 12 }
  Repeater {
    model: root.columns
    delegate: Rectangle {
      required property int index
      readonly property int column: root.columns - index - 1
      x: root.gridX + index * root.cellWidth; y: root.answerY; width: root.cellWidth - 2; height: 38; radius: 7
      color: root.step && root.step.row === "result" && (root.step.column < 0 || root.step.column === column) ? "#E4EEE4" : "transparent"
      Text { anchors.centerIn: parent; text: root.value("result", column) || "·"; color: root.value("result", column) ? "#477B72" : "#DACDD3"; font.pixelSize: 28; font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace" }
    }
  }
}
