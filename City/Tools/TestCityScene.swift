import Foundation

@main
enum TestCityScene {
    static func main() {
        testDeterminismAndIndependentWindows()
        testClockAndPauses()
        testThirtyMinutes()
        testWeatherOverrides()
        print("City windows, weather, trains, occasional cars, clock recovery and 30-minute simulation: OK")
    }

    private static func testDeterminismAndIndependentWindows() {
        var first = CitySceneModel(seed: 2026)
        var matching = CitySceneModel(seed: 2026)
        let other = CitySceneModel(seed: 2027)
        let initial = (0..<1_000).map { first.windowLight(id: $0) }
        precondition(initial.contains(0) && initial.contains { $0 > 0.7 })
        precondition(initial != (0..<1_000).map { other.windowLight(id: $0) })
        var changedWindows = Set<Int>()
        var previous = initial
        var independentFrames = 0
        for _ in 0..<6_000 {
            first.step(seconds: 0.1)
            matching.step(seconds: 0.1)
            precondition(first.time == matching.time)
            precondition(first.weather == matching.weather && first.train == matching.train)
            precondition(first.cars == matching.cars)
            let lights = (0..<1_000).map { first.windowLight(id: $0) }
            let changed = lights.indices.filter { abs(lights[$0] - previous[$0]) > 0.000_001 }
            if !changed.isEmpty && changed.count < 250 { independentFrames += 1 }
            changedWindows.formUnion(changed)
            for index in lights.indices {
                precondition((0...1).contains(lights[index]))
                precondition(abs(lights[index] - previous[index]) <= 0.044,
                             "Window jumped instead of fading")
                precondition(lights[index] == matching.windowLight(id: index))
            }
            previous = lights
        }
        precondition(changedWindows.count == 1_000, "Some windows never changed in ten minutes")
        precondition(independentFrames > 5_000, "Windows formed a shared short animation cycle")
        precondition((0...1).contains(first.windowLight(id: -1)))
        precondition((0...1).contains(first.windowLight(id: Int.max)))
    }

    private static func testClockAndPauses() {
        var city = CitySceneModel(seed: 3)
        city.advance(to: 10_000)
        precondition(city.time == 0)
        city.advance(to: 10_000.2)
        precondition(abs(city.time - 0.2) < 0.000_001)
        city.advance(to: 9_000)
        precondition(abs(city.time - 0.2) < 0.000_001)
        city.advance(to: 10_000.4)
        precondition(abs(city.time - 0.4) < 0.000_001)
        city.advance(to: 1_000_000)
        precondition(abs(city.time - 0.9) < 0.000_001,
                     "Resume replayed events accumulated during sleep")
        city.advance(to: 1_000_000.1)
        precondition(abs(city.time - 1) < 0.000_001)
        let before = city.time
        city.advance(to: .nan)
        city.advance(to: .infinity)
        city.step(seconds: -1)
        city.step(seconds: .nan)
        city.step(seconds: .infinity)
        precondition(city.time == before)
        city.step(seconds: 1_000_000_000)
        checkState(city)
        city.step(seconds: 0.1)
        checkState(city)
    }

    private static func testThirtyMinutes() {
        var trainCount = 0
        var rainSeen = false
        var cloudySeen = false
        var dryingSeen = false
        var directions = Set<Int>()
        var carriageCounts = Set<Int>()
        var city = CitySceneModel(seed: 0xC17_2026)
        var previousTrain: CityTrainState?
        var previousWeather = city.weather
        var trainStart: Double?
        var previousTrainEnd: Double?
        var carCount = 0
        var previousCars: [Int: CityCarState] = [:]
        var carStarts: [Int: Double] = [:]
        var carEnds: [Int: Double] = [:]
        var carDirections = Set<Int>()
        var carStyles = Set<Int>()
        var emptyRoadFrames = 0
        for _ in 0..<18_000 {
            city.step(seconds: 0.1)
            checkState(city)
            let train = city.train
            if let train {
                directions.insert(train.direction)
                carriageCounts.insert(train.carCount)
                if previousTrain == nil {
                    trainCount += 1
                    trainStart = city.time
                    if let previousTrainEnd {
                        precondition((29.8...65.2).contains(city.time - previousTrainEnd),
                                     "Train pause outside expected bounds")
                    } else {
                        precondition((4.9...5.2).contains(city.time), "First train did not arrive after five seconds")
                    }
                } else if let previousTrain {
                    precondition(train.direction == previousTrain.direction)
                    precondition(train.carCount == previousTrain.carCount)
                    precondition(train.progress >= previousTrain.progress)
                    precondition(train.progress - previousTrain.progress <= 0.008_34)
                }
            } else if previousTrain != nil {
                guard let trainStart else { preconditionFailure("Train start missing") }
                precondition((11.8...16.2).contains(city.time - trainStart),
                             "Train did not use the faster 12...16-second passage")
                previousTrainEnd = city.time
            }
            let cars = Dictionary(uniqueKeysWithValues: city.cars.map { ($0.lane, $0) })
            if cars.isEmpty { emptyRoadFrames += 1 }
            for lane in 0..<2 {
                if let car = cars[lane] {
                    carDirections.insert(car.direction)
                    carStyles.insert(car.style)
                    if let previous = previousCars[lane] {
                        precondition(car.style == previous.style && car.direction == previous.direction)
                        precondition(car.progress >= previous.progress)
                        precondition(car.progress - previous.progress <= 0.011_12,
                                     "Car moved faster than its shortest passage")
                    } else {
                        carCount += 1
                        carStarts[lane] = city.time
                        if let end = carEnds[lane] {
                            precondition((19.8...40.2).contains(city.time - end),
                                         "Cars followed one another without a quiet interval")
                        } else {
                            let firstDeparture = lane == 0 ? 3.0 : 11.0
                            precondition(abs(city.time - firstDeparture) <= 0.2)
                        }
                    }
                } else if previousCars[lane] != nil {
                    guard let start = carStarts[lane] else { preconditionFailure("Car start missing") }
                    precondition((8.8...14.2).contains(city.time - start),
                                 "Car passage outside 9...14-second bounds")
                    carEnds[lane] = city.time
                }
            }
            previousCars = cars
            rainSeen = rainSeen || city.weather.rain > 0.5
            cloudySeen = cloudySeen || city.weather.cloudiness > 0.6
            dryingSeen = dryingSeen || (city.weather.rain < 0.02 && city.weather.wetness > 0.25
                                         && city.weather.wetness < previousWeather.wetness)
            precondition(abs(city.weather.cloudiness - previousWeather.cloudiness) < 0.006)
            precondition(abs(city.weather.rain - previousWeather.rain) < 0.006)
            precondition(abs(city.weather.wetness - previousWeather.wetness) < 0.006)
            previousTrain = train
            previousWeather = city.weather
        }
        precondition((20...44).contains(trainCount), "Train passages lacked substantial pauses")
        precondition(directions == [-1, 1] && carriageCounts == [3, 4])
        precondition((65...120).contains(carCount), "Traffic was missing or too frequent")
        precondition(carDirections == [-1, 1] && carStyles == [0, 1, 2, 3])
        precondition(emptyRoadFrames > 4_000, "Roads never became quiet")
        precondition(rainSeen && cloudySeen && dryingSeen, "Weather did not vary or puddles dried instantly")
        print("30-minute sample: \(trainCount) train passages, \(carCount) cars, both directions, changing weather and persistent wetness")
    }

    private static func testWeatherOverrides() {
        var city = CitySceneModel(seed: 9)
        city.step(seconds: 450)
        let original = city.weather
        precondition(city.weather(for: nil) == original)
        precondition(city.weather(for: .clear).rain == 0)
        precondition(city.weather(for: .cloudy).cloudiness > 0.7)
        precondition(city.weather(for: .rain).rain > 0.7)
        precondition(city.weather == original, "Preview override changed live weather")
    }

    private static func checkState(_ city: CitySceneModel) {
        precondition(city.time.isFinite && city.time >= 0)
        for value in [city.weather.cloudiness, city.weather.rain, city.weather.wetness] {
            precondition(value.isFinite && (0...1).contains(value))
        }
        if let train = city.train {
            precondition(train.progress.isFinite && (0...1).contains(train.progress))
            precondition(train.direction == -1 || train.direction == 1)
            precondition(train.carCount == 3 || train.carCount == 4)
        }
        precondition(city.cars.count <= 2, "Traffic grew beyond its two scheduled lanes")
        precondition(Set(city.cars.map(\.lane)).count == city.cars.count)
        for car in city.cars {
            precondition(car.progress.isFinite && (0...1).contains(car.progress))
            precondition(car.lane == 0 || car.lane == 1)
            precondition(car.direction == (car.lane == 0 ? 1 : -1))
            precondition((0...3).contains(car.style))
        }
        for id in [0, 31, 100, 410, 512, 999, 1_023] {
            precondition((0...1).contains(city.windowLight(id: id)))
        }
    }
}
