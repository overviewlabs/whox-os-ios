import Testing
@testable import WHOXCore

@Test func audioMeterClampsSilenceAndFullScale() {
    #expect(AudioMeter.level(rms: 0) == 0)
    #expect(AudioMeter.level(rms: 1) == 1)
    #expect(AudioMeter.level(rms: 2) == 1)
}

@Test func audioMeterMakesOrdinarySpeechVisiblyResponsive() {
    let quiet = AudioMeter.level(rms: 0.01)
    let speaking = AudioMeter.level(rms: 0.1)

    #expect(quiet > 0)
    #expect(speaking > quiet)
    #expect(speaking < 1)
}
