"""Check compiled hyperref-regression PDFs: python check-hyperlinks.py QA_DIR.

Requires pypdf. The fixtures and regression cases must already be compiled;
expected filenames are hyper-{before,after}-{english,persian}.pdf and
hyper-{none,draft}-persian.pdf.
An optional second argument names the compiled test/docref.pdf example;
its links are checked against the actual external manuals' outline entries.
"""

from pathlib import Path
import re
import sys

from pypdf import PdfReader


def filename(value):
    # Hyperref's file-specification string contains the OS filename bytes.
    try:
        return value.original_bytes.decode("utf-8")
    except (AttributeError, UnicodeDecodeError):
        return str(value)


def check(directory):
    for order, language in [
        ("before", "english"), ("after", "english"),
        ("before", "persian"), ("after", "persian"),
        ("none", "persian"), ("draft", "persian"),
    ]:
        path = directory / f"hyper-{order}-{language}.pdf"
        reader = PdfReader(path)
        actions = [
            annot.get_object()["/A"]
            for page in reader.pages
            for annot in page.get("/Annots", [])
            if "/A" in annot.get_object()
        ]
        if order in {"none", "draft"}:
            assert not actions, path.name
            print(path.name, "no annotations, as expected")
            continue

        assert any(
            getattr(item, "title", None) == "Babel section 1.9"
            for item in reader.outline
        ), (path.name, reader.outline)

        expected = [
            ("aux/manual with spaces.pdf", "subsection.custom-9"),
            ("aux/manual with spaces.pdf", "subsubsection.custom-9.1"),
            ("standard/hyperref-manual.pdf", "subsection.1.2"),
            ("plain/hyperref-manual.pdf", None),
            (None, None),  # Explicit URL.
            ("aux/manual with spaces.pdf", "subsection.custom-9"),
            ("babel.pdf", "subsection.1.9"),
        ]
        # Missing PDFs and unresolved labels must not create annotations.
        assert len(actions) == len(expected), (path.name, actions)
        for action, (suffix, destination) in zip(actions, expected):
            if suffix is None:
                assert action["/S"] == "/URI", action
                assert action["/URI"] == (
                    "https://example.invalid/manual.pdf#subsection.custom-9"
                ), action
                continue
            assert action["/S"] == "/GoToR", action
            target = Path(filename(action["/F"]))
            assert target.as_posix().endswith(suffix), target
            assert target.is_file(), target
            if destination is None:
                assert isinstance(action["/D"], list) and action["/D"][0] == 0
            else:
                assert action["/D"] == destination, action
                assert destination in PdfReader(target).named_destinations, action
        print(path.name, "all external destinations verified")


def check_example(path):
    """Compare real manual links with their corresponding outline entries."""
    expected = [
        ("babel.pdf", "Basic language selectors"),
        ("babel.pdf", "provide and babelprovide ini files"),
        ("enumitem.pdf", "enumerate-like labels"),
        ("xepersian-doc.pdf", "Basics"),
        ("tcolorbox.pdf", "Library vignette"),
        ("babelbidi.pdf", "Language Selection"),
        ("babel.pdf", "Basic language selectors"),  # Title.
        ("babel.pdf", "Basic language selectors"),  # Page.
    ]
    reader = PdfReader(path)
    actions = [
        annot.get_object()["/A"]
        for page in reader.pages for annot in page.get("/Annots", [])
        if annot.get_object().get("/A", {}).get("/S") == "/GoToR"
    ]
    assert len(actions) == len(expected), actions

    def flatten(items):
        for item in items:
            if isinstance(item, list):
                yield from flatten(item)
            else:
                yield item

    def normalized(title):
        return re.sub(r"[^a-z]", "", title.casefold())

    for action, (suffix, title) in zip(actions, expected):
        target = Path(filename(action["/F"]))
        assert target.name == suffix, target
        manual = PdfReader(target)
        destination = manual.named_destinations[action["/D"]]
        headings = [item for item in flatten(manual.outline)
                    if normalized(item.title) == normalized(title)]
        assert len(headings) == 1, (target, title, headings)
        assert destination.dest_array == headings[0].dest_array, (target, action)
        print(suffix, action["/D"], "verified against outline; physical page",
              manual.get_destination_page_number(destination) + 1)


if __name__ == "__main__":
    check(Path(sys.argv[1]))
    if len(sys.argv) > 2:
        check_example(Path(sys.argv[2]))
