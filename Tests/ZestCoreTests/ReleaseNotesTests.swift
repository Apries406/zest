import Testing
@testable import ZestCore

@Suite struct ReleaseNotesTests {
    let changelog = """
    # Changelog

    ## 0.1.2 — 2026-11-16

    - New spec: `tofu` (OpenTofu), with workspace suggestions. Thanks to
      @chen-xiao-yuan for the first community contribution! (#4)
    - Fixed `composer` suggestions on older macOS versions.

    ## 0.1.1 — 2026-11-15

    - Older entry.
    """

    @Test func findsTheVersionSection() {
        let section = ReleaseNotes.section(changelog, version: "0.1.2")
        #expect(section?.hasPrefix("- New spec") == true)
        #expect(section?.contains("Older entry") == false)
        #expect(ReleaseNotes.section(changelog, version: "9.9.9") == nil)
    }

    @Test func summaryIsShortPlainText() {
        let summary = ReleaseNotes.summary(ReleaseNotes.section(changelog, version: "0.1.2")!)
        #expect(summary == """
        • New spec: tofu (OpenTofu), with workspace suggestions.
        • Fixed composer suggestions on older macOS versions.
        """)
    }

    @Test func dropsGitHubGeneratedNoise() {
        let generated = """
        ## What's Changed
        * Add a spec for OpenTofu (tofu) by @rostik32 in https://github.com/rostik32/zest/pull/10

        ## New Contributors
        * @rostik32 made their first contribution in https://github.com/rostik32/zest/pull/10

        **Full Changelog**: https://github.com/rostik32/zest/compare/v0.1.1...v0.1.2
        """
        let summary = ReleaseNotes.summary(generated)
        #expect(summary == "• Add a spec for OpenTofu (tofu)")
        #expect(!summary.contains("http"))
        #expect(!summary.contains("@"))
        #expect(!summary.contains("contribution"))
    }

    @Test func keepsVersionsAndAbbreviationsWhole() {
        #expect(ReleaseNotes.summary("- Non-ASCII history (e.g. Cyrillic) works in 0.1.2. More details here.")
            == "• Non-ASCII history (e.g. Cyrillic) works in 0.1.2.")
    }

    @Test func limitsTheNumberOfLines() {
        let notes = (1...6).map { "- Change \($0)." }.joined(separator: "\n")
        let summary = ReleaseNotes.summary(notes, maxItems: 4)
        #expect(summary.split(separator: "\n").count == 5)
        #expect(summary.hasSuffix("…and 2 more changes"))
    }
}
