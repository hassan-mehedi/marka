import Foundation
import CodeEditLanguages

// Candidates for the inline completion popup: emoji after ":" and fence
// languages after three backticks.
enum Completions {
    struct Emoji: Equatable {
        let name: String
        let character: String
    }

    static let emoji: [Emoji] = [
        ("smile", "😄"), ("grinning", "😀"), ("laughing", "😆"), ("joy", "😂"), ("rofl", "🤣"), ("wink", "😉"),
        ("blush", "😊"), ("heart_eyes", "😍"), ("kissing_heart", "😘"), ("thinking", "🤔"), ("neutral_face", "😐"),
        ("expressionless", "😑"), ("unamused", "😒"), ("sweat_smile", "😅"), ("sob", "😭"), ("cry", "😢"),
        ("angry", "😠"), ("rage", "😡"), ("scream", "😱"), ("fearful", "😨"), ("sleeping", "😴"), ("mask", "😷"),
        ("sunglasses", "😎"), ("nerd_face", "🤓"), ("star_struck", "🤩"), ("partying_face", "🥳"), ("hugs", "🤗"),
        ("shushing_face", "🤫"), ("zany_face", "🤪"), ("face_with_monocle", "🧐"), ("upside_down_face", "🙃"),
        ("thumbsup", "👍"), ("+1", "👍"), ("thumbsdown", "👎"), ("-1", "👎"), ("clap", "👏"), ("wave", "👋"), ("ok_hand", "👌"),
        ("pray", "🙏"), ("muscle", "💪"), ("point_right", "👉"), ("point_left", "👈"), ("point_up", "☝️"), ("point_down", "👇"),
        ("raised_hands", "🙌"), ("handshake", "🤝"), ("v", "✌️"), ("crossed_fingers", "🤞"), ("writing_hand", "✍️"), ("eyes", "👀"),
        ("heart", "❤️"), ("broken_heart", "💔"), ("orange_heart", "🧡"), ("yellow_heart", "💛"), ("green_heart", "💚"),
        ("blue_heart", "💙"), ("purple_heart", "💜"), ("black_heart", "🖤"), ("sparkling_heart", "💖"), ("two_hearts", "💕"),
        ("fire", "🔥"), ("sparkles", "✨"), ("star", "⭐"), ("star2", "🌟"), ("zap", "⚡"), ("boom", "💥"), ("tada", "🎉"),
        ("confetti_ball", "🎊"), ("balloon", "🎈"), ("gift", "🎁"), ("trophy", "🏆"), ("medal", "🏅"), ("crown", "👑"),
        ("rocket", "🚀"), ("airplane", "✈️"), ("car", "🚗"), ("bike", "🚲"), ("ship", "🚢"), ("train", "🚆"), ("bus", "🚌"),
        ("check", "✔️"), ("heavy_check_mark", "✔️"), ("white_check_mark", "✅"), ("x", "❌"), ("heavy_multiplication_x", "✖️"),
        ("ballot_box_with_check", "☑️"), ("warning", "⚠️"), ("no_entry", "⛔"), ("no_entry_sign", "🚫"), ("exclamation", "❗"),
        ("question", "❓"), ("bangbang", "‼️"), ("interrobang", "⁉️"), ("100", "💯"), ("bulb", "💡"), ("memo", "📝"),
        ("pencil2", "✏️"), ("pencil", "📝"), ("book", "📖"), ("books", "📚"), ("bookmark", "🔖"), ("clipboard", "📋"),
        ("pushpin", "📌"), ("paperclip", "📎"), ("link", "🔗"), ("lock", "🔒"), ("unlock", "🔓"), ("key", "🔑"),
        ("mag", "🔍"), ("bell", "🔔"), ("hourglass", "⌛"), ("alarm_clock", "⏰"), ("calendar", "📅"), ("date", "📅"),
        ("chart_with_upwards_trend", "📈"), ("chart_with_downwards_trend", "📉"), ("bar_chart", "📊"), ("moneybag", "💰"),
        ("dollar", "💵"), ("credit_card", "💳"), ("email", "📧"), ("envelope", "✉️"), ("inbox_tray", "📥"), ("outbox_tray", "📤"),
        ("package", "📦"), ("file_folder", "📁"), ("open_file_folder", "📂"), ("page_facing_up", "📄"), ("newspaper", "📰"),
        ("computer", "💻"), ("desktop_computer", "🖥️"), ("keyboard", "⌨️"), ("iphone", "📱"), ("phone", "☎️"), ("camera", "📷"),
        ("tv", "📺"), ("headphones", "🎧"), ("microphone", "🎤"), ("musical_note", "🎵"), ("video_game", "🎮"), ("dart", "🎯"),
        ("wrench", "🔧"), ("hammer", "🔨"), ("hammer_and_wrench", "🛠️"), ("gear", "⚙️"), ("nut_and_bolt", "🔩"), ("toolbox", "🧰"),
        ("bug", "🐛"), ("beetle", "🪲"), ("ant", "🐜"), ("bee", "🐝"), ("snail", "🐌"), ("butterfly", "🦋"), ("spider", "🕷️"),
        ("dog", "🐶"), ("cat", "🐱"), ("mouse", "🐭"), ("rabbit", "🐰"), ("fox_face", "🦊"), ("bear", "🐻"), ("panda_face", "🐼"),
        ("koala", "🐨"), ("tiger", "🐯"), ("lion", "🦁"), ("cow", "🐮"), ("pig", "🐷"), ("frog", "🐸"), ("monkey_face", "🐵"),
        ("chicken", "🐔"), ("penguin", "🐧"), ("bird", "🐦"), ("owl", "🦉"), ("unicorn", "🦄"), ("dragon", "🐉"), ("whale", "🐳"),
        ("dolphin", "🐬"), ("fish", "🐟"), ("octopus", "🐙"), ("turtle", "🐢"), ("snake", "🐍"), ("crocodile", "🐊"), ("t-rex", "🦖"),
        ("apple", "🍎"), ("green_apple", "🍏"), ("banana", "🍌"), ("lemon", "🍋"), ("grapes", "🍇"), ("strawberry", "🍓"),
        ("cherries", "🍒"), ("peach", "🍑"), ("pineapple", "🍍"), ("watermelon", "🍉"), ("avocado", "🥑"), ("carrot", "🥕"),
        ("corn", "🌽"), ("hot_pepper", "🌶️"), ("bread", "🍞"), ("cheese", "🧀"), ("egg", "🥚"), ("hamburger", "🍔"), ("pizza", "🍕"),
        ("taco", "🌮"), ("sushi", "🍣"), ("ramen", "🍜"), ("cake", "🍰"), ("birthday", "🎂"), ("cookie", "🍪"), ("doughnut", "🍩"),
        ("icecream", "🍦"), ("coffee", "☕"), ("tea", "🍵"), ("beer", "🍺"), ("beers", "🍻"), ("wine_glass", "🍷"), ("champagne", "🍾"),
        ("sunny", "☀️"), ("cloud", "☁️"), ("umbrella", "☔"), ("snowflake", "❄️"), ("rainbow", "🌈"), ("ocean", "🌊"), ("earth_africa", "🌍"),
        ("earth_americas", "🌎"), ("earth_asia", "🌏"), ("globe_with_meridians", "🌐"), ("moon", "🌙"), ("full_moon", "🌕"), ("seedling", "🌱"),
        ("evergreen_tree", "🌲"), ("deciduous_tree", "🌳"), ("palm_tree", "🌴"), ("cactus", "🌵"), ("herb", "🌿"), ("four_leaf_clover", "🍀"),
        ("rose", "🌹"), ("tulip", "🌷"), ("sunflower", "🌻"), ("cherry_blossom", "🌸"), ("bouquet", "💐"), ("mushroom", "🍄"),
        ("house", "🏠"), ("office", "🏢"), ("hospital", "🏥"), ("school", "🏫"), ("construction", "🚧"), ("world_map", "🗺️"),
        ("arrow_right", "➡️"), ("arrow_left", "⬅️"), ("arrow_up", "⬆️"), ("arrow_down", "⬇️"), ("arrows_counterclockwise", "🔄"),
        ("recycle", "♻️"), ("infinity", "♾️"), ("heavy_plus_sign", "➕"), ("heavy_minus_sign", "➖"), ("heavy_division_sign", "➗"),
        ("copyright", "©️"), ("registered", "®️"), ("tm", "™️"), ("hash", "#️⃣"), ("zero", "0️⃣"), ("one", "1️⃣"), ("two", "2️⃣"), ("three", "3️⃣"),
        ("speech_balloon", "💬"), ("thought_balloon", "💭"), ("loudspeaker", "📢"), ("mega", "📣"), ("dizzy", "💫"), ("sweat_drops", "💦"),
        ("zzz", "💤"), ("poop", "💩"), ("skull", "💀"), ("ghost", "👻"), ("alien", "👽"), ("robot", "🤖"), ("jack_o_lantern", "🎃"),
        ("christmas_tree", "🎄"), ("santa", "🎅"), ("snowman", "⛄"), ("soccer", "⚽"), ("basketball", "🏀"), ("football", "🏈"),
        ("tennis", "🎾"), ("running", "🏃"), ("swimmer", "🏊"), ("bicyclist", "🚴"), ("mountain", "⛰️"), ("volcano", "🌋"), ("camping", "🏕️"),
        ("tent", "⛺"), ("beach_umbrella", "🏖️"), ("desert_island", "🏝️"), ("sunrise", "🌅"), ("city_sunset", "🌇"), ("night_with_stars", "🌃"),
        ("wheelchair", "♿"), ("mens", "🚹"), ("womens", "🚺"), ("baby", "👶"), ("family", "👪"), ("couple", "👫"), ("dancer", "💃"),
        ("art", "🎨"), ("clapper", "🎬"), ("ticket", "🎫"), ("guitar", "🎸"), ("violin", "🎻"), ("trumpet", "🎺"), ("drum", "🥁"),
        ("shield", "🛡️"), ("bomb", "💣"), ("gun", "🔫"), ("dagger", "🗡️"), ("crystal_ball", "🔮"), ("gem", "💎"), ("ring", "💍"),
        ("speech_left", "🗨️"), ("black_nib", "✒️"), ("fountain_pen", "🖋️"), ("crayon", "🖍️"), ("scissors", "✂️"), ("triangular_ruler", "📐"),
        ("straight_ruler", "📏"), ("abacus", "🧮"), ("test_tube", "🧪"), ("microscope", "🔬"), ("telescope", "🔭"), ("satellite", "📡"),
        ("dna", "🧬"), ("pill", "💊"), ("syringe", "💉"), ("stethoscope", "🩺"), ("brain", "🧠"), ("tooth", "🦷"), ("bone", "🦴"),
    ].map { Emoji(name: $0.0, character: $0.1) }

    static let languages: [String] = {
        var names = Set<String>()
        for language in CodeLanguage.allLanguages {
            names.insert(language.tsName.lowercased())
            for ext in language.extensions where ext.count <= 6 { names.insert(ext.lowercased()) }
        }
        names.formUnion(["mermaid", "text", "shell", "console", "yaml", "json", "toml", "markdown", "md"])
        return names.sorted()
    }()

    static func emoji(matching partial: String) -> [String] {
        let query = partial.lowercased()
        guard !query.isEmpty else { return [] }
        return emoji
            .filter { $0.name.hasPrefix(query) || $0.name.contains(query) }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.hasPrefix(query)
                let rhsPrefix = rhs.name.hasPrefix(query)
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.name < rhs.name
            }
            .prefix(12)
            .map { $0.character + " :" + $0.name + ":" }
    }

    static func languages(matching partial: String) -> [String] {
        let query = partial.lowercased()
        return languages.filter { query.isEmpty || $0.hasPrefix(query) }.prefix(12).map { $0 }
    }

    // Splits a completion label back into the text that goes into the document.
    static func insertion(for completion: String) -> String {
        guard let space = completion.firstIndex(of: " "), completion.hasSuffix(":") else { return completion }
        return String(completion[..<space])
    }
}
