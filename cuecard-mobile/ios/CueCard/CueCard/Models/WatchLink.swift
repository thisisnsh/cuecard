import Foundation

/// What the iPhone app and the watch app say to each other. Shared by both.
///
/// Each message, reply and application context carries one of these types as
/// JSON under one key, so the two sides agree on types rather than on
/// dictionary spellings.
enum WatchLink {
    /// A `WatchCommand`, from the watch.
    static let commandKey = "command"
    /// A `WatchPhoneState`, from the iPhone: in the application context, in a
    /// push, and in the reply to a command.
    static let stateKey = "state"
    /// Names what a transferred file holds.
    static let fileKindKey = "kind"
    /// A transferred file holding `[WatchDeck]`.
    static let decksFileKind = "decks"

    static func payload<Value: Encodable>(_ value: Value, key: String) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value) else { return [:] }
        return [key: data]
    }

    static func value<Value: Decodable>(_ type: Value.Type, key: String, in payload: [String: Any]) -> Value? {
        guard let data = payload[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// What both apps tell the user about the watch.
enum WatchTips {
    /// A watch goes back to its clock soon after the wrist drops, and an app
    /// can't keep itself up. The user can.
    static let returnToClock = "To keep CueCard on screen through a talk, open the Watch app on your iPhone, go to General › Return to Clock, choose CueCard, and set it to return after 1 hour."
}

/// How the watch app shows cards, set in the iPhone's Settings.
struct WatchSettings: Codable, Equatable {
    var cardTextSize: WatchCardTextSize
    /// A tap on the wrist as the card changes, and on the teleprompter's buttons.
    var haptics: Bool

    static let `default` = WatchSettings(cardTextSize: .medium, haptics: true)
}

enum WatchCardTextSize: String, Codable, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    /// In points, on the watch.
    var pointSize: Double {
        switch self {
        case .small: return 16
        case .medium: return 19
        case .large: return 23
        }
    }
}

/// Something the watch asks the iPhone to do.
enum WatchCommand: Codable, Equatable {
    case togglePlayPause
    case skipBack
    /// Show this card of the deck open on the iPhone. A card number rather
    /// than next or back, so a move the watch made while out of reach lands
    /// in the same place when it gets through.
    case showCard(session: UUID, index: Int)
    /// Open one of the watch's decks on the iPhone, where the watch is in it.
    case openDeck(id: UUID, title: String, cards: [String], index: Int)
    /// Send the current state back.
    case refresh
}

/// The deck open in cards mode on the iPhone.
struct WatchCardsState: Codable, Equatable {
    /// This opening of the deck. A move made for an earlier one is dropped.
    var session: UUID
    /// The saved note the deck came from, when it came from one.
    var deckID: UUID?
    var title: String
    var cards: [String]
    /// Equal to the number of cards once every one has been put away.
    var index: Int
    /// When the deck was opened, which its timer runs from.
    var startedAt: Date?
    /// The timer set when it was opened, in seconds. Zero counts up.
    var timerDuration: Int?
}

/// Everything the watch shows of the iPhone.
struct WatchPhoneState: Codable, Equatable {
    /// Nil while no script is open in the teleprompter.
    var teleprompter: TeleprompterTimerState?
    /// Nil while no deck is open.
    var cards: WatchCardsState?
    var cueColor: CueColor
    var settings: WatchSettings
    /// The cards timer, in seconds, for a deck read on the watch alone.
    var cardsTimerDuration: Int?
    /// When the iPhone sent it. A push and an application context can arrive
    /// out of turn, and the older of the two is dropped.
    var sentAt: Date
}

/// A saved note sent to the watch, to be read there on its own.
struct WatchDeck: Codable, Identifiable, Equatable {
    /// The saved note's.
    var id: UUID
    var title: String
    var cards: [String]
}
