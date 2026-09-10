// Stable IDs keep saved friends and outfits intact when the catalogue grows.
var pets = [
  {id: "peaches", name: "Peaches", kind: "Kitten", tile: 0, original: true},
  {id: "biscuit", name: "Biscuit", kind: "Puppy", tile: 1, original: true},
  {id: "bluebell", name: "Bluebell", kind: "Bunny", tile: 2, original: true},
  {id: "mochi", name: "Mochi", kind: "Hamster", tile: 0, portrait: [43, 60, 191, 235], head: [0.5, 0.14], neck: [0.5, 0.58]},
  {id: "poppy", name: "Poppy", kind: "Guinea pig", tile: 1, portrait: [270, 67, 213, 228], head: [0.5, 0.14], neck: [0.5, 0.62]},
  {id: "clover", name: "Clover", kind: "Chinchilla", tile: 2, portrait: [503, 33, 251, 262], head: [0.5, 0.22], neck: [0.5, 0.65]},
  {id: "hazel", name: "Hazel", kind: "Hedgehog", tile: 3, portrait: [762, 74, 218, 221], head: [0.5, 0.17], neck: [0.5, 0.66]},
  {id: "noodle", name: "Noodle", kind: "Ferret", tile: 4, portrait: [1029, 45, 195, 260], head: [0.5, 0.13], neck: [0.5, 0.46]},
  {id: "maple", name: "Maple", kind: "Red panda", tile: 5, portrait: [32, 333, 252, 273], head: [0.4, 0.16], neck: [0.41, 0.54]},
  {id: "pip", name: "Pip", kind: "Fox", tile: 6, portrait: [297, 313, 223, 291], head: [0.43, 0.2], neck: [0.45, 0.56]},
  {id: "olive", name: "Olive", kind: "Otter", tile: 7, portrait: [547, 337, 197, 266], head: [0.47, 0.12], neck: [0.48, 0.48]},
  {id: "pebble", name: "Pebble", kind: "Seal pup", tile: 8, portrait: [745, 379, 265, 223], head: [0.47, 0.18], neck: [0.5, 0.62]},
  {id: "sprout", name: "Sprout", kind: "Turtle", tile: 9, portrait: [1019, 395, 213, 203], head: [0.42, 0.17], neck: [0.45, 0.56]},
  {id: "mango", name: "Mango", kind: "Parrot", tile: 10, portrait: [44, 639, 181, 256], head: [0.53, 0.1], neck: [0.5, 0.48]},
  {id: "sunny", name: "Sunny", kind: "Cockatiel", tile: 11, portrait: [277, 606, 192, 296], head: [0.54, 0.35], neck: [0.5, 0.64]},
  {id: "waffles", name: "Waffles", kind: "Duckling", tile: 12, portrait: [540, 647, 171, 251], head: [0.5, 0.15], neck: [0.5, 0.54]},
  {id: "kiwi", name: "Kiwi", kind: "Penguin", tile: 13, portrait: [753, 644, 227, 254], head: [0.5, 0.13], neck: [0.5, 0.54]},
  {id: "pudding", name: "Pudding", kind: "Capybara", tile: 14, portrait: [1015, 632, 211, 277], head: [0.5, 0.12], neck: [0.5, 0.54]},
  {id: "tofu", name: "Tofu", kind: "Alpaca", tile: 15, portrait: [51, 896, 169, 323], head: [0.5, 0.19], neck: [0.5, 0.4]},
  {id: "truffle", name: "Truffle", kind: "Piglet", tile: 16, portrait: [283, 975, 212, 237], head: [0.5, 0.2], neck: [0.5, 0.61]},
  {id: "dottie", name: "Dottie", kind: "Fawn", tile: 17, portrait: [531, 911, 211, 309], head: [0.5, 0.22], neck: [0.48, 0.5]},
  {id: "juniper", name: "Juniper", kind: "Raccoon", tile: 18, portrait: [757, 954, 235, 259], head: [0.39, 0.19], neck: [0.4, 0.57]},
  {id: "bubbles", name: "Bubbles", kind: "Axolotl", tile: 19, portrait: [999, 963, 246, 255], head: [0.5, 0.19], neck: [0.5, 0.57]}
]
var accessories = [
  {id: "berry-bow", name: "Berry bow", shape: "bow", color: "#D9759A", slot: "head"},
  {id: "sky-bow", name: "Sky bow", shape: "bow", color: "#7DAECF", slot: "head"},
  {id: "mint-bow", name: "Mint bow", shape: "bow", color: "#79B69B", slot: "head"},
  {id: "sun-hat", name: "Sun hat", shape: "hat", color: "#E8C67E", slot: "head"},
  {id: "rose-hat", name: "Rose hat", shape: "hat", color: "#D991AD", slot: "head"},
  {id: "lavender-hat", name: "Lavender hat", shape: "hat", color: "#A59BCB", slot: "head"},
  {id: "gold-crown", name: "Golden crown", shape: "crown", color: "#E8B957", slot: "head"},
  {id: "moon-crown", name: "Moon crown", shape: "crown", color: "#ADA7D5", slot: "head"},
  {id: "daisy", name: "Daisy clip", shape: "flower", color: "#FFF5D8", slot: "head"},
  {id: "sunflower", name: "Sunflower clip", shape: "flower", color: "#F0C766", slot: "head"},
  {id: "pink-flower", name: "Blossom clip", shape: "flower", color: "#E7A2BA", slot: "head"},
  {id: "star-pin", name: "Star pin", shape: "star", color: "#E8B957", slot: "neck"},
  {id: "rose-star", name: "Rose star", shape: "star", color: "#D9759A", slot: "neck"},
  {id: "sky-star", name: "Sky star", shape: "star", color: "#7DAECF", slot: "neck"},
  {id: "coral-scarf", name: "Coral scarf", shape: "scarf", color: "#D88C86", slot: "neck"},
  {id: "mint-scarf", name: "Mint scarf", shape: "scarf", color: "#79B69B", slot: "neck"},
  {id: "lilac-scarf", name: "Lilac scarf", shape: "scarf", color: "#A59BCB", slot: "neck"},
  {id: "berry-bow-tie", name: "Berry bow tie", shape: "bow", color: "#D9759A", slot: "neck"},
  {id: "blue-bow-tie", name: "Blue bow tie", shape: "bow", color: "#7DAECF", slot: "neck"},
  {id: "gold-bow-tie", name: "Golden bow tie", shape: "bow", color: "#E8B957", slot: "neck"}
]
var petIds = pets.map(function(pet) { return pet.id })
var accessoryIds = accessories.map(function(accessory) { return accessory.id })
function pet(id) { return pets.filter(function(item) { return item.id === id })[0] || pets[0] }
function accessory(id) { return accessories.filter(function(item) { return item.id === id })[0] || null }
if (typeof module !== "undefined") module.exports = {pets: pets, accessories: accessories, petIds: petIds, accessoryIds: accessoryIds, pet: pet, accessory: accessory}
