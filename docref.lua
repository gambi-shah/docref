-- docref.lua
--
-- Lua engine for references to package documentation.
--
-- Copyright (C) 2026 Amer Amikhteh
--
-- This file is part of the docref package.
--
-- This work is free software: you may redistribute it and/or modify
-- it under the terms of the LaTeX Project Public License as published
-- by the LaTeX Project, either version 1.3c of the License, or
-- (at your option) any later version.
--
-- This work is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty
-- of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
--
-- The full license text is available at:
-- https://www.latex-project.org/lppl/
--
-- This work is "maintained" by Amer Amikhteh.
--
-- The current maintainer of this work is Amer Amikhteh.
--
-- Version: 0.2
-- Date: 2026-10-26



local M = {}

local ok_lfs, lfs_module = pcall(require, "lfs")
local lfs = ok_lfs and lfs_module or nil

-- Used only for the source-text fallback, never to restrict auxiliary labels.
local section_levels = {
  "section",
  "subsection",
  "subsubsection",
  "paragraph",
  "subparagraph"
}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Balanced TeX groups are read as data, never executed.
local function group(s, pos)
  pos = s:find("%S", pos)
  if not pos or s:sub(pos, pos) ~= "{" then return nil end
  local start, depth = pos + 1, 1
  pos = start
  while pos <= #s do
    local c = s:sub(pos, pos)
    if c == "\\" then
      pos = pos + 2
    else
      if c == "{" then depth = depth + 1 end
      if c == "}" then depth = depth - 1 end
      if depth == 0 then return s:sub(start, pos - 1), pos + 1 end
      pos = pos + 1
    end
  end
end

-- Titles are plain text. Retain text arguments, not formatting or commands
-- from another document (including commands embedded in an auxiliary file).
local function plain_text(s)
  local accents = {
    ["'"] = {"AEIOUYaeiouy", {"Á", "É", "Í", "Ó", "Ú", "Ý", "á", "é", "í", "ó", "ú", "ý"}},
    ["`"] = {"AEIOUaeiou", {"À", "È", "Ì", "Ò", "Ù", "à", "è", "ì", "ò", "ù"}},
    ['"'] = {"AEIOUYaeiouy", {"Ä", "Ë", "Ï", "Ö", "Ü", "Ÿ", "ä", "ë", "ï", "ö", "ü", "ÿ"}},
    ["^"] = {"AEIOUaeiou", {"Â", "Ê", "Î", "Ô", "Û", "â", "ê", "î", "ô", "û"}},
    ["~"] = {"ANOano", {"Ã", "Ñ", "Õ", "ã", "ñ", "õ"}},
    c = {"Cc", {"Ç", "ç"}}
  }
  for accent, mapping in pairs(accents) do
    local boundary = accent:match("%a") and "%f[^%a]" or ""
    s = s:gsub("\\" .. accent:gsub("([^%w])", "%%%1") .. boundary .. "%s*{?([%a])}?",
      function(letter)
        local at = mapping[1]:find(letter, 1, true)
        return at and mapping[2][at] or letter
      end)
  end
  s = s:gsub("\\texorpdfstring%s*(%b{})%s*(%b{})", function(_, pdf)
    return pdf:sub(2, -2)
  end)
  for _, command in ipairs({"href", "hyperlink"}) do
    s = s:gsub("\\" .. command .. "%s*(%b{})%s*(%b{})", function(_, text)
      return text:sub(2, -2)
    end)
  end
  local words = {TeX = "TeX", LaTeX = "LaTeX", LuaTeX = "LuaTeX",
    XeTeX = "XeTeX", XeLaTeX = "XeLaTeX", LuaLaTeX = "LuaLaTeX",
    textbackslash = "\\", textasciitilde = "~", textasciicircum = "^",
    textendash = "–", textemdash = "—", ldots = "…", dots = "…",
    textquotedblleft = "“", textquotedblright = "”", ae = "æ", AE = "Æ",
    oe = "œ", OE = "Œ", aa = "å", AA = "Å", ss = "ß"}
  local out, pos = {}, 1
  while pos <= #s do
    local c = s:sub(pos, pos)
    if c == "\\" then
      local a, b, command = s:find("([%a@]+)", pos + 1)
      if a == pos + 1 then
        out[#out + 1] = words[command] or ""
        pos = s:find("%S", b + 1) or #s + 1
      else
        local symbol = s:sub(pos + 1, pos + 1)
        if symbol:match("[#$%%&_{} ]") then out[#out + 1] = symbol end
        if symbol == "\\" then out[#out + 1] = " " end
        pos = pos + 2
      end
    else
      if c ~= "{" and c ~= "}" then out[#out + 1] = c == "~" and " " or c end
      pos = pos + 1
    end
  end
  return trim(table.concat(out):gsub("%-%-%-", "—"):gsub("%-%-", "–"):gsub("%s+", " "))
end

local function package_key(name)
  return trim(name):lower()
end

local function read_file(path)
  if not path or path == "" then
    return nil
  end

  local f = io.open(path, "r")
  if f then
    return f, path
  end
end

local function kpsewhich(name, search_path)
  local args = {}

  if search_path then
    args[#args + 1] = "--path=" .. string.format("%q", search_path)
  end

  args[#args + 1] = string.format("%q", name)

  local p = io.popen("kpsewhich " .. table.concat(args, " "))
  if not p then
    return nil
  end

  local path = trim(p:read("*a") or "")
  p:close()

  return read_file(path)
end

local function find_file(name, base, broad_search)
  if base then
    local f, path = read_file(base .. "/" .. name)
    if f then
      return f, path
    end
    if not name:match("%.tex$") then
      f, path = read_file(base .. "/" .. name .. ".tex")
      if f then return f, path end
    end
  end

  local f, path = read_file(name)
  if f then
    return f, path
  end

  f, path = kpsewhich(name)
  if f then
    return f, path
  end

  if broad_search then
    -- Documentation is not confined to TEXMFDIST (e.g. TEXMFHOME).
    for _, format in ipairs({"TeX system documentation", "TeX system sources"}) do
      local found = kpse.find_file(name, format)
      f, path = read_file(found)
      if f then return f, path end
    end
    local p = io.popen("kpsewhich --var-value=TEXMFDIST")
    if p then
      local texmfdist = trim(p:read("*a") or "")
      p:close()

      if texmfdist ~= "" then
        for _, dir in ipairs({ "doc//", "source//" }) do
          f, path = kpsewhich(name, texmfdist .. "/" .. dir)
          if f then
            return f, path
          end
        end
      end
    end
  end

  -- TeX appends .tex even when an input's basename already contains dots.
  if not name:match("%.tex$") and not name:match("%.ltx$")
    and not name:match("%.dtx$") then
    return find_file(name .. ".tex", base, broad_search)
  end

  error("Cannot find source file: " .. name)
end

-- Editors identify a manual's main file in fragments with a TeX root comment.
-- Resolve it before counting sections or choosing the corresponding PDF.
local function source_file(name)
  local f, path = find_file(name, nil, true)
  if path:match("%.aux$") then return f, path end
  local header = f:read(4096) or ""
  f:seek("set")
  local root = header:match("%%[ \t]*![Tt][Ee][Xx][ \t]+root[ \t]*=[ \t]*([^\r\n]+)")
  if root then
    local ok, parent, parent_path = pcall(find_file, trim(root),
      path:match("^(.*)[/\\]") or ".", true)
    if ok then
      f:close()
      return parent, parent_path
    end
  end
  return f, path
end

local function strip_comments(s)
  local out = {}

  for line in (s .. "\n"):gmatch("(.-)\n") do
    local cut = #line + 1

    for i = 1, #line do
      if line:sub(i, i) == "%" then
        local n, j = 0, i - 1
        while j > 0 and line:sub(j, j) == "\\" do
          n, j = n + 1, j - 1
        end

        if n % 2 == 0 then
          cut = i
          break
        end
      end
    end

    out[#out + 1] = line:sub(1, cut - 1)
  end

  return table.concat(out, "\n")
end

local expand_file
local dependencies = {}
local active = {}

local function expand_inputs(s, base)
  local function replace(name)
    name = trim(name)

    local ok, expanded = pcall(expand_file, name, base, false)
    if ok then
      return "\n" .. expanded .. "\n"
    end

    return ""
  end

  s = s:gsub("\\input%s*{([^{}]+)}", replace)
  s = s:gsub("\\include%s*{([^{}]+)}", replace)

  return s
end

expand_file = function(name, base, broad_search)
  local f, path = find_file(name, base, broad_search)
  path = path:gsub("\\", "/")

  local attr = lfs and lfs.attributes(path)
  dependencies[path] = {
  modification = attr and attr.modification or 0,
  size = attr and attr.size or 0
}


  if active[path] then
    f:close()
    return ""
  end

  local s = f:read("*a")
  f:close()

  active[path] = true

  -- Code samples describe commands; they must not advance manual counters.
  for _, environment in ipairs({"macrocode", "verbatim", "Verbatim",
    "lstlisting", "minted", "dispListing", "fulldocumentlisting"}) do
    s = s:gsub("\\begin%s*{" .. environment .. "%*?}.-\\end%s*{"
      .. environment .. "%*?}", "")
  end
  s = strip_comments(s)
  -- docmute-style inputs are standalone documents. Discard each input's
  -- preamble before expansion, rather than just the main file's preamble.
  local _, body = s:find("\\begin%s*{document}")
  if body then s = s:sub(body + 1) end
  s = expand_inputs(s, path:match("^(.*)[/\\]") or ".")

  active[path] = nil
  return s
end

local function make_reference(source, label)
  dependencies = {}
  active = {}

  local f, path = source_file(source)
  f:close()
  local s = expand_file(path, nil, true)

  local counts = {}
  for i = 1, #section_levels do
    counts[i] = 0
  end

  local target = "\\label%s*{%s*"
    .. label:gsub("([^%w])", "%%%1")
    .. "%s*}"

  local label_at = s:find(target)
  assert(label_at, "Cannot locate label '" .. label .. "' in " .. source)
  local pos, title, heading_end, numbered_heading = 1, nil, nil, false

  while pos < label_at do
    local a, b = s:find("\\([%a@]+)%*?", pos)
    if not a or a >= label_at then
      break
    end

    local command = s:sub(a + 1, b):gsub("%*$", "")
    local level

    for i, name in ipairs(section_levels) do
      if command == name then
        level = i
        break
      end
    end

    -- A mention such as |\section| is not a sectioning command.
    local argument = s:find("%S", b + 1)
    if argument and s:sub(argument, argument) == "[" then
      local closing = s:find("]", argument + 1, true)
      argument = closing and s:find("%S", closing + 1)
    end
    local after_heading
    if level and argument and s:sub(argument, argument) == "{" then
      title, heading_end = group(s, argument)
      after_heading = heading_end
      numbered_heading = s:sub(b, b) ~= "*"
      if numbered_heading then
        counts[level] = counts[level] + 1
        for i = level + 1, #section_levels do
          counts[i] = 0
        end
      end
    end

    -- Heading arguments may contain command names; do not count them again.
    pos = after_heading or b + 1
  end

  -- Source text cannot reveal what an intervening command does to counters.
  -- Only accept labels attached to a heading. Label aliases and TOC entries
  -- do not change its counter and may appear before the target label.
  local between = heading_end and s:sub(heading_end, label_at - 1)
  if between then
    between = between:gsub("\\label%s*{[^{}]*}", "")
      :gsub("\\addcontentsline%s*%b{}%s*%b{}%s*%b{}", "")
  end
  if not between or between:find("%S") then
    return nil, dependencies, nil
  end

  local parts = {}
  for _, n in ipairs(counts) do
    if n > 0 then
      parts[#parts + 1] = tostring(n)
    end
  end

  return numbered_heading and #parts > 0 and table.concat(parts, ".") or nil,
    dependencies, title
end

local function candidate_names(package)
  local p = trim(package)

  return {
    p .. ".tex",
    p .. ".ltx",
    p .. "-doc.tex",
    p .. "-doc.ltx",
    p .. "-manual.tex",
    p .. "-manual.ltx",
    p .. ".dtx",
    p .. "-doc.dtx",
    p .. "-manual.dtx"
  }
end

local function find_package_source(package)
  local tried = {}

  -- Prefer installed documentation to unrelated files named package.tex in
  -- the working directory (a package's test directory commonly has one).
  local sty = kpse.find_file(trim(package) .. ".sty")
  local base = sty and (sty:match("^(.*)[/\\]") or ".")
  for _, name in ipairs(candidate_names(package)) do
    if base then
      local f, local_path = read_file(base .. "/doc/" .. name)
      if f then f:close(); return local_path end
    end
    for _, format in ipairs({"TeX system documentation", "TeX system sources"}) do
      for _, path in ipairs({kpse.lookup(name, {format = format, all = true})}) do
        -- Kpathsea's source path also starts with the current directory.
        if path:match("^/") or path:match("^%a:[/\\]") then return path end
      end
    end
  end

  for _, name in ipairs(candidate_names(package)) do
    tried[#tried + 1] = name

    local ok, f, path = pcall(find_file, name, nil, true)
    if ok and f then
      f:close()
      return path
    end
  end

  error(
    "Cannot find documentation source for '" .. package
      .. "'. Tried: " .. table.concat(tried, ", ")
      .. ". Specify it with \\DocRefSource{"
      .. package .. "}{source-file}."
  )
end

local sources = {}
local cache = {}
local documents = {}
local link_documents = {}

local CACHE_VERSION = "4"
local cache_path = (tex and tex.jobname or "docref") .. ".docref.aux"

local function hex(s)
  return (s:gsub(".", function(c)
    return string.format("%02x", string.byte(c))
  end))
end

local function unhex(s)
  if s == "" then
    return ""
  end

  if #s % 2 ~= 0 or not s:match("^[%da-fA-F]+$") then
    error("Invalid hex data in docref cache")
  end

  return (s:gsub("%x%x", function(pair)
    return string.char(tonumber(pair, 16))
  end))
end

local function serialize_dependencies(deps)
  local dep_parts = {}

  for path, value in pairs(deps or {}) do
    local modification
    local size

    if type(value) == "table" then
      modification = value.modification or 0
      size = value.size or 0
    else
      -- Compatibility with the old in-memory format.
      modification = value or 0
      size = 0
    end

    dep_parts[#dep_parts + 1] =
      hex(path)
      .. "="
      .. tostring(modification)
      .. ":"
      .. tostring(size)
  end

  table.sort(dep_parts)
  return table.concat(dep_parts, ",")
end

local function deserialize_dependencies(encoded)
  local deps = {}

  for item in encoded:gmatch("[^,]+") do
    local path_hex, modification, size =
      item:match("^([%da-fA-F]+)=([%-]?[%d%.]+):([%d%.]+)$")

    if path_hex and modification and size then
      deps[unhex(path_hex)] = {
        modification = tonumber(modification),
        size = tonumber(size)
      }
    else
      -- Read old records containing only mtime.
      local old_path_hex, old_modification =
        item:match("^([%da-fA-F]+)=([%-]?[%d%.]+)$")

      if old_path_hex and old_modification then
        deps[unhex(old_path_hex)] = {
          modification = tonumber(old_modification),
          size = 0
        }
      end
    end
  end

  return deps
end

local function cache_record(package, label, number, source, deps)
  return table.concat({
    "D",
    CACHE_VERSION,
    hex(package),
    hex(label),
    hex(number),
    hex(source),
    hex(serialize_dependencies(deps))
  }, "|")
end

local function append_cache(package, label, number, source, deps)
  local record = cache_record(package, label, number, source, deps)
  local f = io.open(cache_path, "ab")

  if not f then
    -- Cache failure must never stop document compilation.
    texio.write_nl(
      "term and log",
      "docref warning: cannot write cache " .. cache_path
    )
    return
  end

  f:write(record, "\n")
  f:flush()
  f:close()
end

local function load_cache_record(line)
  local version
  local package_hex
  local label_hex
  local number_hex
  local source_hex
  local deps_hex

  version,
  package_hex,
  label_hex,
  number_hex,
  source_hex,
  deps_hex = line:match(
    "^D|([^|]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$"
  )

  if version ~= CACHE_VERSION then
    return
  end

  local ok = pcall(function()
    local package = unhex(package_hex)
    local label = unhex(label_hex)
    local number = unhex(number_hex)
    local source = unhex(source_hex)
    local deps = deserialize_dependencies(unhex(deps_hex))

    local key = package_key(package)
    cache[key] = cache[key] or {}

    -- The last valid record wins.
    cache[key][trim(label)] = {
      number = number,
      source = source,
      deps = deps
    }
  end)

  if not ok then
    texio.write_nl(
      "term and log",
      "docref warning: invalid cache record ignored"
    )
  end
end

local function load_cache()
  local f = io.open(cache_path, "rb")
  if not f then
    return
  end

  for line in f:lines() do
    load_cache_record(line)
  end

  f:close()
end

-- Kept as compatibility no-ops. The cache is no longer stored in the
-- document's main .aux file.
function M.set_aux_writer(_)
end

function M.aux_write(_, _, _, _, _)
end

function M.load_aux(_, _, _, _, _)
end

function M.load_aux_hex(_, _, _, _, _)
end

function M.register(package, source, document)
  local key = package_key(package)
  source = trim(source)

  assert(key ~= "", "Package name must not be empty")
  assert(source ~= "", "Source file name must not be empty")

  -- Do not delete old cache records. A different source automatically
  -- invalidates them during the next reference.
  sources[key] = source
  documents[key] = document and trim(document) or nil
  link_documents[key] = nil
end

local function dependencies_valid(deps)
  if type(deps) ~= "table" or not lfs then
    return false
  end

  local has_dependencies = false

  for path, value in pairs(deps) do
    local attr = lfs.attributes(path)

    if not attr then
      return false
    end

    local old_modification
    local old_size

    if type(value) == "table" then
      old_modification = value.modification or 0
      old_size = value.size or 0
    else
      old_modification = value or 0
      old_size = 0
    end

    if (attr.modification or 0) ~= old_modification then
      return false
    end

    -- Old records have size zero. Do not invalidate them only because
    -- they were created before size tracking was introduced.
    if old_size ~= 0 and (attr.size or 0) ~= old_size then
      return false
    end

    has_dependencies = true
  end

  return has_dependencies
end

load_cache()

local reference_info, reference_value

function M.reference(package, label, field)
  local key = package_key(package)
  label = trim(label)
  field = field or "number"
  assert(key ~= "", "Package name must not be empty")
  assert(label ~= "", "Label must not be empty")
  assert(field == "number" or field == "name" or field == "page",
    "Unknown reference field: " .. tostring(field))

  cache[key] = cache[key] or {}
  local entry = cache[key][label]
  local valid = entry and entry.source == (sources[key] or entry.source)
    and dependencies_valid(entry.deps)
  local source = valid and entry.source or sources[key] or find_package_source(package)
  local info = reference_info(package, source)
  local values = ({number = info.numbers, name = info.titles, page = info.pages})[field]
  -- Auxiliary records describe arbitrary labels, including deliberately empty
  -- values. Never replace a known record with a guessed section reference.
  if values[label] ~= nil then return values[label] end
  if info.labels[label] then
    local value = reference_value(info, label, {number = info.numbers[label]}, field)
    assert(value ~= nil, "Cannot determine " .. field .. " for label '" .. label .. "'")
    return value
  end

  assert(not source:match("%.aux$"), "Cannot locate label '" .. label .. "' in " .. source)

  if not valid then
    local number, deps, title = make_reference(source, label)
    entry = {number = number, source = source, deps = deps, title = title}
    cache[key][label] = entry
    if number then append_cache(package, label, number, source, deps) end
    texio.write_nl("term and log", "docref cache MISS: " .. package .. " / " .. label)
  else
    texio.write_nl("term and log", "docref cache HIT: " .. package .. " / " .. label)
  end

  if field == "number" then
    assert(entry.number, "Cannot determine number for label '" .. label .. "'")
    return entry.number
  end
  if not entry.title and field ~= "number" then
    local _, _, title = make_reference(source, label)
    entry.title = title
  end
  local value = reference_value(info, label, entry, field)
  if not value and field == "name" then
    value = entry.title and plain_text(entry.title)
  end
  assert(value and value ~= "", "Cannot determine " .. field .. " for label '" .. label .. "'")
  return value
end

local function directory(path)
  return path:match("^(.*)[/\\]") or "."
end

local function absolute(path)
  path = path:gsub("\\", "/")
  if not path:match("^/") and not path:match("^%a:/") and lfs then
    path = lfs.currentdir() .. "/" .. path
  end
  local root = path:match("^%a:/") or (path:sub(1, 1) == "/" and "/" or "")
  local parts = {}
  for part in path:sub(#root + 1):gmatch("[^/]+") do
    if part == ".." and #parts > 0 and parts[#parts] ~= ".." then
      table.remove(parts)
    elseif part ~= "." and (part ~= ".." or root == "") then
      parts[#parts + 1] = part
    end
  end
  return root .. table.concat(parts, "/")
end

local function read_anchors(path, info, visited)
  path = absolute(path)
  if visited[path] then return end
  visited[path] = true
  local f = io.open(path, "rb")
  if not f then return end
  local s = strip_comments(f:read("*a"))
  f:close()
  local pos = 1
  while true do
    local a, b, command = s:find("\\([%a@]+)", pos)
    if not a then break end
    pos = b + 1
    if command == "newlabel" or command == "@input" then
      local name, next_pos = group(s, pos)
      if name then
        pos = next_pos
        if command == "@input" then
          local child = name
          if not child:match("^[/\\]") and not child:match("^%a:") then
            child = directory(path) .. "/" .. child
          end
          read_anchors(child, info, visited)
        else
          local fields
          fields, next_pos = group(s, pos)
          if fields then
            pos = next_pos
            local value, p = nil, 1
            for field = 1, 4 do
              value, p = group(fields, p)
              if not value then break end
              if field == 1 then
                info.labels[name] = true
                info.numbers[name] = plain_text(value)
                info.pages[name], info.titles[name], info.anchors[name] = nil, nil, nil
              elseif field == 2 then
                info.pages[name] = plain_text(value)
              elseif field == 3 then
                info.titles[name] = plain_text(value)
              elseif field == 4 and value ~= "" then
                info.anchors[name] = value
              end
            end
          end
        end
      end
    end
  end
end

-- PDF text strings use UTF-16 with a BOM, or PDFDocEncoding otherwise.
local function pdf_text(s)
  if not s then return nil end
  local bom = s:sub(1, 2)
  if bom == "\254\255" or bom == "\255\254" then
    local out, high = {}, nil
    for i = 3, #s - 1, 2 do
      local a, b = s:byte(i, i + 1)
      local n = bom == "\254\255" and a * 256 + b or b * 256 + a
      if n >= 0xD800 and n <= 0xDBFF then
        high = n
      else
        if high and n >= 0xDC00 and n <= 0xDFFF then
          n = 0x10000 + (high - 0xD800) * 1024 + n - 0xDC00
        elseif n >= 0xDC00 and n <= 0xDFFF then
          n = 0xFFFD
        end
        out[#out + 1], high = utf8.char(n), nil
      end
    end
    return table.concat(out)
  end
  if s:sub(1, 3) == "\239\187\191" then return s:sub(4) end
  local special = {0x2022, 0x2020, 0x2021, 0x2026, 0x2014, 0x2013,
    0x0192, 0x2044, 0x2039, 0x203A, 0x2212, 0x2030, 0x201E, 0x201C,
    0x201D, 0x2018, 0x2019, 0x201A, 0x2122, 0xFB01, 0xFB02, 0x0141,
    0x0152, 0x0160, 0x0178, 0x017D, 0x0131, 0x0142, 0x0153, 0x0161, 0x017E}
  return (s:gsub("[\128-\255]", function(c)
    local n = c:byte()
    return utf8.char(special[n - 127] or (n == 160 and 0x20AC or n))
  end))
end

local function roman(n)
  local out = {}
  for _, item in ipairs({{1000, "m"}, {900, "cm"}, {500, "d"}, {400, "cd"},
    {100, "c"}, {90, "xc"}, {50, "l"}, {40, "xl"}, {10, "x"}, {9, "ix"},
    {5, "v"}, {4, "iv"}, {1, "i"}}) do
    while n >= item[1] do out[#out + 1], n = item[2], n - item[1] end
  end
  return table.concat(out)
end

local pdf_names = {}
local function destinations(path)
  if pdf_names[path] then
    return pdf_names[path].names, pdf_names[path].checked
  end
  local names = {}
  local entry = {names = names, checked = false}
  pdf_names[path] = entry
  if not pdfe then return names, false end
  local ok, doc = pcall(pdfe.open, path)
  if not ok or not doc then return names, false end
  entry.checked = pcall(function()
    local catalog = pdfe.getcatalog(doc)
    local page_numbers, labels, signatures = {}, {}, {}
    for n, page in ipairs(pdfe.pagestotable(doc)) do page_numbers[page[3]] = n end
    local function number_tree(tree)
      if not tree then return end
      local nums = pdfe.getarray(tree, "Nums")
      if nums then
        for i = 0, #nums - 1, 2 do
          local label = pdfe.getdictionary(nums, i + 1)
          labels[#labels + 1] = {first = pdfe.getinteger(nums, i),
            style = pdfe.getname(label, "S"),
            prefix = pdf_text(pdfe.getstring(label, "P", true)) or "",
            start = pdfe.getinteger(label, "St") or 1}
        end
      end
      local kids = pdfe.getarray(tree, "Kids")
      if kids then
        for i = 0, #kids - 1 do number_tree(pdfe.getdictionary(kids, i)) end
      end
    end
    number_tree(pdfe.getdictionary(catalog, "PageLabels"))
    table.sort(labels, function(a, b) return a.first < b.first end)
    local function page_label(page)
      if not page then return nil end
      local rule
      for _, item in ipairs(labels) do
        if item.first > page - 1 then break end
        rule = item
      end
      if not rule then return tostring(page) end
      local n = page - 1 - rule.first + rule.start
      local value = ""
      if rule.style == "D" then value = tostring(n)
      elseif rule.style == "r" or rule.style == "R" then
        value = roman(n)
        if rule.style == "R" then value = value:upper() end
      elseif rule.style == "a" or rule.style == "A" then
        value = string.rep(string.char((n - 1) % 26 + 97), math.floor((n - 1) / 26) + 1)
        if rule.style == "A" then value = value:upper() end
      end
      return rule.prefix .. value
    end
    local function destination(container, key)
      local array = pdfe.getarray(container, key)
      if not array then
        local dict = pdfe.getdictionary(container, key)
        array = dict and pdfe.getarray(dict, "D")
      end
      if not array then return nil end
      local parts = {}
      for _, item in ipairs(pdfe.arraytotable(array)) do
        parts[#parts + 1] = tostring(item[1]) .. ":" .. tostring(item[3] or item[2])
      end
      local signature = table.concat(parts, "/")
      if not signatures[signature] then
        -- The generic array reader is one-based; typed accessors are zero-based.
        local kind, _, object = pdfe.getfromarray(array, 1)
        local page = kind == 10 and page_numbers[object] or nil
        signatures[signature] = {page = page_label(page)}
      end
      return signatures[signature]
    end
    local function walk(tree)
      if not tree then return end
      local entries = pdfe.getarray(tree, "Names")
      if entries then
        for i = 0, #entries - 1, 2 do
          local name = pdfe.getstring(entries, i, true)
          if name then names[name] = destination(entries, i + 1) or {} end
        end
      end
      local kids = pdfe.getarray(tree, "Kids")
      if kids then
        for i = 0, #kids - 1 do walk(pdfe.getdictionary(kids, i)) end
      end
    end
    local tree = pdfe.getdictionary(catalog, "Names")
    if tree then walk(pdfe.getdictionary(tree, "Dests")) end
    local old = pdfe.getdictionary(catalog, "Dests")
    if old then
      for name in pairs(pdfe.dictionarytotable(old)) do
        names[name] = destination(old, name) or {}
      end
    end
    local seen = {}
    local function outlines(item)
      while item and not seen[tostring(item)] do
        seen[tostring(item)] = true
        local target, key = item, "Dest"
        local action = pdfe.getdictionary(item, "A")
        if action and pdfe.getname(action, "S") == "GoTo" then target, key = action, "D" end
        local name = pdfe.getstring(target, key, true) or pdfe.getname(target, key)
        local dest = name and names[name] or destination(target, key)
        if dest and not dest.title then
          dest.title = pdf_text(pdfe.getstring(item, "Title", true))
        end
        outlines(pdfe.getdictionary(item, "First"))
        item = pdfe.getdictionary(item, "Next")
      end
    end
    local outline = pdfe.getdictionary(catalog, "Outlines")
    if outline then outlines(pdfe.getdictionary(outline, "First")) end
  end)
  pdfe.close(doc)
  return names, entry.checked
end

local function pdf_file(name)
  local f = io.open(name, "rb")
  if f then f:close(); return absolute(name) end
  local path = kpse.find_file(name, "TeX system documentation")
  if path then return absolute(path) end
end

local function document_info(package, source)
  local f, path = source_file(source)
  f:close()
  path = absolute(path)
  local stem = path:gsub("%.[^./]+$", "")
  local key = package_key(package)
  local document = documents[key]
  local remote = document and document:match("^%a[%w+.-]+://")
  if document and document ~= "" then
    document = remote and document or pdf_file(document)
  else
    document = pdf_file(stem .. ".pdf")
      or pdf_file(directory(path) .. "/" .. package .. ".pdf")
      or pdf_file((stem:match("[^/]+$") or stem) .. ".pdf")
      or pdf_file(package .. ".pdf")
  end
  local info = {file = document, labels = {}, anchors = {}, numbers = {},
    titles = {}, pages = {}, names = {}}
  local visited = {}
  read_anchors(stem .. ".aux", info, visited)
  if document and not remote then
    -- A registered PDF may be in a separate build directory.
    read_anchors(document:gsub("%.[^./]+$", ".aux"), info, visited)
  end
  return info
end

reference_info = function(package, source)
  local key = package_key(package)
  local info = link_documents[key]
  if not info then
    info = document_info(package, source)
    link_documents[key] = info
  end
  return info
end

local function reference_anchor(info, label, number, title)
  if not info.loaded_names then
    if not info.file:match("^%a[%w+.-]+://") then
      info.names, info.checked = destinations(info.file)
    end
    info.loaded_names = true
  end
  local anchor = info.anchors[label]
  if anchor and info.checked and not info.names[anchor] then anchor = nil end
  if not anchor and info.names[label] then anchor = label end
  if not anchor and not info.labels[label] and number then
    local depth = select(2, number:gsub("%.", "")) + 1
    local level = section_levels[depth]
    local candidate = level and (level .. "." .. number)
    -- Installed manuals often omit .aux files. Use the standard destination
    -- only when it actually exists in the PDF; otherwise open the manual.
    if candidate and info.names[candidate] then anchor = candidate end
  end
  if not anchor and title then
    -- Unnumbered headings have no standard numbered destination. Accept only
    -- one distinct destination whose bookmark title matches the source title.
    local wanted, matched = plain_text(title), nil
    for name, dest in pairs(info.names) do
      if dest.title == wanted then
        if matched and matched ~= dest then return nil end
        anchor, matched = name, dest
      end
    end
  end
  return anchor
end

reference_value = function(info, label, entry, field)
  if not info.file then return nil end
  local number = entry.number
  local anchor = reference_anchor(info, label, number, entry.title)
  local dest = anchor and info.names[anchor]
  if dest then
    if field == "page" then return dest.page end
    local title = dest.title
    if title and number then
      title = title:gsub("^" .. number:gsub("([^%w])", "%%%1") .. "%s+", "")
    end
    return title
  end
end

function M.link_target(package, label)
  local key = package_key(package)
  label = trim(label)
  local info = link_documents[key]
  if not info or not info.file then return nil end
  local entry = cache[key] and cache[key][label]
  local anchor = reference_anchor(info, label, entry and entry.number, entry and entry.title)
  return info.file, anchor or ""
end

return M
