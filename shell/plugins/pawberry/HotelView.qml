import QtQuick
import QtQuick.Controls.Basic
import QtCore
import "WorkSteps.js" as Steps
import "PracticePolicy.js" as Practice
import "WorkSession.js" as Session
import "PetCatalog.js" as Catalog
import "PetCollection.js" as Collection

FocusScope {
  id: root
  property bool windowActive: true
  property var policy: null
  readonly property bool policyReady: !policy || policy.ready
  readonly property var practiceStatus: policy ? policy.status : null
  property int requestToken: 0
  property var pendingSession: null
  property string pendingAction: ""
  property string problemId: ""
  property string practiceNote: ""
  readonly property bool checking: pendingSession !== null
  function available(kind) { return kind === "mixed" || Practice.available(practiceStatus, kind) }
  function chooseOperation(kind) {
    operation = kind
    if (kind === "divide" || ((kind === "add" || kind === "subtract") && digitCount === 1)) digitCount = 2
    practiceNote = ""; focusAnswer()
  }
  function quotaText(kind) {
    if (!practiceStatus || !practiceStatus.remaining || practiceStatus.remaining[kind] === null || practiceStatus.remaining[kind] === undefined) return ""
    return operationNames[kind] + ": " + practiceStatus.remaining[kind] + " left today"
  }
  Connections {
    target: root.policy
    function onReply(token, result) { root.policyReply(token, result) }
  }
  property string operation: "add"
  property int digitCount: 2
  property bool reducedMotion: false
  property var session: null
  property string answerInput: ""
  property bool showHint: false
  property url collectionLocation: "file://" + (StandardPaths.writableLocation(StandardPaths.StateLocation) + "/omarchy-pawberry/collection.ini").split("/").map(encodeURIComponent).join("/")
  readonly property var collection: collectionStore.collection
  property bool collectionOpen: false
  property bool parentSettingsOpen: false
  property bool parentSaving: false
  property bool wasPausedBeforeSettings: false
  property var visitPets: ["peaches", "biscuit", "bluebell"]
  property var lastReward: null
  readonly property string currentPet: visitPets[session ? session.problemIndex : 0] || "peaches"
  readonly property var problem: session ? Session.current(session) : null
  readonly property var step: session ? Session.activeStep(session) : null
  readonly property bool working: session !== null && session.phase === "work"
  readonly property bool roomComplete: session !== null && session.phase === "complete"
  readonly property bool paused: session !== null && session.paused
  readonly property var operationNames: ({add: "Addition", subtract: "Subtraction", multiply: "Multiplication", divide: "Division", mixed: "Mixed"})
  signal quitRequested()
  focus: true
  CollectionStore { id: collectionStore; location: root.collectionLocation }

  // A focus scope otherwise restores the last button, even after it is hidden.
  Item { id: answerInputTarget; objectName: "answerInputTarget"; focus: true }
  function focusAnswer() { answerInputTarget.forceActiveFocus() }
  function reset() { parentSettingsOpen = false; parentSaving = false; parents.clear(); requestToken++; pendingSession = null; pendingAction = ""; problemId = ""; practiceNote = ""; if (policy) { policy.cancel(); policy.refresh() }; session = null; answerInput = ""; showHint = false; collectionOpen = false; lastReward = null; focusAnswer() }
  function openCollection() {
    if (working || paused || parentSettingsOpen || checking) return
    wardrobe.selectedPet = roomComplete ? currentPet : (collection.pets[0] || "peaches")
    collectionOpen = true; wardrobe.forceActiveFocus()
  }
  function closeCollection() { collectionOpen = false; focusAnswer() }
  function equip(petId, accessoryId) { collectionStore.save(Collection.equip(collection, petId, accessoryId)) }
  function wearReward() {
    if (lastReward && lastReward.accessoryId) equip(lastReward.petId, lastReward.accessoryId)
    focusAnswer()
  }
  function openParentSettings() {
    if (checking || parentSaving || parentSettingsOpen) return
    wasPausedBeforeSettings = paused
    if (session && session.phase !== "results") setPaused(true)
    parentSettingsOpen = true
    parents.open()
    if (policy) policy.refresh()
  }
  function closeParentSettings() {
    if (parentSaving) return
    parents.clear(); parentSettingsOpen = false
    if (session && session.phase !== "results" && !wasPausedBeforeSettings && windowActive) setPaused(false)
    if (collectionOpen) wardrobe.forceActiveFocus()
    else focusAnswer()
  }
  function saveParentLimits(limits, password) {
    if (!parentSettingsOpen || parentSaving || !policy || !policyReady || !policy.managed) return
    parentSaving = true
    policy.saveLimits(++requestToken, limits, password)
  }
  function newProblem(kind) { return Steps.generate(kind, Practice.sizeFor(kind, digitCount)) }
  function beginProblem(next) {
    var candidate = next.problems[next.problemIndex]
    if (!Practice.available(practiceStatus, candidate.operation)) {
      var kind = Practice.nextKind("mixed", practiceStatus)
      candidate = newProblem(kind)
      next.problems[next.problemIndex] = candidate
      next.board = JSON.parse(JSON.stringify(candidate.board))
      practiceNote = "Today's limit is reached. Let's try " + operationNames[kind].toLowerCase() + "!"
    }
    if (policy && policy.managed) {
      pendingSession = next; pendingAction = "begin"
      policy.request(++requestToken, {cmd: "begin", problem: {a: candidate.a, b: candidate.b, operation: candidate.operation}})
    } else { session = next; focusAnswer() }
  }
  function start() {
    if (checking || parentSettingsOpen || !policyReady || !available(operation)) return
    var problems = []
    for (var i = 0; i < 3; i++) {
      var kind = Practice.nextKind(operation, practiceStatus)
      var candidate = newProblem(kind)
      for (var attempt = 0; attempt < 30 && problems.some(function(p) { return p.a === candidate.a && p.b === candidate.b && p.operation === candidate.operation }); attempt++)
        candidate = newProblem(kind)
      problems.push(candidate)
    }
    visitPets = Collection.guests(collection, Catalog.petIds, problems.length)
    answerInput = ""; showHint = false; lastReward = null; collectionOpen = false; practiceNote = ""
    beginProblem(Session.create(problems))
  }
  function welcome(next) {
    lastReward = Collection.award(collection, currentPet, Catalog.accessoryIds)
    collectionStore.save(lastReward.collection)
    next.paused = paused || !windowActive
    session = next; answerInput = ""; showHint = false; practiceNote = ""; focusAnswer()
  }
  function policyReply(token, result) {
    if (token === requestToken && parentSaving) {
      parentSaving = false
      parents.finish(result)
      return
    }
    if (token !== requestToken || !pendingSession) return
    var next = pendingSession, action = pendingAction
    pendingSession = null; pendingAction = ""
    if (!result.ok) {
      if (result.error === "daily_limit" || result.error === "stale_problem") {
        reset()
        practiceNote = result.error === "daily_limit" ? "That practice is done for today. Pick another kind of math!" : "Another visit was opened. Please start a new visit here."
      } else practiceNote = "Couldn't check with parent controls. Please try again."
      focusAnswer(); return
    }
    if (action === "complete") welcome(next)
    else { problemId = result.id; next.paused = !windowActive; session = next; focusAnswer() }
  }
  function check() {
    if (!working || paused || collectionOpen || parentSettingsOpen || checking) return
    var next = Session.submit(session, answerInput)
    if (session.phase === "work" && next.phase === "complete") {
      if (policy && policy.managed) {
        pendingSession = next; pendingAction = "complete"
        policy.request(++requestToken, {cmd: "complete", id: problemId, answer: problem.answer})
      } else welcome(next)
      return
    }
    if (next.stepIndex > session.stepIndex) { answerInput = ""; showHint = false }
    session = next; practiceNote = ""; focusAnswer()
  }
  function nextRoom() {
    if (checking || parentSettingsOpen || !roomComplete) return
    var next = Session.advance(session)
    answerInput = ""; showHint = false; lastReward = null
    if (next.phase === "work") beginProblem(next)
    else { session = next; focusAnswer() }
  }
  function setPaused(value) { if (session) session = Session.pause(session, value); if (!value) focusAnswer() }
  onWindowActiveChanged: if (!windowActive && session && session.phase !== "results") setPaused(true)
  Keys.onPressed: function(event) {
    if (parentSettingsOpen) return
    if (event.isAutoRepeat) { event.accepted = true; return }
    if (collectionOpen) { if (event.key === Qt.Key_Escape) { closeCollection(); event.accepted = true }; return }
    if (event.key === Qt.Key_Escape && session && session.phase !== "results") { setPaused(!paused); event.accepted = true; return }
    if (!working || paused || checking) return
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
    HotelButton { objectName: "collectionButton"; x: 501; y: 28; width: 167; height: 40; text: "My collection  ·  " + root.collection.pets.length; enabled: !root.working && !root.paused && !root.parentSettingsOpen && !root.checking; onClicked: root.openCollection() }
    HotelButton { objectName: "parentSettingsButton"; x: 678; y: 28; width: 126; height: 40; text: "Parents"; enabled: !root.parentSettingsOpen && !root.checking; onClicked: root.openParentSettings() }
    HotelButton { objectName: "motionButton"; x: 814; y: 28; width: 134; enabled: !root.parentSettingsOpen; height: 40; text: root.reducedMotion ? "Motion: off" : "Motion: on"; onClicked: { root.reducedMotion = !root.reducedMotion; if (!root.collectionOpen) root.focusAnswer() } }
    HotelButton { objectName: "pauseButton"; x: 958; y: 28; width: 80; height: 40; visible: root.session !== null && root.session.phase !== "results" && !root.parentSettingsOpen; text: "Pause"; onClicked: root.setPaused(true) }
    HotelButton { x: 1048; y: 28; width: 38; height: 40; text: "×"; onClicked: root.quitRequested() }
    Rectangle { x: 36; y: 91; width: 1048; height: 1; color: "#E5DADF" }

    Item {
      anchors.fill: parent; visible: root.session === null && !root.collectionOpen && !root.parentSettingsOpen
      Text { x: 40; y: 140; text: "Tiny paws.\nBig brainwaves."; color: "#594355"; font.pixelSize: 48; font.bold: true; lineHeight: 1.08 }
      Text { x: 43; y: 268; width: 500; text: "23 friends to meet! Show your math work to welcome three surprise guests each visit. Finish each problem to earn a pet and a new accessory."; color: "#806C7C"; font.pixelSize: 18; wrapMode: Text.WordWrap; lineHeight: 1.3 }
      Text { x: 43; y: 372; text: "1   PICK YOUR PRACTICE"; color: "#977288"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.6 }
      Row {
        x: 40; y: 401; spacing: 8
        Repeater {
          model: ["add", "subtract", "multiply", "divide", "mixed"]
          delegate: HotelButton {
            required property string modelData
            objectName: "operation-" + modelData
            width: 100; height: 46; enabled: root.available(modelData) && !root.checking; text: root.operationNames[modelData]; selected: root.operation === modelData
            font.pixelSize: 12; onClicked: root.chooseOperation(modelData)
          }
        }
      }
      Text { objectName: "quotaLabel"; x: 43; y: 458; width: 530; text: [root.quotaText("add"), root.quotaText("subtract")].filter(function(text) { return text !== "" }).join("   ·   "); color: "#977288"; font.pixelSize: 12 }
      Text { x: 43; y: 493; text: "2   CHOOSE YOUR NUMBERS"; color: "#977288"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.6 }
      Row {
        x: 40; y: 522; spacing: 10
        Repeater {
          model: root.operation === "divide" ? [2] : root.operation === "multiply" || root.operation === "mixed" ? [1, 2, 3] : [2, 3]
          delegate: HotelButton {
            required property int modelData
            objectName: "digits-" + modelData
            width: root.operation === "divide" ? 530 : root.operation === "multiply" || root.operation === "mixed" ? 170 : 260; height: 48
            font.pixelSize: 13
            text: root.operation === "divide" ? "Easy table facts   ·   42 ÷ 6   ·   no remainders"
              : modelData === 1 ? "1 digit  ·  7 × 6"
              : modelData === 2 ? "2 digits   ·   " + (root.operation === "subtract" ? "68 − 24" : root.operation === "multiply" ? "24 × 38" : "24 + 38")
              : "3 digits   ·   " + (root.operation === "subtract" ? "247 − 185" : root.operation === "multiply" ? "247 × 185" : "247 + 185")
            selected: root.digitCount === modelData; onClicked: { root.digitCount = modelData; root.focusAnswer() }
          }
        }
      }
      HotelButton { objectName: "startButton"; x: 40; y: 616; width: 530; height: 56; primary: true; enabled: root.policyReady && !root.checking && root.available(root.operation); text: root.checking ? "Checking practice…" : !root.policyReady ? "Connecting to parent controls…" : !root.available(root.operation) ? "Pick another kind of math" : "Open the pet hotel  →"; font.pixelSize: 17; onClicked: root.start() }
      Text { x: 43; y: 691; width: 520; text: root.practiceNote || "No countdown. No lost hearts.\nWe check your working before the final answer."; wrapMode: Text.WordWrap; color: "#94798A"; font.pixelSize: 14; lineHeight: 1.4 }
      Rectangle {
        x: 611; y: 143; width: 470; height: 582; radius: 25; color: "#F1E4E9"
        Text { x: 25; y: 27; text: "WHO WILL YOU WELCOME TODAY?"; color: "#916D83"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.4 }
        PetRoom { objectName: "previewRoom"; x: 27; y: 82; width: 416; height: 365; reducedMotion: true }
        Text { x: 32; y: 482; width: 406; text: "23 pets. 20 collectible accessories.\nBows, crowns, flowers, hats and scarves.\nYour collection stays with you!"; horizontalAlignment: Text.AlignHCenter; color: "#8D7083"; font.pixelSize: 15; lineHeight: 1.4 }
      }
    }

    Item {
      anchors.fill: parent; visible: (root.working || root.roomComplete) && !root.collectionOpen && !root.parentSettingsOpen; enabled: !root.paused
      Rectangle {
        x: 36; y: 119; width: 656; height: 642; radius: 23; color: "#FFFDF9"; border.color: "#E9DDE0"
        Text { x: 26; y: 20; text: root.session && root.problem ? "GUEST " + (root.session.problemIndex + 1) + " / 3  ·  " + root.operationNames[root.problem.operation].toUpperCase() : ""; color: "#967487"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
        Text { x: 26; y: 46; text: root.problem ? root.problem.a + " " + root.problem.symbol + " " + root.problem.b : ""; color: "#594355"; font.pixelSize: 32; font.bold: true }
        Text { x: 336; y: 54; width: 292; text: root.problem && root.problem.operation === "divide" ? "Your checked division work" : "Your checked column work"; horizontalAlignment: Text.AlignRight; color: "#9B8691"; font.pixelSize: 13 }
        WorkBoard { objectName: "workBoard"; x: 22; y: 99; width: 605; height: 294; problem: root.problem; board: root.session ? root.session.board : null; step: root.step }
        Rectangle {
          x: 16; y: 413; width: 624; height: 212; radius: 17; color: root.roomComplete ? "#EDF3E8" : "#FAF0F2"
          Text { x: 18; y: 13; text: root.roomComplete ? "PET REVEALED! EVERY STEP CHECKED." : root.session && root.step && root.problem ? "STEP " + (root.session.stepIndex + 1) + " / " + root.problem.steps.length : ""; color: "#967487"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1 }
          Text { objectName: "stepTitle"; x: 18; y: 35; width: 588; text: root.step ? root.step.title : "You welcomed " + Catalog.pet(root.currentPet).name + "!"; color: "#644858"; font.pixelSize: 21; font.bold: true; elide: Text.ElideRight }
          Text { objectName: "stepExpression"; x: 18; y: 66; width: 588; text: root.step ? root.step.expression : root.lastReward && root.lastReward.accessoryId ? "You earned a " + Catalog.accessory(root.lastReward.accessoryId).name + "!" : "Your accessory wardrobe is complete. Enjoy your guest!"; color: "#735668"; font.pixelSize: 19; elide: Text.ElideRight }
          Rectangle {
            objectName: "answerEntry"; x: 18; y: 103; width: 175; height: 49; radius: 11; visible: root.working
            color: "#FFFDFC"; border.width: 2; border.color: root.session && root.session.error ? "#BA6266" : "#A77B8E"
            Text { anchors.centerIn: parent; text: root.answerInput || "?"; color: root.answerInput ? "#594355" : "#BEA2B0"; font.pixelSize: 29; font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace" }
            MouseArea { anchors.fill: parent; onClicked: root.focusAnswer() }
            Accessible.role: Accessible.EditableText
            Accessible.name: "Answer for this step"
          }
          HotelButton { objectName: "checkButton"; x: 204; y: 103; width: 215; height: 49; visible: root.working; enabled: !root.checking; primary: true; text: root.checking ? "Checking practice…" : root.step && root.step.kind === "final" ? "Reveal my pet  ♥" : "Check step  ↵"; onClicked: root.check() }
          HotelButton { objectName: "hintButton"; x: 430; y: 103; width: 175; height: 49; visible: root.working; text: root.showHint ? "Hide hint" : "A little hint"; onClicked: { root.showHint = !root.showHint; root.focusAnswer() } }
          HotelButton { objectName: "wearRewardButton"; x: 18; y: 104; width: 195; height: 49; visible: root.roomComplete && root.lastReward !== null && !!root.lastReward.accessoryId; text: root.collection.outfits[root.currentPet] === (root.lastReward ? root.lastReward.accessoryId : "") ? "Looking lovely!" : "Try it on  ♥"; onClicked: root.wearReward() }
          HotelButton { objectName: "nextButton"; x: 224; y: 104; width: 380; height: 49; visible: root.roomComplete; enabled: !root.checking; primary: true; text: root.checking ? "Preparing practice…" : root.session && root.session.rooms === 3 ? "See our happy guests  →" : "Prepare the next room  →"; onClicked: root.nextRoom() }
          Text {
            objectName: "stepFeedback"; x: 20; y: 163; width: 582; height: 45
            text: root.practiceNote || (root.showHint && root.step ? root.step.hint : root.session && root.session.note ? root.session.note : "Type a number, then press Enter. H opens a hint.")
            color: root.session && root.session.error && !root.showHint ? "#A35462" : "#8D7281"
            font.pixelSize: 13; wrapMode: Text.WordWrap
          }
        }
      }
      PetRoom {
        objectName: "guestRoom"; x: 713; y: 119; width: 371; height: 337
        petId: root.currentPet; accessoryId: root.collection.outfits[root.currentPet] || ""
        roomNumber: root.session ? root.session.problemIndex + 1 : 1
        progress: root.session && root.problem ? Math.min(1, root.session.stepIndex / (root.problem.steps.length - 1)) : 0
        welcomed: root.roomComplete
        reducedMotion: root.reducedMotion
      }
      Rectangle { x: 728; y: 472; width: 340; height: 7; radius: 4; color: "#E8DDE1"; Rectangle { width: root.session && root.problem ? parent.width * root.session.stepIndex / root.problem.steps.length : 0; height: parent.height; radius: 4; color: "#AD788E" } }
      Text { x: 728; y: 490; text: root.session ? root.session.ledger.length + " steps checked  ·  " + root.session.rooms + " / 3 pets welcomed" : ""; color: "#8E7484"; font.pixelSize: 12 }
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
            Text { text: modelData.kind === "divide-groups" ? modelData.expression.replace("?", String(modelData.value)) : modelData.expression + " = " + modelData.value; width: parent.width; color: "#624C5D"; font.pixelSize: 14; wrapMode: Text.WordWrap }
          }
          ScrollBar.vertical: ScrollBar {}
        }
      }
    }

    Item {
      anchors.fill: parent; visible: root.session !== null && root.session.phase === "results" && !root.collectionOpen && !root.parentSettingsOpen
      Text { x: 40; y: 135; width: 1040; text: "You welcomed all three pets!"; color: "#624658"; font.pixelSize: 37; font.bold: true; horizontalAlignment: Text.AlignHCenter }
      Text { x: 40; y: 194; width: 1040; text: "Saved in your collection: " + root.collection.pets.length + " / 23 friends and " + root.collection.accessories.length + " / 20 accessories."; color: "#9A7B8E"; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter }
      Row {
        x: 55; y: 247; spacing: 22
        Repeater { model: 3; delegate: PetRoom { required property int index; objectName: "welcomedPet-" + index; width: 322; height: 320; petId: root.visitPets[index]; accessoryId: root.collection.outfits[petId] || ""; roomNumber: index + 1; progress: 1; welcomed: true; reducedMotion: root.reducedMotion } }
      }
      Text { x: 80; y: 603; width: 960; text: root.session ? root.session.checked + " steps checked  ·  " + root.session.mistakes + (root.session.mistakes === 1 ? " retry" : " retries") + "  ·  all three rooms ready" : ""; color: "#806379"; font.pixelSize: 19; horizontalAlignment: Text.AlignHCenter }
      HotelButton { objectName: "againButton"; x: 356; y: 665; width: 410; height: 54; primary: true; text: "Another lovely day at the hotel  →"; onClicked: root.reset() }
    }

    CollectionView {
      id: wardrobe; objectName: "collectionView"; x: 0; y: 110; width: 1120; height: 690
      visible: root.collectionOpen && !root.parentSettingsOpen; collection: root.collection
      onEquipRequested: function(petId, accessoryId) { root.equip(petId, accessoryId) }
      onCloseRequested: root.closeCollection()
    }

    ParentSettings {
      id: parents; objectName: "parentSettings"; x: 18; y: 100; width: 1084; height: 664
      visible: root.parentSettingsOpen
      status: root.practiceStatus || ({})
      connected: root.policy !== null && root.policyReady
      managed: root.policy !== null && root.policy.managed
      busy: root.parentSaving
      onSaveRequested: function(limits, password) { root.saveParentLimits(limits, password) }
      onCloseRequested: root.closeParentSettings()
      onRetryRequested: if (root.policy) root.policy.refresh()
    }

    Rectangle {
      anchors.fill: parent; visible: root.paused && !root.parentSettingsOpen; color: "#99594A56"; z: 20
      MouseArea { anchors.fill: parent }
      Rectangle {
        anchors.centerIn: parent; width: 500; height: 338; radius: 25; color: "#FFF8F4"
        Text { x: 28; y: 33; width: 444; text: "A little paws."; color: "#67485D"; font.pixelSize: 32; font.bold: true; horizontalAlignment: Text.AlignHCenter }
        Text { x: 30; y: 94; width: 440; text: "Your work and your guests are safe right here."; color: "#907486"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
        HotelButton { objectName: "resumeButton"; x: 30; y: 148; width: 440; primary: true; text: "Back to my guest"; onClicked: root.setPaused(false) }
        HotelButton { objectName: "pausedParentSettingsButton"; x: 30; y: 207; width: 440; text: "Parent settings"; onClicked: root.openParentSettings() }
        HotelButton { objectName: "leaveButton"; x: 30; y: 266; width: 440; text: "Leave this visit and start fresh"; onClicked: root.reset() }
      }
    }
  }
}
