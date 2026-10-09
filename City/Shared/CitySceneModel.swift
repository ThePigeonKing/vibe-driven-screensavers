import Foundation

enum CityWeatherPreset: CaseIterable, Equatable, Sendable {
    case clear, cloudy, rain
}

struct CityWeatherState: Equatable, Sendable {
    let cloudiness: Double
    let rain: Double
    let wetness: Double
}

struct CityTrainState: Equatable, Sendable {
    let progress: Double
    let direction: Int
    let carCount: Int
}

struct CityCarState: Equatable, Sendable {
    let progress: Double
    let direction: Int
    let lane: Int
    let style: Int
}

/// Animation time is independent of the wall clock used by the station display.
/// Each window has its own random stream and dwell times; there is no shared loop.
struct CitySceneModel: Sendable {
    static let windowCount = 1_024
    static let maximumFrameAdvance = 0.5

    private(set) var time: Double = 0
    private(set) var weather = CityWeatherState(cloudiness: 0.22, rain: 0, wetness: 0.35)

    var train: CityTrainState? {
        let progress = (time - scheduledTrain.departure) / scheduledTrain.duration
        guard progress >= 0, progress <= 1 else { return nil }
        return CityTrainState(progress: progress, direction: scheduledTrain.direction,
                              carCount: scheduledTrain.carCount)
    }

    /// Two independently scheduled road lanes keep traffic occasional and
    /// bound the number of visible cars regardless of the running time.
    var cars: [CityCarState] {
        trafficLanes.compactMap { $0.car(at: time) }
    }

    private var windows: [CityWindowLight]
    private var nextWindowChange: Double
    private var weatherRandom: CityRandom
    private var trainRandom: CityRandom
    private var weatherPreset: CityWeatherPreset = .clear
    private var weatherFrom = CityWeatherState(cloudiness: 0.22, rain: 0, wetness: 0.35)
    private var weatherTarget = CityWeatherState(cloudiness: 0.22, rain: 0, wetness: 0.35)
    private var weatherTransitionStart: Double = 0
    private var weatherTransitionDuration: Double = 0
    private var nextWeatherChange: Double
    private var scheduledTrain: CityScheduledTrain
    private var trafficLanes: [CityTrafficLane]
    private var lastUptime: TimeInterval?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        var seedSource = CityRandom(seed: seed)
        var windowSource = CityRandom(seed: seedSource.next())
        let newWindows = (0..<Self.windowCount).map { _ in
            CityWindowLight(seed: windowSource.next())
        }
        windows = newWindows
        nextWindowChange = newWindows.map(\.nextChange).min() ?? .infinity
        weatherRandom = CityRandom(seed: seedSource.next())
        trainRandom = CityRandom(seed: seedSource.next())
        nextWeatherChange = weatherRandom.value(in: 65...110)
        scheduledTrain = CityScheduledTrain(departure: 5, random: &trainRandom)
        var trafficSource = CityRandom(seed: seedSource.next())
        trafficLanes = (0..<2).map { lane in
            CityTrafficLane(lane: lane, departure: lane == 0 ? 3 : 11,
                            seed: trafficSource.next())
        }
    }

    /// Uptime can jump after sleep or a paused preview. Reanchor the clock and
    /// advance at most half a second, so resuming never replays hours of events.
    mutating func advance(to uptime: TimeInterval) {
        guard uptime.isFinite else { return }
        guard let previous = lastUptime else {
            lastUptime = uptime
            return
        }
        guard uptime >= previous else { return }
        lastUptime = uptime
        step(seconds: min(uptime - previous, Self.maximumFrameAdvance))
    }

    /// Direct simulation entry point for previews and deterministic rendering.
    mutating func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, (time + seconds).isFinite else { return }
        time += seconds
        advanceWindows()
        advanceWeather(seconds: seconds)
        advanceTrains()
        for lane in trafficLanes.indices {
            trafficLanes[lane].advance(to: time)
        }
    }

    func windowLight(id: Int) -> Double {
        // Building and tower windows share a fixed pool of independent schedules.
        // Wrapping identifiers keeps storage bounded as the skyline grows.
        let index = Int(UInt64(bitPattern: Int64(id)) % UInt64(Self.windowCount))
        return windows[index].light(at: time)
    }

    /// Fixed weather previews do not alter the live simulation or its schedule.
    func weather(for override: CityWeatherPreset?) -> CityWeatherState {
        guard let override else { return weather }
        switch override {
        case .clear: return CityWeatherState(cloudiness: 0.22, rain: 0, wetness: 0.15)
        case .cloudy: return CityWeatherState(cloudiness: 0.76, rain: 0, wetness: 0.28)
        case .rain: return CityWeatherState(cloudiness: 0.91, rain: 0.76, wetness: 0.88)
        }
    }

    private mutating func advanceWindows() {
        guard time >= nextWindowChange else { return }
        var next = Double.infinity
        for index in windows.indices {
            windows[index].advance(to: time)
            next = min(next, windows[index].nextChange)
        }
        nextWindowChange = next
    }

    private mutating func advanceWeather(seconds: Double) {
        var changes = 0
        while time >= nextWeatherChange, changes < 64 {
            weatherTransitionStart = nextWeatherChange
            weatherFrom = weatherTarget
            switch weatherPreset {
            case .clear:
                weatherPreset = .cloudy
            case .cloudy:
                weatherPreset = weatherRandom.unit() < 0.58 ? .rain : .clear
            case .rain:
                weatherPreset = weatherRandom.unit() < 0.85 ? .cloudy : .clear
            }
            switch weatherPreset {
            case .clear:
                weatherTarget = CityWeatherState(cloudiness: weatherRandom.value(in: 0.12...0.30),
                                                 rain: 0, wetness: 0)
            case .cloudy:
                weatherTarget = CityWeatherState(cloudiness: weatherRandom.value(in: 0.64...0.82),
                                                 rain: 0, wetness: 0)
            case .rain:
                weatherTarget = CityWeatherState(cloudiness: weatherRandom.value(in: 0.82...0.96),
                                                 rain: weatherRandom.value(in: 0.56...0.82), wetness: 0)
            }
            weatherTransitionDuration = weatherRandom.value(in: 25...45)
            nextWeatherChange = weatherTransitionStart + weatherTransitionDuration
                + weatherRandom.value(in: 60...140)
            changes += 1
        }
        // A deliberately enormous direct QA jump remains bounded in cost.
        // Normal frame updates and minute-scale snapshots never take this path.
        if time >= nextWeatherChange {
            weatherTransitionStart = time
            nextWeatherChange = time + weatherTransitionDuration + 100
        }
        let blend = weatherTransitionDuration > 0
            ? citySmooth((time - weatherTransitionStart) / weatherTransitionDuration) : 1
        let cloudiness = cityMix(weatherFrom.cloudiness, weatherTarget.cloudiness, blend)
        let rain = cityMix(weatherFrom.rain, weatherTarget.rain, blend)
        let wetnessTarget = max(0.06, rain * 1.16 + cloudiness * 0.03)
        let dryingTime = wetnessTarget > weather.wetness ? 18.0 : 150.0
        let wetness = cityMix(weather.wetness, wetnessTarget, 1 - exp(-seconds / dryingTime))
        weather = CityWeatherState(cloudiness: cityClamp(cloudiness), rain: cityClamp(rain),
                                   wetness: cityClamp(wetness))
    }

    private mutating func advanceTrains() {
        var passages = 0
        while time > scheduledTrain.departure + scheduledTrain.duration, passages < 64 {
            let departure = scheduledTrain.departure + scheduledTrain.duration
                + trainRandom.value(in: 30...65)
            scheduledTrain = CityScheduledTrain(departure: departure, random: &trainRandom)
            passages += 1
        }
        if time > scheduledTrain.departure + scheduledTrain.duration {
            scheduledTrain = CityScheduledTrain(departure: time + trainRandom.value(in: 30...65),
                                                random: &trainRandom)
        }
    }
}

private struct CityWindowLight: Sendable {
    var random: CityRandom
    var isOn: Bool
    var from: Double
    var target: Double
    var transitionStart: Double = 0
    var transitionDuration: Double = 0
    var nextChange: Double

    init(seed: UInt64) {
        var source = CityRandom(seed: seed)
        isOn = source.unit() < 0.58
        let initialLight = isOn ? source.value(in: 0.72...1) : 0
        from = initialLight
        target = initialLight
        // Different initial offsets prevent a quiet first minute followed by a
        // shared wave of changes. Later dwell times are always 20...110 seconds.
        nextChange = source.value(in: 3...110)
        random = source
    }

    func light(at time: Double) -> Double {
        guard transitionDuration > 0 else { return target }
        return cityMix(from, target, citySmooth((time - transitionStart) / transitionDuration))
    }

    mutating func advance(to time: Double) {
        var changes = 0
        while time >= nextChange, changes < 64 {
            from = target
            isOn.toggle()
            target = isOn ? random.value(in: 0.72...1) : 0
            transitionStart = nextChange
            transitionDuration = random.value(in: 3.5...8.5)
            nextChange = transitionStart + transitionDuration + random.value(in: 20...110)
            changes += 1
        }
        if time >= nextChange {
            transitionStart = time
            nextChange = time + transitionDuration + random.value(in: 20...110)
        }
    }
}

private struct CityScheduledTrain: Sendable {
    let departure: Double
    let duration: Double
    let direction: Int
    let carCount: Int

    init(departure: Double, random: inout CityRandom) {
        self.departure = departure
        duration = random.value(in: 12...16)
        direction = random.unit() < 0.5 ? -1 : 1
        carCount = random.unit() < 0.5 ? 3 : 4
    }
}

private struct CityTrafficLane: Sendable {
    let lane: Int
    private var random: CityRandom
    private var departure: Double
    private var duration: Double
    private var style: Int

    init(lane: Int, departure: Double, seed: UInt64) {
        self.lane = lane
        self.departure = departure
        var source = CityRandom(seed: seed)
        duration = source.value(in: 9...14)
        style = Int(source.next() % 4)
        random = source
    }

    func car(at time: Double) -> CityCarState? {
        let progress = (time - departure) / duration
        guard progress >= 0, progress <= 1 else { return nil }
        return CityCarState(progress: progress, direction: lane == 0 ? 1 : -1,
                            lane: lane, style: style)
    }

    mutating func advance(to time: Double) {
        var passages = 0
        while time > departure + duration, passages < 64 {
            departure += duration + random.value(in: 20...40)
            duration = random.value(in: 9...14)
            style = Int(random.next() % 4)
            passages += 1
        }
        // Direct QA jumps can be arbitrarily large. Reanchor this one lane
        // after a bounded amount of work instead of retaining missed cars.
        if time > departure + duration {
            departure = time + random.value(in: 20...40)
            duration = random.value(in: 9...14)
            style = Int(random.next() % 4)
        }
    }
}

private struct CityRandom: Sendable {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }
    mutating func value(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}

private func cityClamp(_ value: Double) -> Double { min(1, max(0, value)) }
private func citySmooth(_ value: Double) -> Double {
    let clamped = cityClamp(value)
    return clamped * clamped * (3 - 2 * clamped)
}
private func cityMix(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * amount
}
