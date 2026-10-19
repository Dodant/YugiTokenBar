#!/usr/bin/env python3
"""Static Linux localization checks, without invoking the macOS compiler."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("sync_strings", Path(__file__).with_name("sync-strings.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class LinuxKeysTests(unittest.TestCase):
    def scan(self, source):
        return sync.linux_keys(source, "LinuxView.swift")

    def test_comments_ordinary_strings_and_function_declaration_are_not_calls(self):
        source = '''// L("무시")
        /* outer /* L("무시") */ comment */
        let x = "L(\\\"무시\\\")"
        func L(_ key: StaticString) {}
        let y = L("실제")
        '''
        self.assertEqual(self.scan(source), {"실제": ["LinuxView.swift:5"]})

    def test_escapes_nested_arguments_and_multiple_calls(self):
        source = r'''L("카드 \"%2$@\" %1$lld\n100%%", .int(count(1, f(2))), .text(name("x,y"))); L("다음")'''
        self.assertEqual(set(self.scan(source)), {'카드 "%2$@" %1$lld\n100%%', "다음"})

    def test_positional_repeated_argument(self):
        self.assertEqual(set(self.scan('L("%1$lld장 / %1$lld장", .int(n))')), {"%1$lld장 / %1$lld장"})

    def test_nonliteral_and_unsupported_keys_fail_instead_of_disappearing(self):
        for source in ['L(key)', 'L("키" + suffix)', r'L("카드 \(n)")',
                       'L(#"카드"#)', 'L("""카드""")', 'L("키", values)']:
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, "LinuxView.swift:1"):
                self.scan(source)

    def test_argument_count_type_and_specifier_errors(self):
        for source in ['L("%lld장")', 'L("%lld장", .text(name))',
                       'L("%@장", .int(n))', 'L("키", .int(n))',
                       'L("%0$lld장", .int(n))', 'L("%2$lld장", .int(n))',
                       'L("%d장", .int(n))', 'L("%lld장", .int())',
                       'L("%lld장", .int(n), .text(x))']:
            with self.subTest(source=source), self.assertRaises(ValueError):
                self.scan(source)

    def test_nested_interpolation_strings_do_not_create_fake_calls(self):
        source = r'''let label = "\(other("L(\"가짜\")"))"; L("진짜")'''
        self.assertEqual(set(self.scan(source)), {"진짜"})

    def test_executable_interpolation_calls_are_collected_with_real_locations(self):
        source = 'let label = "prefix\\(\n L("무료 카드 %lld장", .int(count)))"'
        self.assertEqual(self.scan(source), {"무료 카드 %lld장": ["LinuxView.swift:2"]})

    def test_bare_linux_literal_cannot_borrow_a_key_from_other_sources(self):
        for filename, source in [("LinuxView.swift", 'Text("버그 신고")'),
                                 ("Shared.swift", '#if os(Linux)\nText("버그 신고")\n#endif'),
                                 ("Shared.swift", '#if os(Linux)\n#if DEBUG\n#else\nText("버그 신고")\n#endif\n#endif'),
                                 ("Shared.swift", '#if os(Linux) && DEBUG\nText("버그 신고")\n#endif')]:
            with tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / filename
                path.write_text(source)
                self.assertEqual(len(sync.stray_literals([str(path)], {"버그 신고": ["MacView.swift:1"]})), 1)

    def test_platform_condition_boolean_branches(self):
        source = ('#if os(macOS)\nmac1\n#elseif os(Linux) && !DEBUG\nlinux1\n#else\nlinux2\n#endif\n'
                  '#if os(Linux) && (DEBUG || canImport(Foo))\nlinux3\n#endif\n'
                  '#if os(Linux)\n#if DEBUG\nlinux4\n#else\nlinux5\n#endif\n#endif')
        lines = sync.linux_only_lines(source, "Shared.swift")
        self.assertEqual({source.splitlines()[n - 1] for n in lines}, {"linux1", "linux2", "linux3", "linux4", "linux5"})

    def test_platform_directives_ignore_comments_and_string_contents(self):
        source = '/*\n#if os(Linux)\n*/\ncommon1\nlet s = """\n#if os(Linux)\n"""\ncommon2\n#if os(Linux) // real\nlinux\n#endif'
        self.assertEqual(sync.linux_only_lines(source, "Shared.swift"), {10})

    def test_shared_swiftui_literal_and_multiline_key_keep_existing_support(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "MacView.swift"
            path.write_text('Text("버그 신고"); String(localized: """\n    첫 줄\\(n)\n    둘째 줄\n    """)')
            self.assertEqual(sync.stray_literals([str(path)], {"버그 신고": [], "첫 줄%lld\n둘째 줄": []}), [])

    def test_stray_literals_normalize_escapes_and_format_specifiers(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "LinuxView.swift"
            path.write_text(r'''L("카드 \"%@\" %lld\n", .text(name), .int(n))
            let stray = "번역 누락"
            // "주석"
            /* "주석" */
            ''')
            keys = self.scan(path.read_text())
            result = sync.stray_literals([str(path)], keys)
            self.assertEqual(len(result), 1)
            self.assertIn("번역 누락", result[0])

    def test_escaped_percent_is_not_an_argument(self):
        self.assertEqual(set(self.scan('L("진행 100%% / %%lld")')), {"진행 100%% / %%lld"})
        self.assertEqual(sync.specs("100%% / %%lld / %lld"), sync.specs("%1$lld / %1$lld / 100%%"))
        self.assertNotEqual(sync.specs("%lld / %@"), sync.specs("%1$@ / %2$lld"))
        self.assertFalse(sync.needs_plural("%%lld cards"))
        self.assertTrue(sync.needs_plural("%%%lld cards"))

    def test_unescape_preserves_literal_backslash_before_n(self):
        self.assertEqual(sync.unescape(r'카드 \\n \n \" \u{AC00}'), '카드 \\n \n " 가')


if __name__ == "__main__":
    unittest.main()
