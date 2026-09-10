import QtQuick
import "PetCatalog.js" as Catalog

Image {
  id: root
  property string petId: "peaches"
  property string accessoryId: ""
  readonly property var guest: Catalog.pet(petId)
  readonly property var accessory: Catalog.accessory(accessoryId)
  readonly property var accessoryAnchor: accessory && accessory.slot === "neck" ? (guest.neck || [0.5, 0.57]) : (guest.head || [0.5, 0.17])
  source: guest.original ? "assets/pets.png" : "assets/pets-more.png"
  sourceClipRect: guest.original ? Qt.rect(guest.tile * 512 + 8, 0, 496, 1024)
    : Qt.rect(guest.portrait[0], guest.portrait[1], guest.portrait[2], guest.portrait[3])
  fillMode: Image.PreserveAspectFit
  smooth: true; mipmap: true
  Accessible.role: Accessible.Graphic
  Accessible.name: guest.name + " the " + guest.kind + (accessory ? ", wearing " + accessory.name : "")
  Item {
    width: root.paintedWidth; height: root.paintedHeight; anchors.centerIn: parent
    AccessoryArt {
      objectName: "wornAccessory"
      accessory: root.accessory
      visible: root.accessory !== null
      width: parent.width * (root.guest.original ? 0.59 : 0.36); height: width * 0.75
      x: parent.width * root.accessoryAnchor[0] - width / 2
      y: parent.height * root.accessoryAnchor[1] - height / 2
    }
  }
}
