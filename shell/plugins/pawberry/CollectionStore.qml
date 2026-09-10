import QtQuick
import QtCore
import "PetCatalog.js" as Catalog
import "PetCollection.js" as Collection

Item {
  id: root
  required property url location
  property var collection: Collection.empty()
  Settings { id: saved; location: root.location }
  Component.onCompleted: collection = Collection.restore(saved.value("collection", ""), Catalog.petIds, Catalog.accessoryIds)
  function save(value) {
    collection = Collection.restore(value, Catalog.petIds, Catalog.accessoryIds)
    saved.setValue("collection", JSON.stringify(collection))
    // Flush each earned reward and outfit immediately, including on early quit.
    saved.sync()
  }
}
