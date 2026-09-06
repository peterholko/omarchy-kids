// Curated, offline English practice. The UI and engine do not own lesson text.
var LESSONS = [
  {id: "home", name: "Home row", detail: "Get comfortable with A S D F · J K L ;", tip: "Rest your index fingers on F and J. Let your other fingers find their neighbours.",
    prompts: ["ask", "dad", "fall", "salad", "flask", "adds", "all", "lad", "sad", "lass", "a dad", "a flask", "dad asks", "all fall", "ask dad", "a salad", "dad adds", "a lad", "fall; ask", "salad; flask"]},
  {id: "words", name: "Word trails", detail: "Everyday words, from easy to adventurous", tip: "Look at the word, then the screen. Accuracy comes first; speed will follow.",
    prompts: ["cloud", "letter", "rabbit", "friend", "garden", "cozy", "planet", "velvet", "sunshine", "whiskers", "pocket", "pencil", "rainbow", "feather", "explore", "cinnamon", "galaxy", "puzzle", "blanket", "lantern", "sparkle", "butterfly", "curious", "adventure", "brave", "pebble", "jellyfish", "notebook", "kindness", "moonlight", "starlight", "postcard", "treasure", "otter", "secret", "mountain", "waffle", "invent", "story", "journey", "dream", "whisper", "breeze", "squirrel", "science", "library", "creative", "comet", "honey", "marshmallow"]},
  {id: "stories", name: "Story mail", detail: "Short messages with capitals and punctuation", tip: "Use Shift for capitals. Spaces and punctuation are part of the message too.",
    prompts: ["Your next adventure starts here.", "The fox packed a tiny picnic.", "Meet me by the moonlit mailbox.", "You make ordinary days brighter!", "A little kindness goes a long way.", "The rabbit found a secret garden.", "Let's send a postcard to the stars.", "I saved the last waffle for you.", "Our kitten dreams of distant planets.", "Curiosity is a kind of superpower.", "The clouds look like sleepy sheep.", "Small steps can lead to big ideas.", "Don't forget your lucky pencil!", "We found a rainbow after the rain.", "What will you discover today?", "Bring your notebook, and an umbrella.", "There's a tiny library in the tree.", "The best stories begin with a friend.", "I think your idea is wonderful.", "Today is a good day to try again.", "Can an otter learn to fly a kite?", "Please deliver this hug by sunset.", "Follow the trail of silver feathers.", "You belong in this big, bright world."]}
]
function get(id) { return LESSONS.filter(function(lesson) { return lesson.id === id })[0] || LESSONS[1] }
function names() { return LESSONS.map(function(lesson) { return {id: lesson.id, name: lesson.name, detail: lesson.detail} }) }
function keyHint(character) {
  if (character === " ") return "Space"
  if (!character) return "Ready"
  if (/[A-Z]/.test(character)) return "Shift + " + character
  if (character === "!") return "!"
  if (character === "?") return "?"
  return character.toUpperCase()
}
if (typeof module !== "undefined") module.exports = {LESSONS: LESSONS, get: get, names: names, keyHint: keyHint}
