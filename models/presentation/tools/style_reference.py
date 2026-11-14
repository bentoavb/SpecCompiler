#!/usr/bin/env python3
"""Apply the presentation model's technical color palette to Pandoc's PPTX reference."""

from pathlib import Path
import re
import sys
import zipfile


COLORS = {
    "dk1": '<a:srgbClr val="000080"/>',
    "lt1": '<a:srgbClr val="F8FAFC"/>',
    "dk2": '<a:srgbClr val="000080"/>',
    "lt2": '<a:srgbClr val="E6EEF7"/>',
    "accent1": '<a:srgbClr val="2563EB"/>',
    "accent2": '<a:srgbClr val="06B6D4"/>',
    "accent3": '<a:srgbClr val="14B8A6"/>',
    "accent4": '<a:srgbClr val="F59E0B"/>',
    "accent5": '<a:srgbClr val="7C3AED"/>',
    "accent6": '<a:srgbClr val="475569"/>',
    "hlink": '<a:srgbClr val="2563EB"/>',
    "folHlink": '<a:srgbClr val="7C3AED"/>',
}
FONTS = {"majorFont": "Aptos Display", "minorFont": "Aptos"}


def replace_theme_xml(data: bytes, theme_name: str) -> bytes:
    text = data.decode("utf-8")
    for slot, color in COLORS.items():
        pattern = rf"(<a:{slot}>).*?(</a:{slot}>)"
        text, count = re.subn(pattern, rf"\g<1>{color}\g<2>", text, count=1, flags=re.DOTALL)
        if count != 1:
            raise RuntimeError(f"{theme_name}: expected one {slot} theme color, found {count}")

    for slot, font in FONTS.items():
        pattern = rf'(<a:{slot}>.*?<a:latin\s+typeface=")[^"]*("[^>]*/>)'
        text, count = re.subn(pattern, rf"\g<1>{font}\g<2>", text, count=1, flags=re.DOTALL)
        if count != 1:
            raise RuntimeError(f"{theme_name}: expected one {slot} Latin font, found {count}")
    return text.encode("utf-8")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: style_reference.py reference.pptx")
    path = Path(sys.argv[1])
    temporary = path.with_suffix(path.suffix + ".tmp")
    with zipfile.ZipFile(path, "r") as source, zipfile.ZipFile(temporary, "w") as output:
        for entry in source.infolist():
            content = source.read(entry.filename)
            if re.fullmatch(r"ppt/theme/theme\d+\.xml", entry.filename):
                content = replace_theme_xml(content, entry.filename)
            output.writestr(entry, content)
    temporary.replace(path)


if __name__ == "__main__":
    main()
