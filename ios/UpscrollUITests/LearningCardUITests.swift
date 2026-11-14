import XCTest

/// Drives the real feed (live YouTube Shorts) and taps through learning cards like a user.
final class LearningCardUITests: XCTestCase {
    /// New-word card: tap the word → reveal → Continue resumes.
    func testNewWordCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetJourney"]
        app.launch()
        let word = app.buttons.matching(identifier: "word-button").firstMatch
        let option = app.buttons.matching(identifier: "recall-option").firstMatch
        // Live feed: some Shorts have no learnable words. Swipe on like a user until a card shows up.
        let deadline = Date().addingTimeInterval(180)
        var lastSwipe = Date()
        while Date() < deadline && !word.exists && !option.exists {
            if app.buttons["original-skip"].exists { app.buttons["original-skip"].tap() }
            if Date().timeIntervalSince(lastSwipe) > 20 { app.swipeUp(); lastSwipe = Date() }
            sleep(1)
        }
        XCTAssertTrue(word.exists || option.exists, "no learning card appeared")
        if option.exists { option.tap() } else { word.tap() }
        try assertToggles(app)
        try assertRevealThenContinue(app, "new")
    }

    /// Every Short asks at least one question (no title-word cards; a fallback review / kana card when
    /// the captions have nothing). Scrolls 5 live (non-ad) Shorts and requires a card on each within 15 s.
    func testQuestionOnEveryShort() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetJourney"]
        app.launch()
        let closers = ["skip", "original-skip", "grammar-skip"]
        func cardCloser() -> XCUIElement? { closers.map { app.buttons[$0] }.first { $0.exists } }
        sleep(4)   // first Short loads
        var checked = 0
        for n in 1...7 where checked < 5 {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline && cardCloser() == nil { sleep(1) }
            let c = cardCloser()
            attach(app, "every-short-\(n)")
            // Sponsored Shorts never get questions (no learning on marketing copy).
            if c == nil, app.staticTexts["Sponsored"].exists { app.swipeUp(); sleep(2); continue }
            checked += 1
            XCTAssertNotNil(c, "Short \(n) asked no question within 15 s")
            c?.tap()
            sleep(1)
            if let again = cardCloser() { again.tap(); sleep(1) }   // a second card queued on the same Short
            app.swipeUp()
            sleep(2)
        }
    }

    /// "How to read it" and the example line are collapsed rows that expand on tap.
    private func assertToggles(_ app: XCUIApplication) throws {
        let reading = app.buttons["toggle-reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5), "reading toggle missing")
        // The open/closed choice is saved; a previous interrupted run may have left it open.
        if reading.value as? String == "expanded" { reading.tap(); sleep(1) }
        let example0 = app.buttons["toggle-example"]
        if example0.exists, example0.value as? String == "expanded" { example0.tap(); sleep(1) }
        XCTAssertEqual(reading.value as? String, "collapsed")
        attach(app, "toggle-1-collapsed")
        reading.tap()
        XCTAssertEqual(reading.value as? String, "expanded")
        sleep(1)   // let the expand animation (and the card's layout) settle before the next tap
        let example = app.buttons["toggle-example"]
        if example.exists { example.tap(); sleep(1); XCTAssertEqual(example.value as? String, "expanded") }
        sleep(1)
        attach(app, "toggle-2-expanded")
        // Restore the default (collapsed) so the saved preference doesn't leak into other runs.
        reading.tap()
        if example.exists { example.tap() }
    }

    /// "Remember it?" card: tap an answer → result + reveal → Continue resumes.
    /// Clears new-word cards along the way until a recall question shows up.
    func testRecallAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetJourney"]
        app.launch()
        let option = app.buttons.matching(identifier: "recall-option").firstMatch
        let word = app.buttons.matching(identifier: "word-button").firstMatch
        let cont = app.buttons["continue"]
        let deadline = Date().addingTimeInterval(180)
        var lastSwipe = Date()
        while Date() < deadline && !option.exists {
            if word.exists && !cont.exists { word.tap(); _ = cont.waitForExistence(timeout: 3); cont.tap(); lastSwipe = Date() }
            if app.buttons["original-skip"].exists { app.buttons["original-skip"].tap() }
            if Date().timeIntervalSince(lastSwipe) > 20 { app.swipeUp(); lastSwipe = Date() }
            sleep(1)
        }
        try XCTSkipUnless(option.exists, "no recall card within 150s of feed")
        attach(app, "recall-1-question")
        option.tap()
        try assertRevealThenContinue(app, "recall")
    }

    private func assertRevealThenContinue(_ app: XCUIApplication, _ tag: String) throws {
        let cont = app.buttons["continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue did not appear after answering")
        sleep(1)
        attach(app, "\(tag)-2-after-answer")
        XCTAssertTrue(cont.isHittable, "Continue is not tappable")
        cont.tap()
        sleep(2)
        attach(app, "\(tag)-3-after-continue")
        XCTAssertFalse(cont.exists, "card still visible after Continue")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

/// Nonverbal Short (no usable speech): picture / listening / review / object questions.
final class NonverbalUITests: XCTestCase {
    /// Steps through every card on a no-talking Short and screenshots each one (question + answered).
    /// Run with words collected, and as a brand-new learner (kana listening drill, new picture word).
    func testNonverbalCards() throws {
        for (args, name) in [(["-seedReview", "tired", "0"], "learner"), (["-resetWords"], "new")] {
            let app = XCUIApplication()
            app.launchArguments = ["-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E", "-forceNonverbal", "-resetJourney"] + args
                + (ProcessInfo.processInfo.environment["LESSON_SERVER"].map { ["-lessonServer", $0] } ?? [])
            app.launch()
            let option = app.buttons.matching(identifier: "recall-option").firstMatch
            var tags: [String] = []
            wordCardsSeen = 0
            for n in 1...3 {
                guard waitForQuestion(app, timeout: n == 1 ? 30 : 15) else { break }
                sleep(1)
                let tag = ["PICTURE", "LISTEN", "REVIEW", "REMEMBER IT?"].first { app.staticTexts[$0].exists } ?? "?"
                tags.append(tag)
                let shot = { (s: String) in
                    let a = XCTAttachment(screenshot: app.screenshot()); a.name = "\(name)-\(n)-\(tag)-\(s)"; a.lifetime = .keepAlways; self.add(a)
                }
                shot("q")
                option.tap()
                let cont = app.buttons["continue"]
                XCTAssertTrue(cont.waitForExistence(timeout: 5))
                sleep(1)
                shot("a")
                cont.tap()
            }
            // Learners with words: picture (+ color), else a word from this Short / a kana sound; never a review.
            // Brand-new learners: picture and the hiragana sound drill.
            // With the full word list this Short's captions can match words for a learner (then it gets
            // ordinary word cards, not the no-talking set), so only the new-learner run must see the screenshot question.
            // Live YouTube: caption loading varies, so sometimes this Short has learnable captions and
            // gets ordinary word cards instead. That run says nothing about the no-talking cards.
            let hadCaptionWords = wordCardsSeen > 0 || tags.contains("REMEMBER IT?")
            if hadCaptionWords { print("\(name): Short had caption words this run, no-talking checks skipped"); app.terminate(); continue }
            // No PICTURE requirement: this football frame often shows only people/background,
            // which are never asked about (by design), so there may be no picture question.
            XCTAssertFalse(tags.isEmpty, "\(name): no cards at all")
            if name == "new" { XCTAssertTrue(tags.contains("LISTEN"), "new: no kana drill, saw \(tags)") }
            // Learners: never a review of a word from an earlier Short (the kana drill may be the last-resort question).
            XCTAssertFalse(tags.contains("REVIEW"), "\(name): review card from an earlier Short shown")
            app.terminate()
        }
    }

    /// Questions stay about the Short on screen: a learner with a word due for review (met in an earlier Short)
    /// never gets a REVIEW card in the feed; the word waits for the dashboard's Review.
    func testNoReviewFromEarlierShorts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E", "-forceNonverbal", "-resetJourney", "-seedReview", "tired", "0"]
        app.launch()
        let option = app.buttons.matching(identifier: "recall-option").firstMatch
        var cards = 0
        for n in 0..<4 {
            guard waitForQuestion(app, timeout: n == 0 ? 30 : 15) else { break }
            sleep(1)
            cards += 1
            let review = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'REVIEW'")).firstMatch
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = "no-review-\(n)"; a.lifetime = .keepAlways; add(a)
            XCTAssertFalse(review.exists, "a review card for a word from an earlier Short was shown")
            if app.buttons["tile"].firstMatch.exists { app.buttons["I don't know"].tap() } else { option.tap() }
            let cont = app.buttons["continue"]
            if cont.waitForExistence(timeout: 5) { cont.tap() }
        }
        XCTAssertGreaterThan(cards, 0, "the Short asked no question at all")
    }
}

/// Plain new-word cards tapped through by `waitForQuestion` (the Short had learnable captions this time).
var wordCardsSeen = 0

/// Waits for a question card; taps through any plain new-word cards on the way.
func waitForQuestion(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let option = app.buttons.matching(identifier: "recall-option").firstMatch
    let word = app.buttons.matching(identifier: "word-button").firstMatch
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        // Answerable cards: multiple choice, spelling tiles or the say-it mic.
        if option.exists || app.buttons["tile"].firstMatch.exists || app.buttons["say-mic"].exists { return true }
        if word.exists {
            wordCardsSeen += 1
            word.tap()
            let cont = app.buttons["continue"]
            if cont.waitForExistence(timeout: 3) { cont.tap() }
        }
        sleep(1)
    }
    return option.exists
}

final class DashboardUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// Home · World · Place · Learn · Progress (Words / Impact / Rewards) with a seeded journey.
    func testJourneyTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-demoJourney"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["words-learned"].waitForExistence(timeout: 10), "no words-learned card")
        XCTAssertTrue(app.buttons["keep-scrolling"].exists)
        shot(app, "1-home")
        app.swipeUp(); sleep(1); shot(app, "1b-home-lower")

        XCTAssertTrue(app.descendants(matching: .any)["path-strip"].exists, "no path strip")
        app.swipeDown(); sleep(1)
        app.buttons["journey-map"].tap()
        XCTAssertTrue(app.buttons["open-place"].waitForExistence(timeout: 5), "no place sheet")
        sleep(1); shot(app, "2-world")
        app.buttons["open-place"].tap()
        XCTAssertTrue(app.buttons["fill-gaps"].waitForExistence(timeout: 5), "no place detail")
        sleep(1); shot(app, "3-place")
        app.buttons["fill-gaps"].tap()
        let option = app.buttons["practice-option"].firstMatch
        let tile = app.buttons["tile"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5) || tile.exists, "no practice")
        sleep(1); shot(app, "4-practice")
        if option.exists {
            option.tap()
            XCTAssertTrue(app.buttons["practice-continue"].waitForExistence(timeout: 3))
            shot(app, "4b-practice-answered")
        }
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 3), "practice didn't close")
        app.buttons["Done"].tap()
        sleep(1)
        app.navigationBars.buttons.firstMatch.tap()   // back from the full map to Home
        sleep(1)

        app.tabBars.buttons["Learn"].tap()
        XCTAssertTrue(app.buttons["learn-listening"].waitForExistence(timeout: 5), "no Learn skills")
        shot(app, "5-learn")

        app.tabBars.buttons["Progress"].tap()
        sleep(1); shot(app, "6-progress-words")
        app.segmentedControls.buttons["Impact"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["impact-week"].waitForExistence(timeout: 3))
        sleep(1); shot(app, "7-impact")
        app.swipeUp(); sleep(1); shot(app, "7b-impact-lower")
        app.segmentedControls.buttons["Rewards"].tap()
        sleep(1); shot(app, "8-rewards")
        app.swipeUp(); sleep(1); shot(app, "8b-rewards-lower")
        app.segmentedControls.buttons["Words"].tap()
        app.buttons["japanese-feed"].tap()
        sleep(1); shot(app, "9-japanese-feed")
    }

    /// Session recap: scroll → Japanese conversion, then a good stop opens Home.
    func testRecap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-recap", "-demoJourney", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["good-stop"].waitForExistence(timeout: 10), "no recap")
        sleep(1); shot(app, "recap")
        app.buttons["good-stop"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["words-learned"].waitForExistence(timeout: 5), "good stop didn't open Home")
    }

    /// An Upscroll original appears in the feed, is answerable and skippable.
    func testOriginalCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-forceOriginal", "-resetJourney", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let card = app.descendants(matching: .any)["original-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 30), "no original card")
        sleep(5)   // the Short underneath must stay paused while the card is open (see the app log)
        shot(app, "original")
        let option = app.buttons["practice-option"].firstMatch
        if option.exists {
            option.tap()
            if app.buttons["practice-continue"].waitForExistence(timeout: 3) {
                shot(app, "original-answered")
                app.buttons["practice-continue"].tap()
            }
        } else {
            app.buttons["original-skip"].tap()
        }
        XCTAssertFalse(card.waitForExistence(timeout: 2) && card.isHittable, "original still showing")
    }

    /// Settings: plan status + grouped sections; Review: the difficulty ladder mixes several practice types.
    func testSettingsAndReviewTypes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-resetWords", "-seedReviewSet"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 20), "no settings button")
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["plan-status"].waitForExistence(timeout: 5), "no plan status")
        sleep(1); shot(app, "s1-settings")
        app.swipeUp(); sleep(1); shot(app, "s2-settings-lower")
        app.swipeUp(); sleep(1); shot(app, "s3-settings-bottom")
        // Back to the top, then down until "Customize" is clear of the navigation bar.
        for _ in 0..<4 { app.swipeDown() }
        let customize = app.buttons["customize-scrolling"]
        for _ in 0..<6 where !(customize.isHittable && customize.frame.minY > 140) {
            app.swipeUp(velocity: .slow); sleep(1)
        }
        customize.tap()
        XCTAssertTrue(app.buttons["card-pace"].waitForExistence(timeout: 3) || app.descendants(matching: .any)["card-pace"].exists, "no customize page")
        sleep(1); shot(app, "s4-customize")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["home-quick-review"].waitForExistence(timeout: 5), "no quick review")
        app.buttons["home-quick-review"].tap()
        var seen = Set<String>()
        let names = ["Meaning", "Listening", "Pick the Japanese", "Fill the line", "Spell it", "Hear & spell", "Recall", "Say it", "Kana sounds"]
        for n in 0..<12 {
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 1) || app.staticTexts.matching(NSPredicate(format: "label IN %@", names)).firstMatch.waitForExistence(timeout: 5), "no question")
            if let k = names.first(where: { app.staticTexts[$0].exists }) { seen.insert(k) }
            shot(app, "r\(n)-question")
            if app.buttons["review-option"].firstMatch.exists {
                app.buttons["review-option"].firstMatch.tap()
            } else if app.buttons["tile"].firstMatch.exists {
                app.buttons["I don't know"].tap()
            } else if app.buttons["show-answer"].exists {
                app.buttons["show-answer"].tap()
                XCTAssertTrue(app.buttons["rate-hard"].waitForExistence(timeout: 3))
                app.buttons["rate-hard"].tap()
            } else if app.buttons["say-mic"].exists {
                app.buttons["Show answer"].tap()
            } else { break }
            XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 3), "no Next after answering")
            shot(app, "r\(n)-answered")
            app.buttons["Next"].tap()
            sleep(1)
        }
        print("REVIEW KINDS SEEN: \(seen.sorted())")
        XCTAssertGreaterThanOrEqual(seen.count, 4, "too few practice types: \(seen)")
    }
}

/// Question Lab: every feed card type, an original and the practice sandbox, screenshotted.
final class QuestionLabUITests: XCTestCase {
    /// Needs `npm run dev` in server/ (with SPEECHFY_API_KEY). Plays a phrase twice: fetched, then cached.
    func testNaturalVoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lab", "-resetJourney", "-lessonServer", "http://localhost:8787/"]
        app.launch()
        let play = app.buttons["lab-voice-phrase"]
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 10), "lab didn't open")
        let clear = app.buttons["lab-voice-clear"]
        for _ in 0..<14 where !(clear.exists && clear.isHittable) { app.swipeUp() }
        app.buttons["lab-voice-clear"].tap()
        play.tap()
        sleep(4)
        XCTAssertTrue(app.buttons["lab-voice-clear"].label.contains("(1 clips)"), "clip not cached: \(app.buttons["lab-voice-clear"].label)")
        play.tap()
        sleep(2)
    }

    func testEveryQuestionType() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-lab", "-forceNonverbal", "-resetJourney", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let shot = { (name: String) in
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; self.add(a)
        }
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 10), "lab didn't open")
        shot("0-lab")
        sleep(8)   // let the Short load so cards attach to it
        let only = ProcessInfo.processInfo.environment["LAB_CASES"]?.split(separator: ",").map(String.init)
        let cases = only ?? ["learn", "recall", "recallToJapanese", "listen", "pictureWhat", "pictureColor", "pictureWhich", "reviewToMeaning", "reviewToJapanese",
                             "reviewListen", "reviewSpell", "reviewSay"]
        for (i, c) in cases.enumerated() {
            if !app.buttons["lab-\(c)"].exists {
                app.buttons["dashboard-button"].press(forDuration: 1.0)
                XCTAssertTrue(app.buttons["lab-\(c)"].waitForExistence(timeout: 5), "lab didn't reopen for \(c)")
            }
            app.buttons["lab-\(c)"].tap()
            let word = app.buttons["word-button"], option = app.buttons.matching(identifier: "recall-option").firstMatch
            let tile = app.buttons.matching(identifier: "tile").firstMatch, mic = app.buttons["say-mic"]
            XCTAssertTrue(word.waitForExistence(timeout: 8) || option.exists || tile.exists || mic.exists, "\(c): no card")
            sleep(1); shot("\(i + 1)-\(c)-q")
            if tile.exists {
                tile.tap(); sleep(1); shot("\(i + 1)-\(c)-placed")
                app.buttons["I don't know"].tap()
            } else if mic.exists { app.buttons["Show answer"].tap() }
            else if option.exists { option.tap() } else { word.tap() }
            let cont = app.buttons["continue"]
            XCTAssertTrue(cont.waitForExistence(timeout: 5), "\(c): no continue")
            sleep(1); shot("\(i + 1)-\(c)-a")
            cont.tap()
            sleep(1)
        }
        // Original card for the chosen phrase/skill.
        app.buttons["dashboard-button"].press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["lab-original"].isHittable { app.swipeUp() }
        app.buttons["lab-original"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["original-card"].waitForExistence(timeout: 5), "no original")
        sleep(1); shot("9-original")
        app.buttons["original-skip"].tap()
        sleep(1)
        // Practice sandbox: one phrase, all four skills.
        app.buttons["dashboard-button"].press(forDuration: 1.0)
        let all = app.buttons["lab-phrase-all"]
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !(all.exists && all.isHittable) { app.swipeUp() }
        all.tap()
        for n in 1...4 {
            sleep(1); shot("10-practice-\(n)")
            app.buttons["Skip"].tap()
        }
        XCTAssertTrue(app.staticTexts["Done · 0 of 4 right"].waitForExistence(timeout: 3), "practice runner didn't finish")
    }

    /// Phrase from this Short (learn → build → saved to My phrases) and a lesson checkpoint card.
    /// Chunk / pattern rung: notice → guided pick, cloze, build; then the ladder card in Progress.
    func testGrammarCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetJourney", "-lab", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        func open(_ id: String) {
            if !app.buttons["lab-learn"].exists { app.buttons["dashboard-button"].press(forDuration: 1.0) }
            XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 20), "no lab")
            for _ in 0..<10 where !(app.buttons[id].exists && app.buttons[id].isHittable) { app.swipeUp() }
            app.buttons[id].tap()
            XCTAssertTrue(app.otherElements["grammar-card"].waitForExistence(timeout: 8) || app.buttons["grammar-skip"].waitForExistence(timeout: 2), "no grammar card for \(id)")
        }
        open("lab-grammar-notice")
        sleep(1); shot("1-grammar-notice")
        XCTAssertTrue(app.buttons["grammar-try"].exists, "no Try it")
        XCTAssertTrue(app.otherElements["grammar-words"].exists || app.staticTexts["ramen"].exists || app.descendants(matching: .any)["grammar-words"].exists,
                      "no word translations on the grammar card")
        app.buttons["grammar-try"].tap()
        let opt = app.buttons.matching(identifier: "grammar-option")
        XCTAssertTrue(opt.firstMatch.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(opt.count, 3, "cloze needs the piece + 2 wrong options")
        shot("2-grammar-cloze-guided")
        opt.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["grammar-continue"].waitForExistence(timeout: 3))
        shot("3-grammar-result")
        app.buttons["grammar-continue"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["grammar-continue"].exists, "card didn't close")
        open("lab-grammar-build")
        let tile = app.buttons.matching(identifier: "tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 3) || app.buttons["grammar-check"].exists, "no build tiles")
        shot("4-grammar-build")
        app.buttons["grammar-skip"].tap()
    }

    func testShortPhraseAndLessonCards() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetJourney", "-lab", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        func shot(_ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 20), "no lab")
        for _ in 0..<8 where !(app.buttons["lab-shortPhrase"].exists && app.buttons["lab-shortPhrase"].isHittable) { app.swipeUp() }
        app.buttons["lab-shortPhrase"].tap()
        XCTAssertTrue(app.buttons["phrase-build"].waitForExistence(timeout: 8), "no phrase card")
        sleep(1); shot("1-phrase-intro")
        app.buttons["phrase-build"].tap()
        let tile = app.buttons.matching(identifier: "tile").firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "no build tiles")
        shot("2-phrase-build")
        app.buttons["original-skip"].tap()
        // Saved to My phrases (a skip after reading still keeps it): relaunch straight into the dashboard.
        sleep(1)
        app.terminate()
        app.launchArguments = ["-dashboard", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let mine = app.buttons["my-phrases"]
        XCTAssertTrue(app.buttons["keep-scrolling"].waitForExistence(timeout: 15), "no dashboard")
        for _ in 0..<5 where !(mine.exists && mine.isHittable) { app.swipeUp() }
        XCTAssertTrue(mine.exists, "phrase not saved to My phrases")
        sleep(1); shot("3-home-my-phrases")
        mine.tap()
        sleep(1); shot("4-phrase-list")
        app.navigationBars.buttons.firstMatch.tap()
        app.swipeDown(); app.swipeDown(); sleep(1); shot("5-home-top")
        // Lesson frame
        app.terminate()
        app.launchArguments = ["-lab", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 20), "lab didn't open")
        for _ in 0..<8 where !(app.buttons["lab-lesson"].exists && app.buttons["lab-lesson"].isHittable) { app.swipeUp() }
        app.buttons["lab-lesson"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["lesson-card"].waitForExistence(timeout: 8), "no lesson card")
        sleep(1); shot("6-lesson-card")
    }

    /// First-run onboarding: language → level → demo → goal → trial, then the feed.
    func testOnboardingFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20), "no onboarding")
        func shot(_ name: String) {
            sleep(1)
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
            if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
                try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
        shot("0-welcome"); next.tap()
        XCTAssertTrue(app.buttons["lang-ja"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lang-es"].isEnabled, "unsupported language is selectable")
        shot("1-language"); next.tap()
        XCTAssertTrue(app.buttons["why-travel"].waitForExistence(timeout: 5))
        app.buttons["why-travel"].tap()
        shot("1b-why"); next.tap()
        XCTAssertTrue(app.buttons["level-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["level-0"].exists, "romaji-only level is back")
        app.buttons["level-1"].tap()
        shot("2-level"); next.tap()
        XCTAssertTrue(app.otherElements["feed-demo"].waitForExistence(timeout: 5) || app.staticTexts["Just keep scrolling"].exists)
        shot("3-demo"); sleep(2); shot("3b-demo"); sleep(2); shot("3c-demo"); next.tap()
        XCTAssertTrue(app.buttons["goal-20"].waitForExistence(timeout: 5))
        app.buttons["goal-20"].tap()
        shot("4-goal"); next.tap()
        shot("5-trial")
        next.tap()
        XCTAssertFalse(next.waitForExistence(timeout: 3) && next.isHittable, "onboarding didn't close")
    }

    /// "Check your email": six code boxes + Open Mail (shown without sending a real email).
    func testCheckEmailScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-demoJourney", "-previewCheckEmail", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["open-sign-in"].waitForExistence(timeout: 10))
        app.buttons["open-sign-in"].tap()
        let field = app.textFields["code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no code boxes")
        XCTAssertTrue(app.buttons["open-mail"].exists, "no Open Mail")
        XCTAssertFalse(app.buttons["verify-code"].isEnabled, "Verify enabled with no code")
        field.tap(); field.typeText("123")   // 3 digits only: a full code would submit to the server
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "check-email"; a.lifetime = .keepAlways; add(a)
    }

    /// Cloud save: with Supabase configured, Settings offers sign-in and the sheet shows both methods.
    func testSignInSheetAppears() {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-demoJourney", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 20), "no settings button")
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["open-sign-in"].waitForExistence(timeout: 10), "no sign-in row")
        app.buttons["open-sign-in"].tap()
        XCTAssertTrue(app.textFields["email-field"].waitForExistence(timeout: 10), "no email field")
        XCTAssertTrue(app.buttons["send-code"].exists, "no send-code button")
        XCTAssertFalse(app.buttons["send-code"].isEnabled, "Continue enabled with no email")
        XCTAssertTrue(app.descendants(matching: .any)["sign-in-gift"].exists, "no sign-in gift offered")
        let shot = { (n: String) in let a = XCTAttachment(screenshot: app.screenshot()); a.name = n; a.lifetime = .keepAlways; self.add(a) }
        sleep(1); shot("signin-1-empty")
        app.textFields["email-field"].typeText("learner@example")
        XCTAssertFalse(app.buttons["send-code"].isEnabled, "Continue enabled for an invalid email")
        app.textFields["email-field"].typeText(".com")
        XCTAssertTrue(app.buttons["send-code"].isEnabled, "Continue disabled for a valid email")
        shot("signin-2-valid")   // not tapped: that would send a real email
        XCTAssertFalse(app.buttons["apple-sign-in"].exists, "Apple sign-in was removed")
        // The upscroll:// link from the email reaches the app, and a bad link explains itself.
        // Hand the link to the running app the way Mail does (app.open relaunches the app and loses the sheet).
        XCUIDevice.shared.system.open(URL(string: "upscroll://auth-callback?error_description=Email+link+is+invalid+or+has+expired")!)
        let openButton = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if openButton.waitForExistence(timeout: 3) { openButton.tap() }
        XCTAssertTrue(app.staticTexts["sign-in-error"].waitForExistence(timeout: 10), "deep link not handled")
        XCTAssertEqual(app.staticTexts["sign-in-error"].label, "Email link is invalid or has expired")
    }

    /// Speaking question: tapping the mic must never crash, even when the simulator/mic gives no input format.
    func testSpeakingQuestionDoesNotCrash() {
        let app = XCUIApplication()
        app.launchArguments = ["-lab", "-resetJourney", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "permissions") { alert in
            for b in ["Allow", "OK", "Allow While Using App"] where alert.buttons[b].exists { alert.buttons[b].tap(); return true }
            return false
        }
        XCTAssertTrue(app.buttons["lab-learn"].waitForExistence(timeout: 20), "no lab")
        for _ in 0..<6 where !(app.buttons["lab-reviewSay"].exists && app.buttons["lab-reviewSay"].isHittable) { app.swipeUp() }
        app.buttons["lab-reviewSay"].tap()
        let mic = app.buttons["say-mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "no say-it card")
        mic.tap()
        // Permission prompts come from SpringBoard; accept them so the mic really starts.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allow = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "OK"])).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() } else { break }
        }
        app.tap()   // lets the interruption monitor run if an alert is still up
        sleep(4)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "speaking-after-mic"; a.lifetime = .keepAlways; add(a)
        XCTAssertEqual(app.state, .runningForeground, "app crashed after tapping the mic")
        XCTAssertTrue(mic.exists || app.buttons["continue"].exists, "speaking card vanished")
    }

    /// Home shows how long until kana practice is done / the next practice type unlocks;
    /// finishing kana practice in the feed shows the unlock celebration.
    func testUnlockProgressAndCelebration() {
        let app = XCUIApplication()
        // 43 of 44 sounds already right: the next drill is the last one (わ).
        app.launchArguments = ["-lab", "-resetJourney", "-kanaKnown", "43", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        func shot(_ n: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = n; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(app.buttons["lab-listen"].waitForExistence(timeout: 20), "no lab")
        app.buttons["lab-listen"].tap()
        let answer = app.buttons.matching(NSPredicate(format: "identifier == 'recall-option' AND label CONTAINS 'わ'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "no kana drill with わ")
        sleep(1); shot("unlock-1-last-kana")
        answer.tap()
        let cont = app.buttons["continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        cont.tap()
        let party = app.descendants(matching: .any)["unlock-celebration"]
        XCTAssertTrue(party.waitForExistence(timeout: 5), "no unlock celebration after finishing kana")
        usleep(600_000); shot("unlock-2-celebration")
        XCTAssertTrue(app.staticTexts["Kana sounds complete!"].exists, "wrong unlock message")
        // It closes by itself.
        XCTAssertFalse(party.waitForExistence(timeout: 1) && party.isHittable && { sleep(5); return party.exists }(), "celebration didn't close")
        // Home: the next unlock (Chunks) with its progress and time estimate; kana is done so no kana row.
        app.terminate()
        app.launchArguments = ["-dashboard", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let card = app.descendants(matching: .any)["next-unlock"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no next-unlock card on Home")
        for _ in 0..<3 where !card.isHittable { app.swipeUp() }
        sleep(1); shot("unlock-3-home")
        XCTAssertTrue(card.label.contains("Chunks") || app.staticTexts["Chunks"].exists, "next unlock isn't Chunks")
        // Kana half done: the track shows it on the same card.
        app.terminate()
        app.launchArguments = ["-dashboard", "-resetJourney", "-kanaKnown", "18", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        for _ in 0..<3 where !card.isHittable { app.swipeUp() }
        sleep(1); shot("unlock-4-home-kana-18")
        XCTAssertTrue(app.descendants(matching: .any)["kana-track"].firstMatch.label.contains("18 of 44"), "kana progress not shown")
        // The full picture (preview, kana tiles, path) is one tap away, in Progress.
        card.tap()
        let detail = app.descendants(matching: .any)["unlock-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5), "card didn't open the full unlock view in Progress")
        sleep(1); shot("unlock-5-progress-detail")
    }

    /// While scrolling: a milestone message (here: the 10th kana sound) slides in over the feed.
    func testProgressNudgeInFeed() {
        let app = XCUIApplication()
        app.launchArguments = ["-lab", "-resetJourney", "-kanaKnown", "9", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["lab-listen"].waitForExistence(timeout: 20), "no lab")
        app.buttons["lab-listen"].tap()
        let answer = app.buttons.matching(NSPredicate(format: "identifier == 'recall-option' AND label CONTAINS 'こ'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10), "no kana drill with こ")
        answer.tap()
        XCTAssertTrue(app.buttons["continue"].waitForExistence(timeout: 5))
        app.buttons["continue"].tap()
        let nudge = app.descendants(matching: .any)["progress-nudge"]
        XCTAssertTrue(nudge.waitForExistence(timeout: 3), "no milestone message after the 10th kana")
        usleep(700_000)
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "nudge-kana-10"; a.lifetime = .keepAlways; add(a)
        // Which milestone wins depends on saved progress (unlock % beats kana); any of them is right here.
        XCTAssertTrue(["10 of 44", "% to unlock", "new words today", "Daily goal"].contains { nudge.label.contains($0) },
                      "unexpected message: \(nudge.label)")
        sleep(4)
        XCTAssertFalse(nudge.exists, "message didn't leave")
    }

    /// Home: a sign-in card right under Review (with the gift) opens the sign-in sheet.
    func testHomeSignInCard() {
        let app = XCUIApplication()
        // "-signInCardHiddenUntil 0": a "Not now" from an earlier run must not hide the card.
        app.launchArguments = ["-dashboard", "-demoJourney", "-resetWords", "-seedReviewSet", "-signInCardHiddenUntil", "0",
                               "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        let card = app.descendants(matching: .any)["sign-in-nudge"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "no sign-in card on Home")
        let review = app.buttons["home-quick-review"]
        if review.exists { XCTAssertLessThan(review.frame.maxY, card.frame.minY, "sign-in card isn't under Review") }
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "home-sign-in-card"; a.lifetime = .keepAlways; add(a)
        app.buttons["home-sign-in"].tap()
        XCTAssertTrue(app.textFields["email-field"].waitForExistence(timeout: 10), "sign-in sheet didn't open")
    }

    /// The email can't be sent (server error): a plain message, not the server's text. No real email is sent.
    func testSignInEmailFailureMessage() {
        let app = XCUIApplication()
        app.launchArguments = ["-dashboard", "-demoJourney", "-fakeSendFailure", "-startURL", "https://m.youtube.com/shorts/SyxBTFf0U1E"]
        app.launch()
        XCTAssertTrue(app.buttons["open-settings"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["open-sign-in"].waitForExistence(timeout: 10))
        app.buttons["open-sign-in"].tap()
        XCTAssertTrue(app.textFields["email-field"].waitForExistence(timeout: 10))
        app.textFields["email-field"].typeText("learner@example.com")
        app.buttons["send-code"].tap()
        let err = app.staticTexts["sign-in-error"]
        XCTAssertTrue(err.waitForExistence(timeout: 5), "no error shown")
        XCTAssertTrue(err.label.hasPrefix("We couldn't send the sign-in email"), "unexpected: \(err.label)")
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = "signin-send-failure"; a.lifetime = .keepAlways; add(a)
    }
}
