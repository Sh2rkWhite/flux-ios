import Foundation
import SwiftUI

// MARK: - Date/time/size formatting (Russian-first, mirrors format.dart)

private let monthsRuGenitive = [
    "января", "февраля", "марта", "апреля", "мая", "июня",
    "июля", "августа", "сентября", "октября", "ноября", "декабря",
]

let monthsRuShort = [
    "янв", "фев", "мар", "апр", "май", "июн",
    "июл", "авг", "сен", "окт", "ноя", "дек",
]

private func dateFromMs(_ ms: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
}

private func sameDay(_ a: Date, _ b: Date) -> Bool {
    Calendar.current.isDate(a, inSameDayAs: b)
}

/// `14:32`
func formatTime(_ ms: Int) -> String {
    let dt = dateFromMs(ms)
    let comps = Calendar.current.dateComponents([.hour, .minute], from: dt)
    return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
}

/// Chat list timestamp: time today, "Вчера", or a short date.
func formatChatTime(_ ms: Int, ru: Bool = true) -> String {
    let dt = dateFromMs(ms)
    let now = Date()
    if sameDay(dt, now) { return formatTime(ms) }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    if sameDay(dt, yesterday) { return ru ? "Вчера" : "Yesterday" }
    let comps = Calendar.current.dateComponents([.day, .month, .year], from: dt)
    if comps.year == Calendar.current.component(.year, from: now) {
        return ru
            ? "\(comps.day ?? 0) \(monthsRuGenitive[(comps.month ?? 1) - 1])"
            : String(format: "%02d.%02d", comps.day ?? 0, comps.month ?? 0)
    }
    return String(format: "%02d.%02d.%d", comps.day ?? 0, comps.month ?? 0, comps.year ?? 0)
}

/// Day divider inside a chat.
func formatDayDivider(_ ms: Int, ru: Bool = true) -> String {
    let dt = dateFromMs(ms)
    let now = Date()
    if sameDay(dt, now) { return ru ? "Сегодня" : "Today" }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    if sameDay(dt, yesterday) { return ru ? "Вчера" : "Yesterday" }
    let comps = Calendar.current.dateComponents([.day, .month, .year], from: dt)
    let yearPart = comps.year == Calendar.current.component(.year, from: now) ? "" : " \(comps.year ?? 0)"
    return "\(comps.day ?? 0) \(monthsRuGenitive[(comps.month ?? 1) - 1])\(yearPart)"
}

/// Call history timestamp.
func formatCallTime(_ ms: Int, ru: Bool = true) -> String {
    let dt = dateFromMs(ms)
    let now = Date()
    if sameDay(dt, now) { return formatTime(ms) }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
    if sameDay(dt, yesterday) { return "Вчера, \(formatTime(ms))" }
    let comps = Calendar.current.dateComponents([.day, .month], from: dt)
    return "\(comps.day ?? 0) \(monthsRuGenitive[(comps.month ?? 1) - 1]), \(formatTime(ms))"
}

/// `0:07`, `1:23`
func formatDurationMs(_ ms: Int) -> String {
    let total = Int((Double(ms) / 1000).rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// `1.2 МБ`
func formatFileSize(_ bytes: Int) -> String {
    if bytes < 1024 { return "\(bytes) Б" }
    if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) КБ" }
    if bytes < 1024 * 1024 * 1024 {
        return String(format: "%.1f МБ", Double(bytes) / (1024 * 1024))
    }
    return String(format: "%.1f ГБ", Double(bytes) / (1024 * 1024 * 1024))
}

/// Initials for generated avatars: "Алиса Соколова" -> "АС".
func initialsOf(_ name: String) -> String {
    let parts = name.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ")
        .filter { !$0.isEmpty }
    guard !parts.isEmpty else { return "F" }
    let first = String(parts[0].prefix(1))
    if parts.count == 1 { return first.uppercased() }
    let second = String(parts[1].prefix(1))
    return (first + second).uppercased()
}

/// Russian pluralization: 1 день / 2 дня / 5 дней.
func pluralRu(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let absN = abs(n) % 100
    let n1 = absN % 10
    if absN > 10 && absN < 20 { return many }
    if n1 > 1 && n1 < 5 { return few }
    if n1 == 1 { return one }
    return many
}

/// Full days elapsed since the given epoch-ms timestamp.
func daysSince(_ ms: Int) -> Int {
    max(0, Int(Date().timeIntervalSince(dateFromMs(ms)) / 86_400))
}

/// `На Flux: 183 дня` — days computed from the registration date.
func daysInFluxString(registeredAtMs: Int?) -> String? {
    guard let registeredAtMs, registeredAtMs > 0 else { return nil }
    let days = daysSince(registeredAtMs)
    return "На Flux: \(days) \(pluralRu(days, "день", "дня", "дней"))"
}

/// Parses a `dd.mm.yyyy` birthday string.
func parseBirthday(_ raw: String?) -> DateComponents? {
    guard let raw else { return nil }
    let parts = raw.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return DateComponents(year: parts[2], month: parts[1], day: parts[0])
}

/// `🎂 12 марта 2012 · 14 лет` — age computed from the birth date.
func birthdayDisplayString(_ raw: String?, showAge: Bool) -> String? {
    guard let comps = parseBirthday(raw) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC") ?? .current
    guard let date = cal.date(from: comps) else { return nil }
    let outComps = cal.dateComponents([.day, .month, .year], from: date)
    var text = "🎂 \(outComps.day ?? 0) \(monthsRuGenitive[(outComps.month ?? 1) - 1]) \(outComps.year ?? 0)"
    if showAge {
        let age = cal.dateComponents([.year], from: date, to: Date()).year ?? 0
        text += " · \(age) \(pluralRu(age, "год", "года", "лет"))"
    }
    return text
}
