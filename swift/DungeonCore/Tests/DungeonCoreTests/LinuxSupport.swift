import XCTest

// Some tests borrow another test class's helpers. Apple's XCTest makes a test
// class with no arguments; Linux's only has init(name:testClosure:). These
// make them the right way on each, so the whole suite also runs on Linux.
#if os(Linux)
func makeAutoPlay() -> AutoPlayTests { AutoPlayTests(name: "helper", testClosure: { _ in }) }
func makeCreationBots() -> CreationBotTests { CreationBotTests(name: "helper", testClosure: { _ in }) }
#else
func makeAutoPlay() -> AutoPlayTests { AutoPlayTests() }
func makeCreationBots() -> CreationBotTests { CreationBotTests() }
#endif
