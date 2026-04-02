//
//  CronParserView+.swift
//  DevToys
//
//  Created by DevToys on 2024/01/01.
//

import CoreUtil

// MARK: - Cron Precision Mode -
enum CronPrecisionMode: String, TextItem, CaseIterable {
    case withSeconds = "With Seconds (6 fields)"
    case withoutSeconds = "Without Seconds (5 fields)"

    var title: String { rawValue.localized() }
}

// MARK: - Cron Parser -
struct CronParser {

    static func nextExecutionTimes(expression: String, mode: CronPrecisionMode, count: Int = 10) -> Result<[Date], CronError> {
        let fields = expression.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        let expectedCount = mode == .withSeconds ? 6 : 5
        guard fields.count == expectedCount else {
            return .failure(.invalidFieldCount(expected: expectedCount, got: fields.count))
        }

        let secondField: String
        let minuteField: String
        let hourField: String
        let dayOfMonthField: String
        let monthField: String
        let dayOfWeekField: String

        if mode == .withSeconds {
            secondField = fields[0]
            minuteField = fields[1]
            hourField = fields[2]
            dayOfMonthField = fields[3]
            monthField = fields[4]
            dayOfWeekField = fields[5]
        } else {
            secondField = "0"
            minuteField = fields[0]
            hourField = fields[1]
            dayOfMonthField = fields[2]
            monthField = fields[3]
            dayOfWeekField = fields[4]
        }

        let seconds: Set<Int>
        let minutes: Set<Int>
        let hours: Set<Int>
        let daysOfMonth: Set<Int>
        let months: Set<Int>
        let daysOfWeek: Set<Int>

        do {
            seconds = try parseField(secondField, range: 0...59, name: "second")
            minutes = try parseField(minuteField, range: 0...59, name: "minute")
            hours = try parseField(hourField, range: 0...23, name: "hour")
            daysOfMonth = try parseField(dayOfMonthField, range: 1...31, name: "day-of-month")
            months = try parseField(monthField, range: 1...12, name: "month")
            daysOfWeek = try parseField(dayOfWeekField, range: 0...6, name: "day-of-week")
        } catch let error as CronError {
            return .failure(error)
        } catch {
            return .failure(.invalidExpression(error.localizedDescription))
        }

        var results = [Date]()
        let calendar = Calendar.current
        var candidate = Date()

        let maxIterations = 500_000
        var iterations = 0

        while results.count < count && iterations < maxIterations {
            iterations += 1
            candidate = calendar.date(byAdding: .second, value: 1, to: candidate)!

            let comps = calendar.dateComponents([.second, .minute, .hour, .day, .month, .weekday], from: candidate)
            guard let sec = comps.second, let min = comps.minute, let hr = comps.hour,
                  let day = comps.day, let mon = comps.month, let wd = comps.weekday else { continue }

            // Calendar weekday: 1=Sunday...7=Saturday, cron: 0=Sunday...6=Saturday
            let cronWeekday = wd - 1

            if seconds.contains(sec) && minutes.contains(min) && hours.contains(hr)
                && daysOfMonth.contains(day) && months.contains(mon) && daysOfWeek.contains(cronWeekday) {
                results.append(candidate)
            }
        }

        if results.isEmpty {
            return .failure(.noMatchFound)
        }

        return .success(results)
    }

    static func describeExpression(expression: String, mode: CronPrecisionMode) -> Result<String, CronError> {
        let fields = expression.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        let expectedCount = mode == .withSeconds ? 6 : 5
        guard fields.count == expectedCount else {
            return .failure(.invalidFieldCount(expected: expectedCount, got: fields.count))
        }

        var parts = [String]()
        if mode == .withSeconds {
            parts.append(describeField(fields[0], unit: "second"))
            parts.append(describeField(fields[1], unit: "minute"))
            parts.append(describeField(fields[2], unit: "hour"))
            parts.append(describeField(fields[3], unit: "day-of-month"))
            parts.append(describeField(fields[4], unit: "month"))
            parts.append(describeField(fields[5], unit: "day-of-week"))
        } else {
            parts.append(describeField(fields[0], unit: "minute"))
            parts.append(describeField(fields[1], unit: "hour"))
            parts.append(describeField(fields[2], unit: "day-of-month"))
            parts.append(describeField(fields[3], unit: "month"))
            parts.append(describeField(fields[4], unit: "day-of-week"))
        }

        return .success(parts.joined(separator: "\n"))
    }

    // MARK: - Private Helpers -

    private static func describeField(_ field: String, unit: String) -> String {
        if field == "*" {
            return "[\(unit)] every \(unit)"
        }
        if field.hasPrefix("*/") {
            let step = field.dropFirst(2)
            return "[\(unit)] every \(step) \(unit)(s)"
        }
        if field.contains(",") {
            return "[\(unit)] at \(unit) \(field)"
        }
        if field.contains("-") {
            let rangeParts = field.split(separator: "-")
            if rangeParts.count == 2 {
                return "[\(unit)] from \(rangeParts[0]) to \(rangeParts[1])"
            }
        }
        return "[\(unit)] at \(unit) \(field)"
    }

    private static func parseField(_ field: String, range: ClosedRange<Int>, name: String) throws -> Set<Int> {
        var result = Set<Int>()

        let parts = field.split(separator: ",").map(String.init)
        for part in parts {
            if part == "*" {
                result.formUnion(Set(range))
            } else if part.hasPrefix("*/") {
                guard let step = Int(part.dropFirst(2)), step > 0 else {
                    throw CronError.invalidField(name: name, value: part)
                }
                var i = range.lowerBound
                while i <= range.upperBound {
                    result.insert(i)
                    i += step
                }
            } else if part.contains("/") {
                let slashParts = part.split(separator: "/").map(String.init)
                guard slashParts.count == 2 else {
                    throw CronError.invalidField(name: name, value: part)
                }
                let basePart = slashParts[0]
                guard let step = Int(slashParts[1]), step > 0 else {
                    throw CronError.invalidField(name: name, value: part)
                }
                let startVal: Int
                let endVal: Int
                if basePart.contains("-") {
                    let rangeParts = basePart.split(separator: "-").map(String.init)
                    guard rangeParts.count == 2, let s = Int(rangeParts[0]), let e = Int(rangeParts[1]) else {
                        throw CronError.invalidField(name: name, value: part)
                    }
                    startVal = s
                    endVal = e
                } else if basePart == "*" {
                    startVal = range.lowerBound
                    endVal = range.upperBound
                } else {
                    guard let s = Int(basePart) else {
                        throw CronError.invalidField(name: name, value: part)
                    }
                    startVal = s
                    endVal = range.upperBound
                }
                var i = startVal
                while i <= endVal {
                    if range.contains(i) { result.insert(i) }
                    i += step
                }
            } else if part.contains("-") {
                let rangeParts = part.split(separator: "-").map(String.init)
                guard rangeParts.count == 2, let start = Int(rangeParts[0]), let end = Int(rangeParts[1]) else {
                    throw CronError.invalidField(name: name, value: part)
                }
                guard range.contains(start) && range.contains(end) && start <= end else {
                    throw CronError.invalidField(name: name, value: part)
                }
                result.formUnion(Set(start...end))
            } else {
                guard let val = Int(part), range.contains(val) else {
                    throw CronError.invalidField(name: name, value: part)
                }
                result.insert(val)
            }
        }

        return result
    }
}

// MARK: - Cron Error -
enum CronError: LocalizedError {
    case invalidFieldCount(expected: Int, got: Int)
    case invalidField(name: String, value: String)
    case invalidExpression(String)
    case noMatchFound

    var errorDescription: String? {
        switch self {
        case .invalidFieldCount(let expected, let got):
            return "Expected \(expected) fields, got \(got)"
        case .invalidField(let name, let value):
            return "Invalid \(name) field: \(value)"
        case .invalidExpression(let msg):
            return "Invalid expression: \(msg)"
        case .noMatchFound:
            return "No matching execution time found"
        }
    }
}

// MARK: - ViewController -
final class CronParserViewController: NSViewController {
    private let cell = CronParserView()

    @RestorableState("cron.expression") private var expression = "0 */5 * * * *"
    @RestorableState("cron.precisionMode") private var precisionMode: CronPrecisionMode = .withSeconds

    @Observable private var descriptionText = ""
    @Observable private var nextTimesText = ""
    @Observable private var isError = false

    override func loadView() { self.view = cell }

    override func viewDidLoad() {
        self.cell.precisionModePicker.selectedItem = precisionMode
        self.cell.expressionField.string = expression

        self.cell.precisionModePicker.itemPublisher
            .sink{[unowned self] in
                self.precisionMode = $0
                self.cell.precisionModePicker.selectedItem = $0
                self.updatePlaceholder()
                self.parse()
            }
            .store(in: &objectBag)

        self.cell.expressionField.changeStringPublisher
            .handleEvents(receiveOutput: { [unowned self] in self.expression = $0 })
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink{[unowned self] _ in
                self.parse()
            }
            .store(in: &objectBag)

        self.$descriptionText
            .sink{[unowned self] in self.cell.descriptionSection.string = $0 }
            .store(in: &objectBag)

        self.$nextTimesText
            .sink{[unowned self] in self.cell.nextTimesSection.string = $0 }
            .store(in: &objectBag)

        self.$isError
            .sink{[unowned self] in self.cell.expressionField.isError = $0 }
            .store(in: &objectBag)

        self.updatePlaceholder()
        self.parse()
    }

    private func updatePlaceholder() {
        if precisionMode == .withSeconds {
            self.cell.expressionField.placeholder = "e.g. 0 */5 * * * *"
        } else {
            self.cell.expressionField.placeholder = "e.g. */5 * * * *"
        }
    }

    private func parse() {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else {
            self.descriptionText = ""
            self.nextTimesText = ""
            self.isError = false
            return
        }

        let mode = precisionMode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Description
            let descResult = CronParser.describeExpression(expression: expr, mode: mode)

            var timesResult: Result<[Date], CronError>?
            if case .success = descResult {
                timesResult = CronParser.nextExecutionTimes(expression: expr, mode: mode, count: 10)
            }

            DispatchQueue.main.async {
                guard let self = self else { return }

                switch descResult {
                case .success(let desc):
                    self.descriptionText = desc
                    self.isError = false
                case .failure(let error):
                    self.descriptionText = error.localizedDescription
                    self.isError = true
                    self.nextTimesText = ""
                    return
                }

                if let timesResult = timesResult {
                    switch timesResult {
                    case .success(let dates):
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss (EEEE)"
                        let lines = dates.enumerated().map { "\($0.offset + 1). \(formatter.string(from: $0.element))" }
                        self.nextTimesText = lines.joined(separator: "\n")
                    case .failure(let error):
                        self.nextTimesText = error.localizedDescription
                    }
                }
            }
        }
    }
}

// MARK: - View -
final private class CronParserView: Page {

    let precisionModePicker = EnumPopupButton<CronPrecisionMode>()
    let expressionField = TextField(showCopyButton: false)
    let descriptionSection = TextViewSection(title: "Description".localized(), options: .defaultOutput)
    let nextTimesSection = TextViewSection(title: "Next Execution Times".localized(), options: .defaultOutput)

    override func layout() {
        super.layout()
        self.descriptionSection.snp.remakeConstraints{ make in
            make.height.equalTo(max(120, (self.frame.height - 340) * 0.35))
            make.left.right.equalToSuperview().inset(16)
        }
        self.nextTimesSection.snp.remakeConstraints{ make in
            make.height.equalTo(max(200, (self.frame.height - 340) * 0.65))
            make.left.right.equalToSuperview().inset(16)
        }
    }

    override func onAwake() {
        self.addSection(Section(title: "Configuration".localized(), items: [
            Area(icon: R.Image.paramators, title: "Precision Mode".localized(),
                 message: "Select seconds or minutes precision".localized(), control: precisionModePicker)
        ]))

        self.expressionField.font = .monospacedSystemFont(ofSize: R.Size.controlTitleFontSize, weight: .regular)
        self.addSection(Section(title: "Cron Expression".localized(), items: [expressionField]))

        self.addSection(descriptionSection)
        self.addSection(nextTimesSection)
    }
}
