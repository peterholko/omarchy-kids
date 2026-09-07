import QtQuick
import QtQuick.Controls.Basic
import "WorkSteps.js" as Steps
import "WorkSession.js" as Session

FocusScope {
  id: root
  property bool windowActive: true
  property string operation: "add"
  property int digitCount: 2
  property bool reducedMotion: false
  property var session: null
  property string answerInput: ""
  property bool showHint: false
  property int celebration: 0
  readonly property var problem: session ? Session.current(session) : null
  readonly property var step: session ? Session.activeStep(session) : null
  readonly property bool working: session !== null && session.phase === "work"
  readonly property bool roomComplete: session !== null && session.phase === "complete"
  readonly property bool paused: session !== null && session.paused
  readonly property var petNames: ["Peaches", "Biscuit", "Bluebell"]
  readonly property var operationNames: ({add: "Addition", subtract: "Subtraction", multiply: "Multiplication", mixed: "Mixed"})
  signal quitRequested()
  focus: true

  function reset() { session = null; answerInput = ""; showHint = false }
  function start() {
    var problems = []
    var kinds = operation === "mixed" ? ["add", "subtract", "multiply"] : [operation, operation, operation]
    for (var i = 0; i < kinds.length; i++) {
      var candidate = Steps.generate(kinds[i], digitCount)
      for (var attempt = 0; attempt < 30 && problems.some(function(p) { return p.a === candidate.a && p.b === candidate.b && p.operation === candidate.operation }); attempt++)
        candidate = Steps.generate(kinds[i], digitCount)
      problems.push(candidate)
    }
    session = Session.create(problems); answerInput = ""; showHint = false
    forceActiveFocus()
  }
  function check() {
    if (!working || paused) return
    var next = Session.submit(session, answerInput)
    if (next.stepIndex > session.stepIndex) { answerInput = ""; showHint = false; celebration++ }
    session = next
    forceActiveFocus()
  }
  function nextRoom() { session = Session.advance(session); answerInput = ""; showHint = false; forceActiveFocus() }
  function setPaused(value) { if (session) session = Session.pause(session, value); if (!value) forceActiveFocus() }
  onWindowActiveChanged: if (!windowActive && session && session.phase !== "results") setPaused(true)
  Keys.onPressed: function(event) {
    if (event.isAutoRepeat) { event.accepted = true; return }
    if (event.key === Qt.Key_Escape && session && session.phase !== "results") { setPaused(!paused); event.accepted = true; return }
    if (!working || paused) return
    if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && /^[0-9]$/.test(event.text)) {
      if (answerInput.length < 7) answerInput += event.text
      event.accepted = true
    } else if (event.key === Qt.Key_Backspace) { answerInput = answerInput.slice(0, -1); event.accepted = true }
    else if (event.key === Qt.Key_Delete) { answerInput = ""; event.accepted = true }
    else if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) { check(); event.accepted = true }
    else if (event.key === Qt.Key_H) { showHint = !showHint; event.accepted = true }
  }

  Rectangle { anchors.fill: parent; color: "#FAF5F2" }
  Item {
    id: page
    width: 1120; height: 800
    scale: Math.min(root.width / width, root.height / height)
    transformOrigin: Item.TopLeft
    x: (root.width - width * scale) / 2; y: (root.height - height * scale) / 2
    Text { x: 37; y: 25; text: "♥"; color: "#AD6581"; font.pixelSize: 38 }
    Text { x: 87; y: 26; text: "Pawberry Pet Hotel"; color: "#554252"; font.pixelSize: 25; font.bold: true }
    Text { x: 89; y: 58; text: "A LITTLE CARE. A LITTLE MATH. A LOT OF PAWS."; color: "#927888"; font.pixelSize: 10; font.letterSpacing: 1.4 }
    HotelButton { x: 790; y: 28; width: 158; height: 40; text: root.reducedMotion ? "Motion: off" : "Motion: on"; onClicked: root.reducedMotion = !root.reducedMotion }
    HotelButton { objectName: "pauseButton"; x: 958; y: 28; width: 80; height: 40; visible: root.session !== null && root.session.phase !== "results"; text: "Pause"; onClicked: root.setPaused(true) }
    HotelButton { x: 1048; y: 28; width: 38; height: 40; text: "×"; onClicked: root.quitRequested() }
    Rectangle { x: 36; y: 91; width: 1048; height: 1; color: "#E5DADF" }

    Item {
      anchors.fill: parent; visible: root.session === null
      Text { x: 40; y: 140; text: "Tiny paws.\nBig brainwaves."; color: "#594355"; font.pixelSize: 48; font.bold: true; lineHeight: 1.08 }
      Text { x: 43; y: 268; width: 500; text: "Welcome three little guests. Show your math work to make their rooms cozy, one checked step at a time."; color: "#806C7C"; font.pixelSize: 18; wrapMode: Text.WordWrap; lineHeight: 1.3 }
      Text { x: 43; y: 372; text: "1   PICK YOUR PRACTICE"; color: "#977288"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.6 }
      Row {
        x: 40; y: 401; spacing: 8
        Repeater {
          model: ["add", "subtract", "multiply", "mixed"]
          delegate: HotelButton {
            required property string modelData
            objectName: "operation-" + modelData
            width: 126; height: 46; text: root.operationNames[modelData]; selected: root.operation === modelData
            font.pixelSize: 14; onClicked: root.operation = modelData
          }
        }
      }
      Text { x: 43; y: 486; text: "2   CHOOSE YOUR NUMBERS"; color: "#977288"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.6 }
      Row {
        x: 40; y: 515; spacing: 10
        Repeater {
          model: [2, 3]
          delegate: HotelButton {
            required property int modelData
            objectName: "digits-" + modelData
            width: 260; height: 48
            text: modelData === 2 ? "Two digits   ·   " + (root.operation === "subtract" ? "68 − 24" : root.operation === "multiply" ? "24 × 38" : "24 + 38")
              : "Three digits   ·   " + (root.operation === "subtract" ? "247 − 185" : root.operation === "multiply" ? "247 × 185" : "247 + 185")
            selected: root.digitCount === modelData; onClicked: root.digitCount = modelData
          }
        }
      }
      HotelButton { objectName: "startButton"; x: 40; y: 616; width: 530; height: 56; primary: true; text: "Open the pet hotel  →"; font.pixelSize: 17; onClicked: root.start() }
      Text { x: 43; y: 691; width: 520; text: "No countdown. No lost hearts.\nWe check your working before the final answer."; color: "#94798A"; font.pixelSize: 14; lineHeight: 1.4 }
      Rectangle {
        x: 611; y: 143; width: 470; height: 582; radius: 25; color: "#F1E4E9"
        Text { x: 25; y: 27; text: "YOUR VERY IMPORTANT GUESTS"; color: "#916D83"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.4 }
        Image { objectName: "menuPets"; x: 14; y: 89; width: 442; height: 337; source: "assets/pets.png"; fillMode: Image.PreserveAspectFit; mipmap: true }
        Row {
          x: 21; y: 437; spacing: 9
          Repeater {
            model: root.petNames
            delegate: Rectangle {
              required property string modelData
              width: 136; height: 51; radius: 15; color: "#FFF8F4"
              Text { anchors.centerIn: parent; text: modelData; color: "#715169"; font.pixelSize: 16; font.bold: true }
            }
          }
        }
        Text { x: 32; y: 520; width: 406; text: "Cozy beds. Little treats.\nThree happy check-ins."; horizontalAlignment: Text.AlignHCenter; color: "#8D7083"; font.pixelSize: 16; lineHeight: 1.3 }
      }
    }

    Item {
      anchors.fill: parent; visible: root.working || root.roomComplete; enabled: !root.paused
      Rectangle {
        x: 36; y: 119; width: 656; height: 642; radius: 23; color: "#FFFDF9"; border.color: "#E9DDE0"
        Text { x: 26; y: 20; text: root.problem ? "GUEST " + (root.session.problemIndex + 1) + " / 3  ·  " + root.operationNames[root.problem.operation].toUpperCase() : ""; color: "#967487"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
        Text { x: 26; y: 46; text: root.problem ? root.problem.a + " " + root.problem.symbol + " " + root.problem.b : ""; color: "#594355"; font.pixelSize: 32; font.bold: true }
        Text { x: 336; y: 54; width: 292; text: "Your checked column work"; horizontalAlignment: Text.AlignRight; color: "#9B8691"; font.pixelSize: 13 }
        WorkBoard { objectName: "workBoard"; x: 22; y: 99; width: 605; height: 294; problem: root.problem; board: root.session ? root.session.board : null; step: root.step }
        Rectangle {
          x: 16; y: 413; width: 624; height: 212; radius: 17; color: root.roomComplete ? "#EDF3E8" : "#FAF0F2"
          Text { x: 18; y: 13; text: root.roomComplete ? "ONE COZY ROOM, ALL WORK CHECKED" : root.step ? "STEP " + (root.session.stepIndex + 1) + " / " + root.problem.steps.length : ""; color: "#967487"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1 }
          Text { objectName: "stepTitle"; x: 18; y: 35; width: 588; text: root.step ? root.step.title : "A lovely stay for " + (root.session ? root.petNames[root.session.problemIndex] : "") + "."; color: "#644858"; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
          Text { objectName: "stepExpression"; x: 18; y: 66; width: 588; text: root.step ? root.step.expression : "You can review every checked step in your work log."; color: "#735668"; font.pixelSize: 19; elide: Text.ElideRight }
          Rectangle {
            objectName: "answerEntry"; x: 18; y: 103; width: 175; height: 49; radius: 11; visible: root.working
            color: "#FFFDFC"; border.width: 2; border.color: root.session && root.session.error ? "#BA6266" : "#A77B8E"
            Text { anchors.centerIn: parent; text: root.answerInput || "?"; color: root.answerInput ? "#594355" : "#BEA2B0"; font.pixelSize: 29; font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace" }
            MouseArea { anchors.fill: parent; onClicked: root.forceActiveFocus() }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Answer for this step"
          }
          HotelButton { objectName: "checkButton"; x: 204; y: 103; width: 215; height: 49; visible: root.working; primary: true; text: root.step && root.step.kind === "final" ? "Finish the room  ♥" : "Check step  ↵"; onClicked: root.check() }
          HotelButton { objectName: "hintButton"; x: 430; y: 103; width: 175; height: 49; visible: root.working; text: root.showHint ? "Hide hint" : "A little hint"; onClicked: { root.showHint = !root.showHint; root.forceActiveFocus() } }
          HotelButton { objectName: "nextButton"; x: 18; y: 104; width: 586; height: 49; visible: root.roomComplete; primary: true; text: root.session && root.session.rooms === 3 ? "See our happy guests  →" : "Welcome the next guest  →"; onClicked: root.nextRoom() }
          Text {
            objectName: "stepFeedback"; x: 20; y: 163; width: 582; height: 45
            text: root.showHint && root.step ? root.step.hint : root.session && root.session.note ? root.session.note : "Type a number, then press Enter. H opens a hint."
            color: root.session && root.session.error && !root.showHint ? "#A35462" : "#8D7281"
            font.pixelSize: 13; wrapMode: Text.WordWrap
          }
        }
      }
      PetRoom {
        objectName: "guestRoom"; x: 713; y: 119; width: 371; height: 337
        petIndex: root.session ? root.session.problemIndex : 0
        progress: root.problem ? root.session.stepIndex / root.problem.steps.length : 0
        celebration: root.celebration; reducedMotion: root.reducedMotion
      }
      Rectangle { x: 728; y: 472; width: 340; height: 7; radius: 4; color: "#E8DDE1"; Rectangle { width: root.problem ? parent.width * root.session.stepIndex / root.problem.steps.length : 0; height: parent.height; radius: 4; color: "#AD788E" } }
      Text { x: 728; y: 490; text: root.session ? root.session.ledger.length + (root.session.ledger.length === 1 ? " step checked for " : " steps checked for ") + root.petNames[root.session.problemIndex] : ""; color: "#8E7484"; font.pixelSize: 12 }
      Rectangle {
        x: 713; y: 522; width: 371; height: 239; radius: 19; color: "#F2E9ED"
        Text { x: 18; y: 16; text: "YOUR WORK LOG"; color: "#907386"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
        Text { x: 18; y: 55; width: 325; visible: root.session !== null && root.session.ledger.length === 0; text: "Every checked step appears here.\nYour work is the story."; color: "#9D8292"; font.pixelSize: 14; lineHeight: 1.4 }
        ListView {
          id: workLog
          objectName: "workLog"; x: 18; y: 45; width: 335; height: 177; clip: true; spacing: 11
          model: root.session ? root.session.ledger : []
          onCountChanged: Qt.callLater(function() { workLog.positionViewAtEnd() })
          delegate: Column {
            required property var modelData
            width: workLog.width; spacing: 3
            Text { text: modelData.title; width: parent.width; color: "#8D7182"; font.pixelSize: 11; wrapMode: Text.WordWrap }
            Text { text: modelData.expression + " = " + modelData.value; width: parent.width; color: "#624C5D"; font.pixelSize: 14; wrapMode: Text.WordWrap }
          }
          ScrollBar.vertical: ScrollBar {}
        }
      }
    }

    Item {
      anchors.fill: parent; visible: root.session !== null && root.session.phase === "results"
      Text { x: 40; y: 135; width: 1040; text: "Three guests. Three cozy stays."; color: "#624658"; font.pixelSize: 37; font.bold: true; horizontalAlignment: Text.AlignHCenter }
      Text { x: 40; y: 194; width: 1040; text: "You showed every step. That’s thoughtful maths."; color: "#9A7B8E"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter }
      Row {
        x: 55; y: 247; spacing: 22
        Repeater { model: 3; delegate: PetRoom { required property int index; width: 322; height: 320; petIndex: index; progress: 1; reducedMotion: root.reducedMotion } }
      }
      Text { x: 80; y: 603; width: 960; text: root.session ? root.session.checked + " steps checked  ·  " + root.session.mistakes + (root.session.mistakes === 1 ? " retry" : " retries") + "  ·  all three rooms ready" : ""; color: "#806379"; font.pixelSize: 19; horizontalAlignment: Text.AlignHCenter }
      HotelButton { objectName: "againButton"; x: 356; y: 665; width: 410; height: 54; primary: true; text: "Another lovely day at the hotel  →"; onClicked: root.reset() }
    }

    Rectangle {
      anchors.fill: parent; visible: root.paused; color: "#99594A56"; z: 20
      MouseArea { anchors.fill: parent }
      Rectangle {
        anchors.centerIn: parent; width: 500; height: 280; radius: 25; color: "#FFF8F4"
        Text { x: 28; y: 33; width: 444; text: "A little paws."; color: "#67485D"; font.pixelSize: 32; font.bold: true; horizontalAlignment: Text.AlignHCenter }
        Text { x: 30; y: 94; width: 440; text: "Your work and your guests are safe right here."; color: "#907486"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
        HotelButton { objectName: "resumeButton"; x: 30; y: 148; width: 440; primary: true; text: "Back to my guest"; onClicked: root.setPaused(false) }
        HotelButton { objectName: "leaveButton"; x: 30; y: 207; width: 440; text: "Leave this visit and start fresh"; onClicked: root.reset() }
      }
    }
  }
}
