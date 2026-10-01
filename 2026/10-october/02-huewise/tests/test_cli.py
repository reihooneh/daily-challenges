import io
import json
import os
import tempfile
import time
import unittest

from huewise.cli import MAX_CSS_BYTES, extract_css_colors, run


def cli(*args):
    out, err = io.StringIO(), io.StringIO()
    code = run(list(args), out, err)
    return code, out.getvalue(), err.getvalue()


class CliTests(unittest.TestCase):
    def test_exit_codes(self):
        self.assertEqual(cli("#000", "#fff")[0], 0)
        self.assertEqual(cli("#d62728", "#2ca02c")[0], 1)
        self.assertEqual(cli("#000")[0], 2)
        self.assertEqual(cli("#000", "banana")[0], 2)

    def test_human_output_explains_and_fixes(self):
        code, out, _ = cli("#d62728", "#2ca02c", "--no-color")
        self.assertEqual(code, 1)
        for text in ["deuteranopia", "fix: change #2ca02c", "Re-checked: the repaired palette has no collisions"]:
            self.assertIn(text, out)
        self.assertNotIn("\x1b[", out)

    def test_json_output(self):
        code, out, _ = cli("#d62728", "#2ca02c", "--json")
        data = json.loads(out)
        self.assertEqual(code, 1)
        self.assertFalse(data["ok"])
        self.assertEqual(data["remaining_after_fixes"], 0)
        self.assertEqual(len(data["repaired_palette"]), 2)

    def test_contrast_mode(self):
        code, out, _ = cli("--contrast", "#000", "#fff")
        self.assertEqual(code, 0)
        self.assertIn("21.00:1", out)
        self.assertIn("AAA", out)

    def test_duplicates_and_short_forms_collapse(self):
        code, _, err = cli("#fff", "#FFFFFF", "#ffffff")
        self.assertEqual(code, 2)
        self.assertIn("at least two", err)


class CssTests(unittest.TestCase):
    def test_extracts_colours_from_declarations_only(self):
        css = """
        #add, #fed { color: #D62728; background: #2ca02c url(x.png); }
        :root { --brand: #abc; }
        @media (min-width: 10px) { a:hover { border: 1px solid #d62728 } }
        """
        self.assertEqual(extract_css_colors(css), ["#d62728", "#2ca02c", "#aabbcc"])

    def test_css_file_end_to_end(self):
        with tempfile.NamedTemporaryFile("w", suffix=".css", delete=False) as f:
            f.write(".ok{color:#2ca02c}.err{color:#d62728}")
        try:
            code, out, _ = cli("--css", f.name, "--no-color")
            self.assertEqual(code, 1)
            self.assertIn("1 collision", out)
        finally:
            os.unlink(f.name)


class HostileInputTests(unittest.TestCase):
    def test_missing_directory_and_oversized_files_are_refused(self):
        self.assertEqual(cli("--css", "/no/such/file.css")[0], 2)
        self.assertEqual(cli("--css", tempfile.gettempdir())[0], 2)
        with tempfile.NamedTemporaryFile("w", suffix=".css", delete=False) as f:
            f.write("a{color:#fff}" + " " * (MAX_CSS_BYTES + 1))
        try:
            code, _, err = cli("--css", f.name)
            self.assertEqual(code, 2)
            self.assertIn("refusing", err)
        finally:
            os.unlink(f.name)

    def test_too_many_colours_in_css(self):
        css = "a{" + "".join(f"c:#{i:06x};" for i in range(0, 200 * 4099, 4099)) + "}"
        with tempfile.NamedTemporaryFile("w", suffix=".css", delete=False) as f:
            f.write(css)
        try:
            code, _, err = cli("--css", f.name)
            self.assertEqual(code, 2)
            self.assertIn("limit", err)
        finally:
            os.unlink(f.name)

    def test_pathological_text_is_handled_quickly(self):
        # Inputs built to make naive regexes take exponential time.
        for text in ["{" * 200_000, ":" * 200_000, "{:" + "#" * 200_000, "{a:" + "#ffffff" * 30_000 + "x"]:
            start = time.perf_counter()
            extract_css_colors(text)
            self.assertLess(time.perf_counter() - start, 2.0)

    def test_binary_and_invalid_utf8_do_not_crash(self):
        with tempfile.NamedTemporaryFile("wb", suffix=".css", delete=False) as f:
            f.write(b"\xff\xfe\x00a{color:#000;b:#fff}\x00\xc3")
        try:
            self.assertEqual(cli("--css", f.name)[0], 0)
        finally:
            os.unlink(f.name)

    def test_shell_and_script_text_is_just_rejected(self):
        for evil in ["$(rm -rf /)", "`id`", "#fff; DROP TABLE", "<script>alert(1)</script>", "../../etc/passwd"]:
            code, out, err = cli("#000", evil)
            self.assertEqual(code, 2)
            self.assertEqual(out, "")
            self.assertTrue(err.startswith("huewise:"))


if __name__ == "__main__":
    unittest.main()
