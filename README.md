LaTeX Package: DocRef v0.2 2026-10-26
----------------------------------------

Cross-references to external LaTeX package documentation.

## Description

`docref` retrieves reference numbers, titles, and page numbers from locally
available package manuals. It requires LuaLaTeX.

## Usage

~~~latex
\documentclass{article}
\usepackage{docref}
\usepackage{hyperref} % optional
\begin{document}
See Section~\docref{babel}{selectors},
``\docnameref{babel}{selectors}'',
on page~\docpageref{babel}{selectors}.
\end{document}
~~~

All three commands take a package name and label. With `hyperref`, references
link to the PDF manual; starred forms suppress links. Unresolved values
produce `??` and a warning.

Common documentation source names are discovered automatically. To select
a source or auxiliary file explicitly, use:

~~~latex
\DocRefSource{pkg}{build/manual.aux}[build/manual.pdf]
~~~

The first file may be `.tex`, `.ltx`, `.dtx`, or `.aux`; the optional final
argument specifies a PDF file or URL. Auxiliary records support all label
types, including figures, tables, equations, and custom counters. Titles
require `nameref` or `hyperref` in the target manual; exact destinations
require `hyperref` there. Without auxiliary records, lookup is limited to
source headings and PDF information.

## Installation

Keep `docref.sty` and `docref.lua` together beside your document or in a
TeX-searchable directory.

## Documentation

See the [main manual](doc/docref.pdf) for lookup rules and examples.

## License and maintainer

- License: LPPL 1.3c or later.
- Maintainer: Amer Amikhteh.
