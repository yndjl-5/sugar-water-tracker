import SwiftUI
import Observation
import UIKit
import UserNotifications

private enum WaterNotificationArtwork {
    static func attachment() -> UNNotificationAttachment? {
        let size = CGSize(width: 600, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let canvas = CGRect(origin: .zero, size: size)
            UIColor(red: 0.08, green: 0.55, blue: 0.78, alpha: 1).setFill()
            context.cgContext.fill(canvas)

            let glass = CGRect(x: 220, y: 52, width: 160, height: 256)
            let glassPath = UIBezierPath(roundedRect: glass, cornerRadius: 28)
            UIColor.white.withAlphaComponent(0.22).setFill()
            glassPath.fill()

            let water = CGRect(x: 232, y: 164, width: 136, height: 132)
            let waterPath = UIBezierPath(
                roundedRect: water,
                byRoundingCorners: [.bottomLeft, .bottomRight],
                cornerRadii: CGSize(width: 20, height: 20)
            )
            UIColor(red: 0.33, green: 0.82, blue: 1, alpha: 1).setFill()
            waterPath.fill()

            UIColor.white.withAlphaComponent(0.9).setStroke()
            glassPath.lineWidth = 10
            glassPath.stroke()

            UIColor.white.withAlphaComponent(0.7).setFill()
            UIBezierPath(ovalIn: CGRect(x: 260, y: 98, width: 18, height: 18)).fill()
            UIBezierPath(ovalIn: CGRect(x: 298, y: 76, width: 12, height: 12)).fill()
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("water-reminder-(UUID().uuidString).png")
        guard let data = image.pngData() else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "water-cup", url: url)
        } catch {
            return nil
        }
    }
}

struct DrinkEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let sugarGrams: Double
    let price: Double
    let date: Date
    let source: String

    init(id: UUID = UUID(), name: String, sugarGrams: Double, price: Double, date: Date, source: String = "手動輸入") {
        self.id = id
        self.name = name
        self.sugarGrams = sugarGrams
        self.price = price
        self.date = date
        self.source = source
    }
}

struct SavedDrink: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let sugarGrams: Double
    let price: Double

    init(id: UUID = UUID(), name: String, sugarGrams: Double, price: Double) {
        self.id = id
        self.name = name
        self.sugarGrams = sugarGrams
        self.price = price
    }
}

struct DrinkTopping: Identifiable {
    let name: String
    let sugarGrams: Double

    var id: String { name }

    static let common = [
        DrinkTopping(name: "珍珠", sugarGrams: 20),
        DrinkTopping(name: "椰果", sugarGrams: 14),
        DrinkTopping(name: "布丁", sugarGrams: 12),
        DrinkTopping(name: "仙草", sugarGrams: 4),
        DrinkTopping(name: "愛玉", sugarGrams: 2)
    ]
}

struct TaiwanDrinkTemplate: Identifiable {
    let name: String
    let sugarPer100ML: Double
    let note: String

    var id: String { name }

    static let common = [
        TaiwanDrinkTemplate(name: "無糖茶", sugarPer100ML: 0, note: "無糖模板"),
        TaiwanDrinkTemplate(name: "微糖茶", sugarPer100ML: 2.5, note: "甜度估算，請以店家標示為準"),
        TaiwanDrinkTemplate(name: "半糖茶", sugarPer100ML: 5, note: "甜度估算，請以店家標示為準"),
        TaiwanDrinkTemplate(name: "全糖茶", sugarPer100ML: 10, note: "甜度估算，請以店家標示為準")
    ]
}

@MainActor
@Observable
final class SugarTracker {
    private let storageKey = "SugarTracker.entries"
    private let favoritesKey = "SugarTracker.favorites"

    var entries: [DrinkEntry] = [] {
        didSet { saveEntries() }
    }
    var favorites: [SavedDrink] = [] {
        didSet { saveFavorites() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let savedEntries = try? JSONDecoder().decode([DrinkEntry].self, from: data) {
            entries = savedEntries
        }
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let savedFavorites = try? JSONDecoder().decode([SavedDrink].self, from: data) {
            favorites = savedFavorites
        }
    }

    func add(_ entry: DrinkEntry) {
        entries.append(entry)
        saveFavorite(name: entry.name, sugarGrams: entry.sugarGrams, price: entry.price)
    }

    func delete(_ entry: DrinkEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    func update(_ entry: DrinkEntry, name: String, sugarGrams: Double, price: Double, date: Date, source: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = DrinkEntry(
            id: entry.id,
            name: name,
            sugarGrams: sugarGrams,
            price: price,
            date: date,
            source: source
        )
        saveFavorite(name: name, sugarGrams: sugarGrams, price: price)
    }

    func entries(on date: Date) -> [DrinkEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    func sugar(on date: Date) -> Double {
        entries(on: date).reduce(0) { $0 + $1.sugarGrams }
    }

    func cost(on date: Date) -> Double {
        entries(on: date).reduce(0) { $0 + $1.price }
    }

    func saveFavorite(name: String, sugarGrams: Double, price: Double) {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return }

        favorites.removeAll {
            $0.name.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        favorites.insert(
            SavedDrink(name: normalizedName, sugarGrams: sugarGrams, price: price),
            at: 0
        )
    }

    func matchingFavorites(for query: String) -> [SavedDrink] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return favorites }
        return favorites.filter {
            $0.name.localizedCaseInsensitiveContains(normalizedQuery)
                || normalizedQuery.localizedCaseInsensitiveContains($0.name)
        }
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: favoritesKey)
    }
}


@MainActor
@Observable
final class WaterTracker {
    private let amountKey = "WaterTracker.todayAmount"
    private let dateKey = "WaterTracker.loggedDate"
    private let reminderPrefix = "WaterTracker.reminder."
    private let goal = 2_000

    var todayAmount: Int {
        didSet { UserDefaults.standard.set(todayAmount, forKey: amountKey) }
    }

    init() {
        let storedDate = UserDefaults.standard.object(forKey: dateKey) as? Date
        if let storedDate, Calendar.current.isDateInToday(storedDate) {
            todayAmount = UserDefaults.standard.integer(forKey: amountKey)
        } else {
            todayAmount = 0
            UserDefaults.standard.set(Date(), forKey: dateKey)
        }
    }

    var remainingAmount: Int {
        max(0, goal - todayAmount)
    }

    private func reminderContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "喝水時間 💧")
        content.body = String(localized: "喝一杯水吧！今天的目標是 2,000 cc，現在就補充 250 cc。")
        content.sound = .default

        if let attachment = WaterNotificationArtwork.attachment() {
            content.attachments = [attachment]
        }

        return content
    }

    func addWater(_ amount: Int) {
        resetIfNeeded()
        todayAmount += amount
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }

    func scheduleReminders(every intervalHours: Int) async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw WaterReminderError.permissionDenied }

        let identifiers = (6...22).map { reminderPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for hour in stride(from: 8, through: 20, by: intervalHours) {
            var components = DateComponents()
            components.hour = hour
            components.minute = 0

            let content = reminderContent()

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderPrefix + String(hour),
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    func scheduleTestReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else { throw WaterReminderError.permissionDenied }

        let identifier = reminderPrefix + "test"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = reminderContent()

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    private func resetIfNeeded() {
        guard let storedDate = UserDefaults.standard.object(forKey: dateKey) as? Date,
              !Calendar.current.isDateInToday(storedDate) else { return }
        todayAmount = 0
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}

enum WaterReminderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "通知權限尚未開啟，請到系統設定允許此 App 發送通知。"
    }
}

struct ContentView: View {
    @State private var tracker = SugarTracker()
    @State private var waterTracker = WaterTracker()
    @State private var showingAddDrink = false
    @State private var selectedMonth = Date()

    var body: some View {
        TabView {
            TodayView(tracker: tracker, showingAddDrink: $showingAddDrink)
                .tabItem { Label("今日", systemImage: "drop.fill") }

            MonthCalendarView(tracker: tracker, selectedMonth: $selectedMonth)
                .tabItem { Label("月曆", systemImage: "calendar") }

            RecordsView(tracker: tracker)
                .tabItem { Label("紀錄", systemImage: "list.bullet") }

            WaterView(tracker: waterTracker)
                .tabItem { Label("喝水", systemImage: "drop.circle.fill") }
        }
        .tint(.teal)
        .sheet(isPresented: $showingAddDrink) {
            AddDrinkView(tracker: tracker)
        }
    }
}

private struct TodayView: View {
    let tracker: SugarTracker
    @Binding var showingAddDrink: Bool
    @State private var editingEntry: DrinkEntry?

    private var todaySugar: Double { tracker.sugar(on: .now) }
    private var todayCost: Double { tracker.cost(on: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sugarSummary
                    healthMessage
                    dailyRecords
                }
                .padding()
            }
            .navigationTitle("控糖日記")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddDrink = true
                    } label: {
                        Label("新增飲料", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingEntry) { entry in
            AddDrinkView(tracker: tracker, editingEntry: entry)
        }
    }

    private var sugarSummary: some View {
        VStack(spacing: 12) {
            Text("今天已攝入")
                .font(.headline)
            Text("\(todaySugar, format: .number.precision(.fractionLength(0...1))) / 50 g")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)

            ProgressView(value: min(todaySugar, 50), total: 50)
                .tint(statusColor)
                .scaleEffect(x: 1, y: 2, anchor: .center)

            HStack {
                Label("剩餘 \(max(0, 50 - todaySugar), format: .number.precision(.fractionLength(0...1))) g", systemImage: "target")
                Spacer()
                Label("今天花了 NT$\(todayCost, format: .number.precision(.fractionLength(0...0)))", systemImage: "wallet.bifold")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    private var healthMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text("給你的控糖提醒")
                    .font(.headline)
                Text("經常攝入過多添加糖，可能增加蛀牙、體重增加及代謝疾病的風險。慢慢以無糖飲品取代含糖飲料。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dailyRecords: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日飲料")
                .font(.title3.bold())

            if tracker.entries(on: .now).isEmpty {
                ContentUnavailableView("今天還沒有飲料紀錄", systemImage: "cup.and.saucer", description: Text("點右上角新增第一筆紀錄。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(tracker.entries(on: .now).sorted { $0.date > $1.date }) { entry in
                    TodayRecordRow(
                        entry: entry,
                        onEdit: { editingEntry = entry },
                        onDelete: { tracker.delete(entry) }
                    )
                }
            }
        }
    }

    private var statusColor: Color {
        todaySugar > 50 ? .red : (todaySugar == 0 ? .green : .yellow)
    }
}

private struct MonthCalendarView: View {
    let tracker: SugarTracker
    @Binding var selectedMonth: Date

    private let calendar = Calendar.current
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: selectedMonth) else { return [] }
        let offset = calendar.component(.weekday, from: interval.start) - calendar.firstWeekday
        let leadingSpaces = offset >= 0 ? offset : offset + 7
        return Array(repeating: nil, count: leadingSpaces) + dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthControls
                    weekdayHeader
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 10) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                            if let date {
                                CalendarDay(date: date, sugar: tracker.sugar(on: date), cost: tracker.cost(on: date))
                            } else {
                                Color.clear.frame(height: 88)
                            }
                        }
                    }
                    calendarLegend
                    monthTotal
                }
                .padding()
            }
            .navigationTitle("糖分月曆")
        }
    }

    private var monthControls: some View {
        HStack {
            Button {
                selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(selectedMonth, format: .dateTime.year().month(.wide))
                .font(.title3.bold())
            Spacer()
            Button {
                selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            } label: {
                Image(systemName: "chevron.right")
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortWeekdaySymbols
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calendarLegend: some View {
        HStack(spacing: 14) {
            Text("😃 0g").foregroundStyle(.green)
            Text("🤨 1–50g").foregroundStyle(.orange)
            Text("😡 超過 50g").foregroundStyle(.red)
        }
        .font(.caption)
    }

    private var monthTotal: some View {
        let monthEntries = tracker.entries.filter { calendar.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
        let sugar = monthEntries.reduce(0) { $0 + $1.sugarGrams }
        let cost = monthEntries.reduce(0) { $0 + $1.price }
        let recordedDays = Set(monthEntries.map { calendar.startOfDay(for: $0.date) }).count
        let overLimitDays = Set(monthEntries.map { calendar.startOfDay(for: $0.date) })
            .filter { tracker.sugar(on: $0) > 50 }
            .count

        return VStack(alignment: .leading, spacing: 14) {
            Text("本月 Summary")
                .font(.headline)

            HStack(spacing: 12) {
                MonthStat(title: "糖分總量", value: sugar.formatted(.number.precision(.fractionLength(0...1))) + " g", color: .teal)
                MonthStat(title: "飲料花費", value: "NT$" + cost.formatted(.number.precision(.fractionLength(0...0))), color: .orange)
            }

            HStack(spacing: 12) {
                MonthStat(title: "有紀錄天數", value: "\(recordedDays) 天", color: .blue)
                MonthStat(title: "超標天數", value: "\(overLimitDays) 天", color: overLimitDays == 0 ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WaterView: View {
    let tracker: WaterTracker

    @State private var reminderInterval = 1
    @State private var reminderMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("今天的喝水目標") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(tracker.todayAmount) / 2,000 cc")
                                .font(.title2.bold())
                            Spacer()
                            Text(tracker.remainingAmount == 0 ? "已達標 🎉" : "還差 \(tracker.remainingAmount) cc")
                                .foregroundStyle(tracker.remainingAmount == 0 ? .green : .secondary)
                        }
                        ProgressView(value: min(Double(tracker.todayAmount), 2_000), total: 2_000)
                            .tint(.blue)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        waterButton(amount: 250)
                        waterButton(amount: 500)
                    }
                }

                Section("白天喝水提醒") {
                    Stepper("每 \(reminderInterval) 小時提醒一次", value: $reminderInterval, in: 1...4)
                    Text("提醒時段為每天 08:00 到 20:00。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("通知範例：喝一杯水吧！今天的目標是 2,000 cc，現在就補充 250 cc。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("開啟／更新提醒") {
                        configureReminders()
                    }

                    Button("3 秒後測試通知") {
                        sendTestReminder()
                    }

                    if let reminderMessage {
                        Text(reminderMessage)
                            .font(.caption)
                            .foregroundStyle(reminderMessage.hasPrefix("已") ? .green : .red)
                    }
                }
            }
            .navigationTitle("喝水")
        }
    }

    private func waterButton(amount: Int) -> some View {
        Button("+\(amount) cc") {
            tracker.addWater(amount)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    private func configureReminders() {
        Task {
            do {
                try await tracker.scheduleReminders(every: reminderInterval)
                reminderMessage = "已設定白天每 \(reminderInterval) 小時提醒一次。"
            } catch {
                reminderMessage = error.localizedDescription
            }
        }
    }

    private func sendTestReminder() {
        Task {
            do {
                try await tracker.scheduleTestReminder()
                reminderMessage = "測試通知將在 3 秒後送出。請先回到主畫面查看。"
            } catch {
                reminderMessage = error.localizedDescription
            }
        }
    }
}

private struct MonthStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CalendarDay: View {
    let date: Date
    let sugar: Double
    let cost: Double

    var body: some View {
        VStack(spacing: 3) {
            Text(date, format: .dateTime.day())
                .font(.caption.bold())
            Text(emoji)
                .font(.title3)
            Text("\(sugar, format: .number.precision(.fractionLength(0...0)))g")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("NT$\(cost, format: .number.precision(.fractionLength(0...0)))")
                .font(.caption2.weight(.medium))
                .foregroundStyle(cost > 0 ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted))，糖分 \(sugar) 克，花費 \(cost) 元")
    }

    private var emoji: String {
        sugar == 0 ? "😃" : (sugar > 50 ? "😡" : "🤨")
    }

    private var color: Color {
        sugar == 0 ? .green : (sugar > 50 ? .red : .yellow)
    }
}

private struct RecordsView: View {
    let tracker: SugarTracker
    private let calendar = Calendar.current

    private var dates: [Date] {
        let uniqueDates = Set(tracker.entries.map { calendar.startOfDay(for: $0.date) })
        return uniqueDates.sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            List {
                if tracker.entries.isEmpty {
                    ContentUnavailableView("尚無紀錄", systemImage: "list.bullet.rectangle")
                } else {
                    ForEach(dates, id: \.self) { date in
                        Section {
                            ForEach(tracker.entries(on: date).sorted { $0.date > $1.date }) { entry in
                                DrinkRow(entry: entry, tracker: tracker)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            DateRecordHeader(
                                date: date,
                                sugar: tracker.sugar(on: date),
                                cost: tracker.cost(on: date)
                            )
                        }
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("所有紀錄")
        }
    }
}

private struct DateRecordHeader: View {
    let date: Date
    let sugar: Double
    let cost: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.year().month().day().weekday(.wide))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("糖分 \(sugar, format: .number.precision(.fractionLength(0...1))) g · NT$\(cost, format: .number.precision(.fractionLength(0...0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TodayRecordRow: View {
    let entry: DrinkEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(.teal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.headline)
                Text(entry.date, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(entry.sugarGrams, format: .number.precision(.fractionLength(0...1))) g")
                    .font(.headline)
                Text("NT$\(entry.price, format: .number.precision(.fractionLength(0...0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu {
                Button("更正紀錄", systemImage: "pencil", action: onEdit)
                Button("刪除紀錄", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .padding(.leading, 4)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct DrinkRow: View {
    let entry: DrinkEntry
    let tracker: SugarTracker

    var body: some View {
        HStack {
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(.teal)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.headline)
                Text(entry.date, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(entry.sugarGrams, format: .number.precision(.fractionLength(0...1))) g")
                    .font(.headline)
                Text("NT$\(entry.price, format: .number.precision(.fractionLength(0...0)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                tracker.delete(entry)
            } label: {
                Label("刪除", systemImage: "trash")
            }
        }
    }
}

private struct AddDrinkView: View {
    @Environment(\.dismiss) private var dismiss
    let tracker: SugarTracker
    private let editingEntry: DrinkEntry?

    @State private var name: String
    @State private var sugar: Double
    @State private var price: Double
    @State private var volumeML: Double
    @State private var date: Date
    @State private var selectedToppings: Set<String>
    @State private var selectedSource: String

    init(tracker: SugarTracker, editingEntry: DrinkEntry? = nil) {
        self.tracker = tracker
        self.editingEntry = editingEntry
        _name = State(initialValue: editingEntry?.name ?? "")
        _sugar = State(initialValue: editingEntry?.sugarGrams ?? 0)
        _price = State(initialValue: editingEntry?.price ?? 0)
        _volumeML = State(initialValue: 500)
        _date = State(initialValue: editingEntry?.date ?? Date())
        _selectedToppings = State(initialValue: [])
        _selectedSource = State(initialValue: editingEntry?.source ?? "手動輸入")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("飲料資訊") {
                    TextField("飲料名稱，可輸入中文，例如：五十嵐珍珠奶茶", text: $name)
                    DatePicker("飲用時間", selection: $date)
                    TextField("容量（ml）", value: $volumeML, format: .number)
                    TextField("糖分（g）", value: $sugar, format: .number)
                    TextField("價格（NT$）", value: $price, format: .number)
                 }

                Section("台灣手搖飲快速模板") {
                    Text("以下是甜度估算，不是品牌官方營養標示；套用後可再修改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(TaiwanDrinkTemplate.common) { template in
                        Button {
                            apply(template: template)
                        } label: {
                            HStack {
                                Text(template.name)
                                Spacer()
                                Text("\(template.sugarPer100ML, format: .number.precision(.fractionLength(0...1))) g / 100 ml")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("小料") {
                    Text("以下為每份小料的估算糖分，會直接加到本杯糖分；請依店家標示調整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(DrinkTopping.common) { topping in
                        Button {
                            toggle(topping: topping)
                        } label: {
                            HStack {
                                Text(topping.name)
                                Spacer()
                                Text("+\(topping.sugarGrams, format: .number.precision(.fractionLength(0...0))) g")
                                    .foregroundStyle(.orange)
                                Image(systemName: selectedToppings.contains(topping.name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedToppings.contains(topping.name) ? .teal : .secondary)
                            }
                        }
                    }
                }

                Section("我的常用飲料") {
                    let favorites = tracker.matchingFavorites(for: name)

                    if favorites.isEmpty {
                        Text("儲存一筆飲料紀錄後，它會自動出現在這裡。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites) { favorite in
                            Button {
                                name = favorite.name
                                sugar = favorite.sugarGrams
                                price = favorite.price
                                selectedSource = "我的常用飲料"
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(favorite.name).foregroundStyle(.primary)
                                        Text("\(favorite.sugarGrams, format: .number.precision(.fractionLength(0...1))) g")
                                            .font(.caption)
                                            .foregroundStyle(.teal)
                                    }
                                    Spacer()
                                    Text("NT$\(favorite.price, format: .number.precision(.fractionLength(0...0)))")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

            }
            .navigationTitle("新增飲料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingEntry == nil ? "儲存" : "更新") {
                        if let editingEntry {
                            tracker.update(
                                editingEntry,
                                name: name,
                                sugarGrams: sugar,
                                price: price,
                                date: date,
                                source: selectedSource
                            )
                        } else {
                            tracker.add(DrinkEntry(name: name, sugarGrams: sugar, price: price, date: date, source: selectedSource))
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func apply(template: TaiwanDrinkTemplate) {
        name = template.name
        sugar = template.sugarPer100ML * volumeML / 100
        selectedSource = template.note
    }

    private func toggle(topping: DrinkTopping) {
        if selectedToppings.contains(topping.name) {
            selectedToppings.remove(topping.name)
            sugar = max(0, sugar - topping.sugarGrams)
        } else {
            selectedToppings.insert(topping.name)
            sugar += topping.sugarGrams
        }
    }
}

#Preview {
    ContentView()
}
