import Testing
@testable import Cyclop

@MainActor
struct TranslatorTests {
    private func make() -> Translator { Translator(targetCode: "auto", persistTarget: { _ in }) }

    @Test func typingInvalidatesOldTranslationBeforeDebounce() {
        let translator = make()
        translator.input = "Hello"
        #expect(translator.request == nil)
        #expect(!translator.isTranslating)
        translator.requestTranslation()
        #expect(translator.request?.text == "Hello")
        #expect(translator.isTranslating)
        translator.input = "New text"
        #expect(translator.request == nil)
        #expect(!translator.isTranslating)
        #expect(translator.output.isEmpty)
    }
    @Test func changedLanguageInvalidatesPendingRequest() {
        let translator = make()
        translator.input = "Hello"
        translator.requestTranslation()
        translator.targetCode = "fr"
        #expect(translator.request == nil)
        #expect(translator.route.target.languageCode?.identifier == "fr")
        translator.requestTranslation()
        #expect(translator.request?.route.target.languageCode?.identifier == "fr")
    }
    @Test func shortRussianWordKeepsRussianRoute() {
        let route = Translator.route(for: "привет")
        #expect(route.source.languageCode?.identifier == "ru")
        #expect(route.target.languageCode?.identifier == "en")
    }
    @Test func sameLanguageUsesInputWithoutSession() {
        let translator = make()
        translator.sourceCode = "en"
        translator.targetCode = "en"
        translator.input = "  Hello  "
        translator.requestTranslation()
        #expect(translator.output == "Hello")
        #expect(translator.request == nil)
        #expect(!translator.isTranslating)
        translator.swapLanguages()
        #expect(translator.input == "Hello")
        #expect(translator.output.isEmpty)
    }
    @Test func whitespaceAndResetNeverStartWork() {
        let translator = make()
        translator.input = " \n "
        translator.requestTranslation()
        #expect(translator.request == nil)
        translator.input = "Hello"
        translator.requestTranslation()
        translator.reset()
        #expect(translator.request == nil)
        #expect(translator.input.isEmpty)
        #expect(!translator.isTranslating)
    }
    @Test func translatesAutomaticallyAfterPause() async {
        let translator = make()
        translator.input = "Hello"
        await translator.translateAfterPause(for: translator.draft, delay: .milliseconds(10))
        #expect(translator.request?.text == "Hello")
        #expect(translator.isTranslating)
    }
    @Test func changedDraftNeverSubmitsOldText() async {
        let translator = make()
        translator.input = "Old text"
        let old = translator.draft
        translator.input = "New text"
        await translator.translateAfterPause(for: old, delay: .milliseconds(10))
        #expect(translator.request == nil)
        await translator.translateAfterPause(for: translator.draft, delay: .milliseconds(10))
        #expect(translator.request?.text == "New text")
    }
    @Test func leavingPaneCancelsAutomaticTranslation() async {
        let translator = make()
        translator.input = "Hello"
        let task = Task { await translator.translateAfterPause(for: translator.draft, delay: .seconds(1)) }
        task.cancel()
        await task.value
        #expect(translator.request == nil)
        #expect(!translator.isTranslating)
    }

}
