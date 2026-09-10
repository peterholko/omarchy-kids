import QtQuick
import QtQuick.Controls.Basic
import "PetCatalog.js" as Catalog

FocusScope {
  id: root
  required property var collection
  property string selectedPet: collection.pets.length ? collection.pets[0] : "peaches"
  property string tab: "pets"
  readonly property bool petOwned: collection.pets.indexOf(selectedPet) !== -1
  signal equipRequested(string petId, string accessoryId)
  signal closeRequested()
  Keys.onEscapePressed: closeRequested()

  Rectangle { anchors.fill: parent; color: "#FAF5F2" }
  Text { x: 40; y: 12; text: "Your little circle of friends"; color: "#594355"; font.pixelSize: 32; font.bold: true }
  Text { x: 42; y: 57; text: collection.pets.length + " / " + Catalog.pets.length + " pets  ·  " + collection.accessories.length + " / " + Catalog.accessories.length + " accessories  ·  saved for your next visit"; color: "#806C7C"; font.pixelSize: 15 }
  HotelButton { objectName: "closeCollectionButton"; x: 929; y: 16; width: 155; height: 43; text: "Back to hotel"; onClicked: root.closeRequested() }

  Rectangle {
    x: 36; y: 105; width: 327; height: 531; radius: 25; color: "#F1E4E9"
    Text { x: 20; y: 25; width: 287; text: root.petOwned ? Catalog.pet(root.selectedPet).name : "A friend to discover"; horizontalAlignment: Text.AlignHCenter; color: "#654E5E"; font.pixelSize: 28; font.bold: true }
    Text { x: 20; y: 64; width: 287; text: root.petOwned ? Catalog.pet(root.selectedPet).kind : "Finish a problem to meet a pet"; horizontalAlignment: Text.AlignHCenter; color: "#8D7083"; font.pixelSize: 15 }
    PetPortrait {
      objectName: "collectionPortrait"; x: 35; y: 104; width: 257; height: 276
      petId: root.selectedPet; accessoryId: root.collection.outfits[root.selectedPet] || ""
      visible: root.petOwned
    }
    Text { x: 35; y: 175; width: 257; text: "?"; visible: !root.petOwned; color: "#C38D9F"; font.pixelSize: 104; horizontalAlignment: Text.AlignHCenter }
    Text {
      x: 24; y: 399; width: 279; height: 57; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
      text: root.petOwned ? (root.collection.outfits[root.selectedPet] ? "Wearing " + Catalog.accessory(root.collection.outfits[root.selectedPet]).name : "Choose an accessory from your wardrobe.") : "Your collected pets and accessories stay here, even after you close the game."
      color: "#806379"; font.pixelSize: 15
    }
    HotelButton {
      objectName: "removeAccessoryButton"; x: 29; y: 467; width: 269; height: 43
      text: "Take accessory off"; enabled: root.petOwned && !!root.collection.outfits[root.selectedPet]
      onClicked: root.equipRequested(root.selectedPet, "")
    }
  }
  HotelButton { objectName: "petsTab"; x: 390; y: 104; width: 330; height: 45; text: "Pet album  ·  " + root.collection.pets.length; selected: root.tab === "pets"; onClicked: root.tab = "pets" }
  HotelButton { objectName: "accessoriesTab"; x: 731; y: 104; width: 353; height: 45; text: "Accessory wardrobe  ·  " + root.collection.accessories.length; selected: root.tab === "accessories"; onClicked: root.tab = "accessories" }
  Text { x: 391; y: 165; width: 690; text: root.tab === "pets" ? (root.collection.pets.length === Catalog.pets.length ? "You have met every friend! Select a pet to dress up." : "Select a friend to dress up. Mystery pets are still waiting to meet you.") : (root.collection.accessories.length === Catalog.accessories.length ? "Your wardrobe is complete! Select any accessory to put it on your pet." : "Finish a problem to earn a new accessory. Select one to put it on your pet."); color: "#806C7C"; font.pixelSize: 13; wrapMode: Text.WordWrap }
  GridView {
    id: album
    objectName: "collectionGrid"; x: 390; y: 206; width: 704; height: 435; clip: true
    cellWidth: 176; cellHeight: 145
    model: root.tab === "pets" ? Catalog.pets : Catalog.accessories
    onModelChanged: positionViewAtBeginning()
    delegate: HotelButton {
      id: card
      required property var modelData
      readonly property bool isPet: root.tab === "pets"
      readonly property bool owned: (isPet ? root.collection.pets : root.collection.accessories).indexOf(modelData.id) !== -1
      objectName: (isPet ? "album-" : "wardrobe-") + modelData.id
      width: 164; height: 133
      selected: owned && (isPet ? root.selectedPet === modelData.id : root.collection.outfits[root.selectedPet] === modelData.id)
      enabled: owned && (isPet || root.petOwned)
      text: owned ? modelData.name : (isPet ? "Mystery friend" : modelData.name + " · locked")
      contentItem: Item {
        PetPortrait { x: 15; y: 2; width: parent.width - 30; height: 86; petId: card.isPet ? modelData.id : "peaches"; accessoryId: root.collection.outfits[modelData.id] || ""; visible: card.isPet && card.owned }
        AccessoryArt { anchors.horizontalCenter: parent.horizontalCenter; y: 5; width: 100; height: 78; accessory: card.isPet ? null : modelData; visible: !card.isPet; opacity: card.owned ? 1 : 0.27 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 7; text: "?"; color: "#C1A1B1"; font.pixelSize: 58; visible: card.isPet && !card.owned }
        Text { x: 0; y: 92; width: parent.width; text: card.text; color: card.selected ? "#FFFFFF" : card.owned ? "#654E5E" : "#937789"; font.pixelSize: 12; font.bold: card.owned; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
      }
      onClicked: {
        if (isPet) root.selectedPet = modelData.id
        else root.equipRequested(root.selectedPet, modelData.id)
      }
    }
    ScrollBar.vertical: ScrollBar {}
  }
}
