import QtQuick
import "Lessons.js" as Lessons
import "TypingEngine.js" as Engine

FocusScope {
  id: root
  objectName: "pawPostGame"
  implicitWidth: 1080; implicitHeight: 820
  focus: true
  property bool windowActive: true
  property bool reducedMotion: false
  property string lesson: "words"
  property string mode: "cozy"
  property string screen: "start"
  property var session: Engine.create("words", "cozy", Lessons.get("words").prompts, 1)
  readonly property string nextKey: session.typed !== session.target.slice(0, session.typed.length)
    ? "Backspace" : Lessons.keyHint(session.target[session.typed.length] || "")
  readonly property string recipient: ["Clover the fox", "Pip the rabbit", "Mochi the kitten"][(session.phase === "delivery" || session.phase === "results" ? Math.max(0, session.delivered - 1) : session.delivered) % 3]
  signal quitRequested()

  function reset() { screen = "start"; forceActiveFocus() }
  function start() {
    session = Engine.create(lesson, mode, Lessons.get(lesson).prompts, Date.now())
    screen = "play"
    forceActiveFocus()
  }
  function pause() {
    if (screen === "play") session = Engine.pause(session, Date.now())
    forceActiveFocus()
  }
  function typeCharacter(value) {
    if (screen !== "play" || !windowActive) return
    session = Engine.type(session, value, Date.now())
  }
  function safe(text) { return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
  function targetMarkup() {
    var text = ""
    for (var i = 0; i < session.target.length; i++) {
      var entered = i < session.typed.length
      var correct = entered && session.typed[i] === session.target[i]
      var value = entered ? session.typed[i] : session.target[i]
      var color = entered ? correct ? "#3E867C" : "#C05475" : i === session.typed.length ? "#4E3D64" : "#867695"
      text += '<span style="color:' + color + ';' + (entered && !correct ? 'text-decoration:underline;' : '')
        + (i === session.typed.length ? 'background-color:#E8DDF2;text-decoration:underline;' : '') + '">'
        + safe(value === " " ? "·" : value) + '</span>'
    }
    return text
  }
  onWindowActiveChanged: {
    if (!windowActive && screen === "play" && !session.paused && session.phase !== "results") pause()
  }
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      if (screen === "start") quitRequested()
      else if (session.phase === "results") reset()
      else pause()
    } else if (screen === "start") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) start()
      else { event.accepted = false; return }
    } else if (session.phase === "results") {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) reset()
      else { event.accepted = false; return }
    } else if (session.paused || !windowActive) {
      event.accepted = true; return
    } else if (event.key === Qt.Key_Backspace) session = Engine.backspace(session, Date.now())
    else if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
      event.accepted = false; return
    } else if (event.text && event.text.length === 1 && !event.isAutoRepeat) typeCharacter(event.text)
    else { event.accepted = false; return }
    event.accepted = true
  }
  Timer {
    interval: 100; repeat: true
    running: root.screen === "play" && root.session.phase === "play" && !root.session.paused && root.windowActive
    onTriggered: root.session = Engine.advance(root.session, Date.now())
  }
  Timer {
    interval: root.reducedMotion ? 400 : 900
    running: root.screen === "play" && root.session.phase === "delivery" && !root.session.paused && root.windowActive
    onTriggered: root.session = Engine.next(root.session)
  }
  Rectangle { anchors.fill: parent; color: "#FAF7F2" }
  MouseArea { anchors.fill: parent; onClicked: root.forceActiveFocus() }
  Item {
    id: page
    width: 1080; height: 820; anchors.centerIn: parent
    scale: Math.min(root.width / width, root.height / height)
    readonly property bool playing: root.screen === "play"
    readonly property bool finished: playing && root.session.phase === "results"

    MailSprite { x: 38; y: 27; width: 44; height: 34 }
    Text { x: 94; y: 25; text: "Paw Post"; font.pixelSize: 27; font.weight: Font.Bold; color: "#514460" }
    Text { x: 95; y: 59; text: "A LITTLE KINDNESS, LETTER BY LETTER"; font.pixelSize: 10; font.letterSpacing: 1.4; color: "#998A9C" }
    PostButton {
      objectName: "pauseButton"
      x: 864; y: 29; width: 180; height: 42
      text: !page.playing ? "Close" : page.finished ? "Choose a route" : root.session.paused ? "Resume" : "Pause  ·  Esc"
      onClicked: {
        if (!page.playing) root.quitRequested()
        else if (page.finished) root.reset()
        else root.pause()
      }
    }
    Rectangle { x: 36; y: 91; width: 1008; height: 1; color: "#E7DFE7" }

    Item {
      visible: !page.playing
      Column {
        x: 40; y: 139; width: 345; spacing: 18
        Text { text: "Little paws.\nHappy mail."; font.pixelSize: 49; lineHeight: 1.05; font.weight: Font.Bold; color: "#514460" }
        Text { width: 334; text: "Help animal friends send a little joy. Type each message to fly the mail across the clouds."; font.pixelSize: 17; lineHeight: 1.3; color: "#897C92"; wrapMode: Text.WordWrap }
        Column {
          spacing: 10
          Text { text: "1  PICK YOUR PRACTICE"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.3; color: "#8D7A9B" }
          Row {
            spacing: 7
            Repeater {
              model: Lessons.names()
              PostButton {
                required property var modelData
                objectName: "lesson-" + modelData.id
                width: 107; height: 43; font.pixelSize: 13
                text: modelData.name; selected: root.lesson === modelData.id
                onClicked: { root.lesson = modelData.id; root.forceActiveFocus() }
              }
            }
          }
          Text { width: 335; height: 37; text: Lessons.get(root.lesson).detail; font.pixelSize: 14; wrapMode: Text.WordWrap; color: "#897C92" }
        }
        Column {
          spacing: 10
          Text { text: "2  CHOOSE YOUR PACE"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.3; color: "#8D7A9B" }
          Row {
            spacing: 8
            PostButton { objectName: "cozyMode"; width: 163; height: 44; text: "Cozy route"; selected: root.mode === "cozy"; onClicked: { root.mode = "cozy"; root.forceActiveFocus() } }
            PostButton { objectName: "dashMode"; width: 166; height: 44; text: "90-second dash"; selected: root.mode === "dash"; onClicked: { root.mode = "dash"; root.forceActiveFocus() } }
          }
          Text { width: 335; height: 38; text: root.mode === "cozy" ? "10 deliveries. No countdown. Take your time." : "See how much kindness you can deliver in 90 seconds of typing."; font.pixelSize: 14; wrapMode: Text.WordWrap; color: "#897C92" }
        }
        PostButton { objectName: "startButton"; width: 337; height: 54; primary: true; text: "Start delivering  →"; onClicked: root.start() }
        Text { width: 330; text: "Go gently. Accuracy matters more than speed."; font.pixelSize: 13; wrapMode: Text.WordWrap; color: "#998A9C" }
      }
      Rectangle {
        x: 416; y: 135; width: 628; height: 433; radius: 27; color: "#EAF0F4"
        Image { objectName: "menuArtwork"; anchors.fill: parent; source: "assets/cloud-post.png"; fillMode: Image.PreserveAspectFit; asynchronous: false; smooth: true }
      }
      Text { x: 438; y: 590; width: 590; text: "THREE FRIENDS. A SKY FULL OF STORIES."; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 11; font.letterSpacing: 1.7; font.weight: Font.Bold; color: "#9B8BA1" }
      Row {
        x: 450; y: 622; spacing: 15
        Repeater {
          model: [{name: "Clover", note: "A curious fox", color: "#F4E4DA"}, {name: "Pip", note: "A cheerful rabbit", color: "#E8EADF"}, {name: "Mochi", note: "A dreamy kitten", color: "#EAE1F1"}]
          Rectangle {
            required property var modelData
            width: 173; height: 83; radius: 16; color: modelData.color
            Text { x: 16; y: 15; text: modelData.name; font.pixelSize: 20; font.weight: Font.Bold; color: "#655370" }
            Text { x: 16; y: 46; text: modelData.note; font.pixelSize: 13; color: "#9A839B" }
            Text { anchors.right: parent.right; anchors.rightMargin: 14; y: 16; text: "✦"; font.pixelSize: 24; color: "#BDA3BB" }
          }
        }
      }
    }

    Item {
      visible: page.playing && !page.finished
      Row {
        x: 40; y: 110; spacing: 14
        Repeater {
          model: [
            {label: "YOUR ROUTE", value: Lessons.get(root.session.lesson).name},
            {label: root.session.mode === "dash" ? "TIME LEFT" : "MAIL DELIVERED", value: root.session.mode === "dash" ? Math.ceil(Math.max(0, root.session.limit - root.session.elapsed) / 1000) + " sec" : root.session.delivered + " / " + root.session.goal},
            {label: "ACCURACY", value: root.session.attempts ? Engine.accuracy(root.session) + "%" : "Ready"},
            {label: "TYPING SPEED", value: root.session.elapsed >= 3000 ? Engine.wpm(root.session) + " wpm" : "—"}
          ]
          Rectangle {
            required property var modelData
            width: 239; height: 69; radius: 14; color: "#F1EAF2"
            Text { x: 17; y: 11; text: modelData.label; font.pixelSize: 10; font.letterSpacing: 1.1; color: "#9B89A7"; font.weight: Font.Bold }
            Text { x: 17; y: 29; text: modelData.value; font.pixelSize: 23; font.weight: Font.DemiBold; color: "#635174" }
          }
        }
      }
      Rectangle {
        id: sky
        x: 40; y: 194; width: 1000; height: 232; color: "#B4DCEE"; clip: true
        Image { width: parent.width; height: width * 2 / 3; y: -236; source: "assets/cloud-post.png"; smooth: true }
        Rectangle {
          anchors.right: parent.right; anchors.rightMargin: 20; y: 18; width: 270; height: 41; radius: 12; color: "#F2FFFCF7"
          Text { anchors.centerIn: parent; text: (root.session.phase === "delivery" ? "♥  Delivered to " : "TO  ") + root.recipient; font.pixelSize: 15; font.weight: Font.Medium; color: "#8E718F" }
        }
        MailSprite {
          id: flyingMail
          objectName: "flyingMail"
          readonly property real fraction: root.session.target.length ? Engine.progress(root.session) / root.session.target.length : 0
          x: 110 + fraction * 715; y: 140 - Math.sin(fraction * Math.PI) * 100
          width: 62; height: 46; rotation: -12 + fraction * 24
          visible: root.session.phase !== "results"
          Behavior on x { enabled: !root.reducedMotion; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
          Behavior on y { enabled: !root.reducedMotion; NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
          Behavior on rotation { enabled: !root.reducedMotion; NumberAnimation { duration: 110 } }
        }

      }
      Rectangle {
        x: 40; y: 443; width: 1000; height: 170; radius: 19
        color: root.session.error ? "#FFF0F1" : "#FFFDF9"
        border.color: root.session.error ? "#E0A4B6" : "#E4DCE8"
        border.width: 2
        Accessible.role: Accessible.EditableText
        Accessible.name: "Type this message: " + root.session.target
        Accessible.description: root.session.note
        Text { x: 22; y: 14; text: root.session.phase === "delivery" ? "SIGNED, SEALED, DELIVERED" : "TYPE THE MESSAGE"; font.pixelSize: 10; font.letterSpacing: 1.5; color: "#A693AC"; font.weight: Font.Bold }
        Text {
          objectName: "targetText"
          x: 24; y: 43; width: 952; height: 85
          text: root.targetMarkup(); textFormat: Text.RichText
          font.family: Qt.platform.os === "osx" ? "Menlo" : "monospace"; font.pixelSize: root.session.target.length > 24 ? 27 : 36
          font.weight: Font.DemiBold; wrapMode: Text.WrapAnywhere
          horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        Text { x: 24; y: 139; width: 952; text: root.session.note; horizontalAlignment: Text.AlignHCenter; color: root.session.error ? "#BB6A83" : "#9B88A5"; font.pixelSize: 13 }
      }
      Column {
        x: 166; y: 635; spacing: 5
        Repeater {
          model: ["qwertyuiop", "asdfghjkl;", "zxcvbnm,."]
          Row {
            required property string modelData
            required property int index
            x: index * 17; spacing: 5
            Repeater {
              model: modelData.split("")
              Rectangle {
                required property string modelData
                readonly property bool next: root.nextKey !== "Backspace" && String(root.session.target[root.session.typed.length] || "").toLowerCase() === modelData
                width: 42; height: 34; radius: 7
                color: next ? "#8570A2" : "#EFE9F0"
                border.color: next ? "#6D578D" : "#E4DCE8"
                Text { anchors.centerIn: parent; text: parent.modelData.toUpperCase(); color: parent.next ? "#FFFFFF" : "#9B8CA5"; font.pixelSize: 14; font.weight: Font.DemiBold }
                Rectangle { visible: modelData === "f" || modelData === "j"; width: 9; height: 2; x: 17; y: 28; color: parent.next ? "#FFFFFF" : "#BAACC2" }
              }
            }
          }
        }
      }
      Rectangle {
        x: 690; y: 642; width: 225; height: 94; radius: 15; color: "#F0EAF3"
        Text { x: 18; y: 13; text: "NEXT KEY"; font.pixelSize: 10; font.letterSpacing: 1.3; font.weight: Font.Bold; color: "#AA97B4" }
        Text { objectName: "nextKeyLabel"; x: 18; y: 36; text: root.session.phase === "delivery" ? "Lovely work!" : root.nextKey; font.pixelSize: 24; font.weight: Font.DemiBold; color: "#7E6498" }
      }
      Text { x: 45; y: 754; width: 985; text: Lessons.get(root.session.lesson).tip; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 13; color: "#9B8BA3" }
    }

    Item {
      visible: page.finished
      Image { x: 40; y: 135; width: 430; height: 560; source: "assets/cloud-post.png"; fillMode: Image.PreserveAspectFit; smooth: true }
      Column {
        x: 495; y: 149; width: 530; spacing: 23
        Text { text: "ROUTE COMPLETE"; font.pixelSize: 11; font.letterSpacing: 2; color: "#A48AAF"; font.weight: Font.Bold }
        Text { width: 530; text: "You made their day."; font.pixelSize: 39; font.weight: Font.Bold; color: "#655174"; wrapMode: Text.WordWrap }
        Text { width: 500; text: root.session.delivered + " happy deliveries. A little more confidence at the keyboard."; font.pixelSize: 19; lineHeight: 1.3; color: "#9A87A5"; wrapMode: Text.WordWrap }
        Rectangle {
          width: 515; height: 116; radius: 18; color: "#EEE5F0"
          Row {
            x: 24; y: 24; spacing: 38
            Repeater {
              model: [{label: "ACCURACY", value: Engine.accuracy(root.session) + "%"}, {label: "SPEED", value: root.session.elapsed >= 1000 ? Engine.wpm(root.session) + " wpm" : "—"}, {label: "BEST STREAK", value: String(root.session.bestStreak)}]
              Column {
                required property var modelData
                spacing: 8
                Text { text: modelData.value; font.pixelSize: 28; font.weight: Font.Bold; color: "#7D6196" }
                Text { text: modelData.label; font.pixelSize: 10; font.letterSpacing: 1.2; color: "#A089AD" }
              }
            }
          }
        }
        Rectangle {
          width: 515; height: 107; radius: 18; color: "#F7E9D8"
          Text { x: 18; y: 24; text: "✦"; font.pixelSize: 47; color: "#D5AA6E" }
          Text { x: 80; y: 19; text: Engine.badge(root.session).title; font.pixelSize: 23; font.weight: Font.Bold; color: "#9B784D" }
          Text { x: 80; y: 53; width: 409; text: Engine.badge(root.session).detail; font.pixelSize: 14; lineHeight: 1.2; color: "#B18D68"; wrapMode: Text.WordWrap }
        }
        PostButton { objectName: "againButton"; width: 230; primary: true; text: "Choose another route  →"; onClicked: root.reset() }
      }
    }

    Rectangle {
      visible: page.playing && root.session.paused
      anchors.fill: parent; color: "#DBFAF7F2"; z: 10
      MouseArea { anchors.fill: parent; onClicked: root.forceActiveFocus() }
      Rectangle {
        width: 520; height: 316; anchors.centerIn: parent; radius: 25
        color: "#FFFDFC"; border.color: "#E2D5E8"; border.width: 2
        MailSprite { x: 230; y: 28; width: 60; height: 44 }
        Text { y: 92; width: parent.width; text: "A little cloud break."; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 31; font.weight: Font.Bold; color: "#6C567D" }
        Text { x: 40; y: 139; width: 440; text: "Your mail and your clock can wait.\nCome back whenever you're ready."; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 16; lineHeight: 1.4; color: "#A08EAA" }
        PostButton { objectName: "resumeButton"; x: 140; y: 215; width: 240; primary: true; text: "Back to delivering"; onClicked: root.pause() }
        PostButton { objectName: "routeButton"; x: 174; y: 270; width: 172; height: 33; text: "Choose a new route"; font.pixelSize: 12; onClicked: root.reset() }
      }
    }
    Text { x: 40; y: 792; text: "OMARCHY KIDS / PAW POST"; font.pixelSize: 10; font.letterSpacing: 1.4; color: "#B8A9BF" }
    PostButton {
      objectName: "motionButton"; x: 864; y: 783; width: 178; height: 28; font.pixelSize: 11
      text: root.reducedMotion ? "Motion: reduced" : "Motion: on"
      onClicked: { root.reducedMotion = !root.reducedMotion; root.forceActiveFocus() }
    }
  }
}
