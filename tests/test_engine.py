from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from novel_ime import HistoryEntry, NovelTextEngine


class NovelTextEngineTests(unittest.TestCase):
    def test_normalizes_paragraphs_and_whitespace(self) -> None:
        engine = NovelTextEngine(
            text="  第一段\t  有  多余空白  \n\n第二段\r\n  仍然   会  归一化  \n\n\n  第三段  "
        )

        self.assertEqual(
            engine.paragraphs,
            ("第一段 有 多余空白", "第二段 仍然 会 归一化", "第三段"),
        )
        self.assertEqual(engine.paragraph_index, 0)
        self.assertEqual(engine.char_index, 0)
        self.assertTrue(engine.has_remaining_text())
        self.assertAlmostEqual(engine.progress, 0.0)

    def test_emit_on_space_advances_character_by_character(self) -> None:
        engine = NovelTextEngine(text="AB\n\nCD")

        self.assertEqual(engine.emit_on_space(), "A")
        self.assertEqual(engine.paragraph_index, 0)
        self.assertEqual(engine.char_index, 1)
        self.assertAlmostEqual(engine.progress, 1 / 5)
        self.assertEqual(len(engine.history), 1)
        self.assertIsInstance(engine.history[-1], HistoryEntry)

        self.assertEqual(engine.emitOnSpace(), "B")
        self.assertEqual(engine.char_index, 2)
        self.assertAlmostEqual(engine.progress, 2 / 5)
        self.assertEqual(engine.emit_on_space(), "")
        self.assertTrue(engine.has_remaining_text())

    def test_emit_on_return_jumps_to_next_paragraph_and_inserts_newline(self) -> None:
        engine = NovelTextEngine(text="AB\n\nCD")

        self.assertEqual(engine.emit_on_space(), "A")
        self.assertEqual(engine.emit_on_return(), "\n")
        self.assertEqual(engine.paragraph_index, 1)
        self.assertEqual(engine.char_index, 0)
        self.assertAlmostEqual(engine.progress, 3 / 5)
        self.assertTrue(engine.has_remaining_text())

        self.assertEqual(engine.emitOnSpace(), "C")
        self.assertEqual(engine.emitOnReturn(), "\n")
        self.assertEqual(engine.paragraph_index, 1)
        self.assertEqual(engine.char_index, 2)
        self.assertFalse(engine.has_remaining_text())
        self.assertAlmostEqual(engine.progress, 1.0)
        self.assertEqual(engine.emit_on_return(), "")

    def test_rewind_last_restores_previous_state_for_space_and_return(self) -> None:
        engine = NovelTextEngine(text="AB\n\nCD")

        self.assertEqual(engine.emit_on_space(), "A")
        self.assertEqual(engine.emit_on_return(), "\n")
        self.assertEqual(engine.paragraph_index, 1)
        self.assertEqual(engine.char_index, 0)

        self.assertEqual(engine.rewind_last(), "\n")
        self.assertEqual(engine.paragraph_index, 0)
        self.assertEqual(engine.char_index, 1)
        self.assertAlmostEqual(engine.progress, 1 / 5)
        self.assertTrue(engine.hasRemainingText())

        self.assertEqual(engine.rewindLast(), "A")
        self.assertEqual(engine.paragraph_index, 0)
        self.assertEqual(engine.char_index, 0)
        self.assertAlmostEqual(engine.progress, 0.0)
        self.assertEqual(engine.rewind_last(), "")

    def test_empty_source_has_no_remaining_text_and_progress_is_complete(self) -> None:
        engine = NovelTextEngine(text="   \n\n\t")

        self.assertEqual(engine.paragraphs, ())
        self.assertFalse(engine.has_remaining_text())
        self.assertAlmostEqual(engine.progress, 1.0)
        self.assertEqual(engine.emit_on_space(), "")
        self.assertEqual(engine.emit_on_return(), "")
        self.assertEqual(engine.rewind_last(), "")

    def test_load_source_converts_rtf_disguised_as_txt(self) -> None:
        rtf_text = (
            "{\\rtf1\\ansi\\ansicpg936\\cocoartf2822 "
            "\\uc0\\u25105 \\u29233 \\u20320 }"
        )
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "sample.txt"
            path.write_text(rtf_text, encoding="utf-8")

            engine = NovelTextEngine(source_path=path)

        self.assertEqual(engine.paragraphs, ("我爱你",))
        self.assertEqual(engine.emit_on_space(), "我")


if __name__ == "__main__":
    unittest.main()
