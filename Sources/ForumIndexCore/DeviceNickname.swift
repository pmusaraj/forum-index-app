import Foundation

/// Friendly installation metadata; the server's public ID remains the identity.
enum DeviceNickname {
    static let verbs = [
        "Ambling", "Bouncing", "Building", "Camping", "Clapping", "Climbing", "Cooking", "Dancing",
        "Diving", "Drawing", "Dreaming", "Drifting", "Exploring", "Floating", "Flying", "Gardening",
        "Gathering", "Gliding", "Hiking", "Hopping", "Humming", "Jogging", "Juggling", "Jumping",
        "Kayaking", "Knitting", "Laughing", "Leaping", "Listening", "Marching", "Napping", "Paddling",
        "Painting", "Playing", "Prancing", "Reading", "Roaming", "Rolling", "Rowing", "Running",
        "Sailing", "Singing", "Skating", "Skipping", "Smiling", "Soaring", "Spinning", "Splashing",
        "Springing", "Strolling", "Surfing", "Swimming", "Swinging", "Tinkering", "Traveling", "Trekking",
        "Trotting", "Tumbling", "Twirling", "Waking", "Walking", "Wandering", "Waving", "Whistling",
    ]

    static let nouns = [
        "Alpaca", "Badger", "Bear", "Beaver", "Bison", "Bobcat", "Buffalo", "Camel",
        "Capybara", "Caribou", "Cat", "Cheetah", "Chipmunk", "Cobra", "Crane", "Deer",
        "Dolphin", "Dove", "Dragon", "Duck", "Eagle", "Elephant", "Falcon", "Ferret",
        "Finch", "Fox", "Frog", "Gazelle", "Gecko", "Giraffe", "Goat", "Heron",
        "Horse", "Ibis", "Jaguar", "Koala", "Lemur", "Leopard", "Lion", "Llama",
        "Lynx", "Macaw", "Moose", "Narwhal", "Newt", "Otter", "Owl", "Panda",
        "Parrot", "Penguin", "Puffin", "Quail", "Rabbit", "Raccoon", "Raven", "Robin",
        "Seal", "Sparrow", "Swan", "Tiger", "Turtle", "Whale", "Wolf", "Wombat",
    ]

    static func generate() -> String {
        // 64 × 64 × 100 combinations. Duplicate display names are acceptable;
        // the server's public ID identifies each installation.
        let suffix = String(format: "%02d", Int.random(in: 0...99))
        return "\(verbs.randomElement()!)\(nouns.randomElement()!)\(suffix)"
    }
}
