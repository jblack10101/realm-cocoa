////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Foundation
import Realm
import Realm.Private
import Realm.Dynamic
import RealmSwift
import XCTest

func inMemoryRealm(_ inMememoryIdentifier: String) -> Realm {
    return try! Realm(configuration: Realm.Configuration(inMemoryIdentifier: inMememoryIdentifier))
}

class TestCase: XCTestCase {
    var exceptionThrown = false
    var testDir: String! = nil

    @discardableResult
    func realmWithTestPath(configuration: Realm.Configuration = Realm.Configuration()) -> Realm {
        var configuration = configuration
        configuration.fileURL = testRealmURL()
        return try! Realm(configuration: configuration)
    }

    override class func setUp() {
        super.setUp()
#if DEBUG || arch(i386) || arch(x86_64)
        // Disable actually syncing anything to the disk to greatly speed up the
        // tests, but only when not running on device because it can't be
        // re-enabled and we need it enabled for performance tests
        RLMDisableSyncToDisk()
#endif
        do {
            // Clean up any potentially lingering Realm files from previous runs
            try FileManager.default().removeItem(atPath: RLMRealmPathForFile(""))
        } catch {
            // The directory might not actually already exist, so not an error
        }
    }

    override class func tearDown() {
        RLMRealm.resetRealmState()
        super.tearDown()
    }

    override func invokeTest() {
        testDir = RLMRealmPathForFile(realmFilePrefix())

        do {
            try FileManager.default().removeItem(atPath: testDir)
        } catch {
            // The directory shouldn't actually already exist, so not an error
        }
        try! FileManager.default().createDirectory(at: NSURL(fileURLWithPath: testDir, isDirectory: true) as URL,
                                                     withIntermediateDirectories: true, attributes: nil)

        let config = Realm.Configuration(fileURL: defaultRealmURL())
        Realm.Configuration.defaultConfiguration = config

        exceptionThrown = false
        autoreleasepool { super.invokeTest() }

        if !exceptionThrown {
            XCTAssertFalse(RLMHasCachedRealmForPath(defaultRealmURL().path!))
            XCTAssertFalse(RLMHasCachedRealmForPath(testRealmURL().path!))
        }

        resetRealmState()

        do {
            try FileManager.default().removeItem(atPath: testDir)
        } catch {
            XCTFail("Unable to delete realm files")
        }

        // Verify that there are no remaining realm files after the test
        let parentDir = (testDir as NSString).deletingLastPathComponent
        for url in FileManager().enumerator(atPath: parentDir)! {
            XCTAssertNotEqual(url.pathExtension, "realm", "Lingering realm file at \(parentDir)/\(url)")
            assert(url.pathExtension != "realm")
        }
    }

    func resetRealmState() {
        RLMRealm.resetRealmState()
    }

    func dispatchSyncNewThread(block: () -> ()) {
        let queue = DispatchQueue(label: "background")
        queue.async() {
            autoreleasepool {
                block()
            }
        }
        queue.sync() {}
    }

    func assertThrows<T>(_ block: @autoclosure(escaping)() -> T, _ message: String? = nil,
                         named: String? = RLMExceptionName, fileName: String = #file, lineNumber: UInt = #line) {
        exceptionThrown = true
        RLMAssertThrows(self, { _ = block() }, named, message, fileName, lineNumber)
    }

    func assertSucceeds(message: String? = nil, fileName: StaticString = #file,
                        lineNumber: UInt = #line, block: @noescape () throws -> ()) {
        do {
            try block()
        } catch {
            XCTFail("Expected no error, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Error, _ message: String? = nil,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: @noescape () throws -> T) {
        do {
            _ = try block()
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch expectedError {
            // Success!
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertNil<T>(block: @autoclosure() -> T?, _ message: String? = nil,
                      fileName: StaticString = #file, lineNumber: UInt = #line) {
        XCTAssert(block() == nil, message ?? "", file: fileName, line: lineNumber)
    }

    private func realmFilePrefix() -> String {
        return name!.trimmingCharacters(in: NSCharacterSet(charactersIn: "-[]") as CharacterSet)
    }

    internal func testRealmURL() -> NSURL {
        return realmURLForFile("test.realm")
    }

    internal func defaultRealmURL() -> NSURL {
        return realmURLForFile("default.realm")
    }

    private func realmURLForFile(_ fileName: String) -> NSURL {
        let directory = NSURL(fileURLWithPath: testDir, isDirectory: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)!
    }
}