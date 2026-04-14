from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import subprocess
from typing import Literal


ActionKind = Literal["space", "return"]


@dataclass(frozen=True, slots=True)
class HistoryEntry:
    action: ActionKind
    output: str
    previous_paragraph_index: int
    previous_char_index: int
    next_paragraph_index: int
    next_char_index: int


class NovelTextEngine:
    def __init__(self, text: str = "", source_path: str | Path | None = None) -> None:
        self.source_path: Path | None = None
        self._raw_text = ""
        self._paragraphs: list[str] = []
        self.paragraph_index = 0
        self.char_index = 0
        self.history: list[HistoryEntry] = []
        self.progress = 1.0

        if source_path is not None:
            self.load_source(source_path)
        else:
            self.load_text(text)

    @staticmethod
    def _normalize_paragraphs(text: str) -> list[str]:
        if not text:
            return []

        normalized = text.replace("\r\n", "\n").replace("\r", "\n")
        raw_paragraphs = re.split(r"\n\s*\n+", normalized)
        paragraphs: list[str] = []
        for paragraph in raw_paragraphs:
            cleaned = " ".join(paragraph.split())
            if cleaned:
                paragraphs.append(cleaned)
        return paragraphs

    @property
    def paragraphs(self) -> tuple[str, ...]:
        return tuple(self._paragraphs)

    @property
    def paragraph_count(self) -> int:
        return len(self._paragraphs)

    @property
    def current_paragraph_length(self) -> int:
        paragraph = self._current_paragraph()
        return len(paragraph) if paragraph is not None else 0

    def load_text(self, text: str) -> None:
        self.source_path = None
        self._set_text(text)

    def load_source(self, path: str | Path) -> None:
        source_path = Path(path).expanduser()
        self.source_path = source_path
        raw_text = source_path.read_text(encoding="utf-8", errors="replace")
        decoded_text = self._decode_source_text(raw_text, source_path)
        self._set_text(decoded_text)

    def loadSource(self, path: str | Path) -> None:  # noqa: N802
        self.load_source(path)

    def _set_text(self, text: str) -> None:
        self._raw_text = text
        self._paragraphs = self._normalize_paragraphs(text)
        self.paragraph_index = 0
        self.char_index = 0
        self.history.clear()
        self._sync_progress()

    @staticmethod
    def _decode_source_text(text: str, source_path: Path | None = None) -> str:
        if NovelTextEngine._looks_like_rtf(text):
            converted = NovelTextEngine._convert_rtf_to_plain_text(text, source_path)
            if converted:
                return converted
        return text

    @staticmethod
    def _looks_like_rtf(text: str) -> bool:
        return text.lstrip().startswith("{\\rtf")

    @staticmethod
    def _convert_rtf_to_plain_text(text: str, source_path: Path | None = None) -> str:
        command = ["textutil", "-convert", "txt", "-stdout", "-format", "rtf"]
        if source_path is not None:
            command.append(str(source_path))
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout
        return text

    def _current_paragraph(self) -> str | None:
        if 0 <= self.paragraph_index < len(self._paragraphs):
            return self._paragraphs[self.paragraph_index]
        return None

    def _total_units(self) -> int:
        if not self._paragraphs:
            return 0
        return sum(len(paragraph) for paragraph in self._paragraphs) + max(
            len(self._paragraphs) - 1, 0
        )

    def _flat_position(self) -> int:
        if not self._paragraphs:
            return 0

        position = 0
        for paragraph in self._paragraphs[: self.paragraph_index]:
            position += len(paragraph) + 1
        position += min(self.char_index, len(self._current_paragraph() or ""))
        return position

    def _compute_progress(self) -> float:
        total_units = self._total_units()
        if total_units == 0:
            return 1.0
        return self._flat_position() / total_units

    def _sync_progress(self) -> None:
        self.progress = self._compute_progress()

    def has_remaining_text(self) -> bool:
        paragraph = self._current_paragraph()
        if paragraph is None:
            return False

        if self.paragraph_index < len(self._paragraphs) - 1:
            return True
        return self.char_index < len(paragraph)

    def hasRemainingText(self) -> bool:  # noqa: N802
        return self.has_remaining_text()

    def emit_on_space(self) -> str:
        paragraph = self._current_paragraph()
        if paragraph is None or self.char_index >= len(paragraph):
            return ""

        previous_paragraph_index = self.paragraph_index
        previous_char_index = self.char_index
        output = paragraph[self.char_index]

        self.char_index += 1
        self.history.append(
            HistoryEntry(
                action="space",
                output=output,
                previous_paragraph_index=previous_paragraph_index,
                previous_char_index=previous_char_index,
                next_paragraph_index=self.paragraph_index,
                next_char_index=self.char_index,
            )
        )
        self._sync_progress()
        return output

    def emitOnSpace(self) -> str:  # noqa: N802
        return self.emit_on_space()

    def emit_on_return(self) -> str:
        paragraph = self._current_paragraph()
        if paragraph is None or not self.has_remaining_text():
            return ""

        previous_paragraph_index = self.paragraph_index
        previous_char_index = self.char_index

        next_paragraph_index = self.paragraph_index + 1
        if next_paragraph_index < len(self._paragraphs):
            next_char_index = 0
        else:
            next_paragraph_index = max(len(self._paragraphs) - 1, 0)
            next_char_index = len(self._paragraphs[next_paragraph_index]) if self._paragraphs else 0

        self.paragraph_index = next_paragraph_index
        self.char_index = next_char_index

        self.history.append(
            HistoryEntry(
                action="return",
                output="\n",
                previous_paragraph_index=previous_paragraph_index,
                previous_char_index=previous_char_index,
                next_paragraph_index=self.paragraph_index,
                next_char_index=self.char_index,
            )
        )
        self._sync_progress()
        return "\n"

    def emitOnReturn(self) -> str:  # noqa: N802
        return self.emit_on_return()

    def rewind_last(self) -> str:
        if not self.history:
            return ""

        last_entry = self.history.pop()
        self.paragraph_index = last_entry.previous_paragraph_index
        self.char_index = last_entry.previous_char_index
        self._sync_progress()
        return last_entry.output

    def rewindLast(self) -> str:  # noqa: N802
        return self.rewind_last()

    def snapshot(self) -> dict[str, object]:
        return {
            "paragraph_count": self.paragraph_count,
            "paragraph_index": self.paragraph_index,
            "char_index": self.char_index,
            "current_paragraph_length": self.current_paragraph_length,
            "progress": self.progress,
            "remaining": self.has_remaining_text(),
            "source_path": str(self.source_path) if self.source_path else "",
        }


TextEngine = NovelTextEngine
