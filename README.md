LaTeX Package: DocRef v0.1 2026-10-23
----------------------------------------

Cross-references to labeled sections in external LaTeX package documentation.

## Description

`docref` resolves a label in another package’s documentation source and prints its section number. It requires LuaLaTeX, discovers common source filenames automatically, and can also scan simple `\input` and `\include` files. Unresolved references print `??` and produce a warning.

## Installation

Keep `docref.sty` and `docref.lua` together, either beside your document or in a TeX-searchable directory.

## Usage

Use `\docref{<package>}{<label>}` for a reference. If automatic discovery does not locate a source, register it with the optional `\DocRefSource{<package>}{<source-file>}` command:

~~~latex
\documentclass{article}
\usepackage{docref}

% Optional: specify the documentation source explicitly
\DocRefSource{mypackage}{mypackage-manual.tex}

\begin{document}
See Section~\docref{mypackage}{sec:overview}.
\end{document}
~~~

Section numbers are read from source text; titles and page numbers are not provided.


## Documentation
See the [main manual](doc/docref.pdf) for configuration and examples.

## License and maintainer

- License: LPPL 1.3c or later.
- Maintainer: Amer Amikhteh.
