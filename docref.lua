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
-- Version: 0.1
-- Date: 2026-10-23



local M = {}

local ok_lfs, lfs_module = pcall(require, "lfs")
local lfs = ok_lfs and lfs_module or nil

local levels = {
  "section",
  "subsection",
  "subsubsection",
  "paragraph",
  "subparagraph"
}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
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

  if not name:match("%.[^/\\]+$") then
    return find_file(name .. ".tex", base, broad_search)
  end

  error("Cannot find source file: " .. name)
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

  s = s:gsub("\\begin%s*{macrocode%*?}.-\\end%s*{macrocode%*?}", "")
  s = s:gsub("\\begin%s*{verbatim%*?}.-\\end%s*{verbatim%*?}", "")
  s = strip_comments(s)
  s = expand_inputs(s, path:match("^(.*)[/\\]") or ".")

  active[path] = nil
  return s
end

local function make_reference(source, label)
  dependencies = {}
  active = {}

  local s = expand_file(source, nil, true)

  local start = s:find("\\begin%s*{document}")
  if start then
    s = s:sub(start)
  end

  local counts = {}
  for i = 1, #levels do
    counts[i] = 0
  end

  local target = "\\label%s*{%s*"
    .. label:gsub("([^%w])", "%%%1")
    .. "%s*}"

  local pos, found = 1, false

  while pos <= #s do
    local a, b = s:find("\\([%a@]+)%*?", pos)
    if not a then
      break
    end

    local command = s:sub(a + 1, b):gsub("%*$", "")
    local level

    for i, name in ipairs(levels) do
      if command == name then
        level = i
        break
      end
    end

    local label_at = s:find(target, pos)
    if label_at and label_at < a then
      found = true
      break
    end

    if level then
      counts[level] = counts[level] + 1
      for i = level + 1, #levels do
        counts[i] = 0
      end
    end

    pos = b + 1

    if label_at and label_at >= a then
      local next_command = s:find("\\[%a@]+%*?", pos)
      if not next_command or label_at < next_command then
        found = true
        break
      end
    end
  end

  assert(found, "Cannot locate label '" .. label .. "' in " .. source)

  local parts = {}
  for _, n in ipairs(counts) do
    if n > 0 then
      parts[#parts + 1] = tostring(n)
    end
  end

  assert(#parts > 0, "Cannot determine section number for " .. label)

  return table.concat(parts, "."), dependencies
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

  for _, name in ipairs(candidate_names(package)) do
    tried[#tried + 1] = name

    local ok, f = pcall(find_file, name, nil, true)
    if ok and f then
      f:close()
      return name
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

local CACHE_VERSION = "1"
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

function M.register(package, source)
  local key = package_key(package)
  source = trim(source)

  assert(key ~= "", "Package name must not be empty")
  assert(source ~= "", "Source file name must not be empty")

  -- Do not delete old cache records. A different source automatically
  -- invalidates them during the next reference.
  sources[key] = source
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

function M.reference(package, label)
  local key = package_key(package)
  label = trim(label)

  assert(key ~= "", "Package name must not be empty")
  assert(label ~= "", "Label must not be empty")

  cache[key] = cache[key] or {}
  local entry = cache[key][label]

  if entry
    and entry.source == (sources[key] or entry.source)
    and dependencies_valid(entry.deps)
  then
    texio.write_nl(
      "term and log",
      "docref cache HIT: " .. package .. " / " .. label
    )

    return entry.number
  end

  texio.write_nl(
    "term and log",
    "docref cache MISS: " .. package .. " / " .. label
  )

  local source = sources[key] or find_package_source(package)
  local number, deps = make_reference(source, label)

  cache[key][label] = {
    number = number,
    source = source,
    deps = deps
  }


append_cache(package, label, number, source, deps)


  texio.write_nl(
    "term and log",
    source .. ": " .. label .. " = " .. number
  )

  return number
end

return M