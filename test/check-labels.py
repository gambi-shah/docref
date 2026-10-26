"""Build and verify arbitrary-label references in a dedicated scratch directory.

Usage: python check-labels.py QA_DIR
Requires LuaLaTeX, docref on the TeX search path, and pypdf.
"""

from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import shutil
import subprocess
import sys

from pypdf import PdfReader


def run(arguments, directory, log):
    with log.open("w") as output:
        subprocess.run(
            ["lualatex", "-interaction=nonstopmode", "-halt-on-error", *arguments],
            cwd=directory, stdout=output, stderr=subprocess.STDOUT, check=True,
        )


def filename(value):
    try:
        return value.original_bytes.decode("utf-8")
    except (AttributeError, UnicodeDecodeError):
        return str(value)


def check(directory):
    repo = Path(__file__).resolve().parents[1]
    directory.mkdir(parents=True, exist_ok=True)
    for kind in ("aux", "source"):
        target = directory / kind
        target.mkdir(exist_ok=True)
        shutil.copyfile(repo / "test/labels-manual.tex", target / "labels-manual.tex")

    target = directory / "aux"
    for extension in ("aux", "out"):
        (target / f"labels-manual.{extension}").unlink(missing_ok=True)
    for _ in range(2):
        run(["labels-manual.tex"], target, target / "build.stdout")
    # Registration must work with no source file to scan or execute.
    (target / "labels-manual.tex").unlink()
    with (target / "labels-manual.aux").open("a") as output:
        output.write("\n" + "\n".join([
            r"\newlabel{legacy}{{X}{1}{Obsolete title}{figure.1.1}{}}",
            r"\newlabel{legacy}{{A-1(a)}{vii}}",
            r"\newlabel{unicode}{{الف-۱}{1}{عنوان}{figure.1.1}{}}",
            r"\newlabel{decorated}{{(A.12)}{1}{Decorated counter}{example.custom-example}{}}",
            r"\errmessage{External AUX must never be executed}",
        ]) + "\n")

    def case(language):
        job = f"labels-{language}"
        source = (r"\def\TestRoot{" + str(directory)
                  + r"}\def\TestMain{" + language + r"}\input{"
                  + str(repo / "test/labels-regression.tex") + "}")
        for _ in range(2):
            run(["-jobname=" + job, source], directory, directory / (job + ".stdout"))
        log = (directory / (job + ".log")).read_text()
        assert "DOCREF GENERIC LABEL REGRESSION PASSED" in log, job
        assert "Package docref Warning:" not in log, job
        assert "External AUX must never be executed" not in log, job
        reader = PdfReader(directory / (job + ".pdf"))
        text = "\n".join(page.extract_text() for page in reader.pages)
        for expected in ("Figure 1.1: Diagram caption, page 1.",
                         "Table 1.1: Table caption.", "Equation 1.1; item 1.",
                         "Ex A-1(a): Worked example.",
                         "Appendix A: An appendix, page 2.",
                         "Legacy record A-1(a), page vii."):
            assert expected in text, (job, text)
        actions = [a.get_object()["/A"]
                   for page in reader.pages for a in page.get("/Annots", [])
                   if "/A" in a.get_object()]
        expected = (["chapter.1"] * 2 + ["figure.1.1"] * 3
                    + ["table.1.1"] * 2 + ["equation.1.1", "Item.1"]
                    + ["example.custom-example"] * 2 + ["appendix.A"] * 3
                    + [None] * 2)
        assert len(actions) == len(expected), (job, actions)
        manual = PdfReader(target / "labels-manual.pdf")
        for action, name in zip(actions, expected):
            assert action["/S"] == "/GoToR", action
            assert Path(filename(action["/F"])) == target / "labels-manual.pdf", action
            if name is None:
                assert isinstance(action["/D"], list) and action["/D"][0] == 0, action
            else:
                assert action["/D"] == name, action
                destination = manual.named_destinations[name]
                index = manual.get_destination_page_number(destination)
                assert index == (1 if name == "appendix.A" else 0), action
        print(job, "numbers, captions, pages, and exact destinations verified", flush=True)

    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(case, ("english", "persian")))


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve())
