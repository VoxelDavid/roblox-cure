
--[[
  This is Cure's build file. It compiles everything under the source directory
  into a Roblox-compatible XML file that you can drag-and-drop into your game.

  You'll need a Lua interpreter and the LuaFileSystem module installed to run
  this file. In Windows this can be done by installing LuaForWindows[1], which
  comes bundled with LuaFileSystem.

  [1] https://code.google.com/p/luaforwindows/
--]]

local lfs = require "lfs"

if _VERSION == "Lua 5.2" then
  unpack = table.unpack
end





--[[
  Configuration
  ==============================================================================
--]]

--[[
  Array of alternative paths to output the contents of the model. You must
  specify the full file path and extension.
--]]
local LOCATIONS = {
  -- "output.rbxmx",
  -- "test/game.rbxmx"
}

--[[
  Where source code is stored and compiled to
--]]
local SOURCE_DIR = "source"
local BUILD_DIR  = "build"

--[[
  The name and extension of the Model file that will be generated.

  [1] Roblox only supports two extensions: rbxm and rbxmx. The former uses
      binary while the latter uses XML. Because this build only compiles to
      XML, the rbxmx file extension is prefered.
--]]
local RBXM_FILE_NAME = "cure"
local RBXM_FILE_EXT  = ".rbxmx" -- [1]
local RBXM_FILE = RBXM_FILE_NAME..RBXM_FILE_EXT

--[[
  The instance that will be used to replicate the folder structure. Any
  instance can be used, but Folders are recommended.
--]]
local CONTAINER_CLASS = "Configuration"

-- maximum length of strings in replicated instances
local MAX_STRING_LENGTH = 200000 - 1





--[[
  Helpers
  ==============================================================================
--]]

function isDir(dir)
  return lfs.attributes(dir, "mode") == "directory"
end

local function splitName(path)
  for i = #path, 1, -1 do
    local c = path:sub(i, i)
    if c == "." then
      return path:sub(1, i-1), path:sub(i+1, #path)
    end
  end
  return path, ""
end

-- Extract the contents of a file
local function getFileContents(path)
  local file = assert(io.open(path))
  local content = file:read("*a")
  file:close()

  return content
end





--[[
  XML
  ==============================================================================
--]]

local xml = {
  -- Global indentation for the RBXM file. This is modified by the indent method
  -- to increase and decrease the indentation of XML elements.
  indentLevel = 1,

  -- Characters that need to be escaped before being added to the XML string.
  escapeChars = {
    ["\""] = "quot",
    ["&"]  = "amp",
    ["'"]  = "apos",
    ["<"]  = "lt",
    [">"]  = "gt"
  }
}

--[[
  Create a new XML object. Each instance has a 'contents' property which
  contains each line of XML you write to it as a string.

  The strings in 'contents' are later concatenated together to be output
  to a file.

    local test = xml:new()
    test:write("<name>")
    test:indent(1):write("<first>John</first>")
    test:indent(1):write("<last>Smith</last>")
    test:write("</name>")

    -- <name>
    --   <first>John</first>
    --   <last>Smith</last>
    -- </name>
--]]
function xml:new(opts)
  local opts = opts or {}
  opts.contents = opts.contents or {}  -- [1]

  setmetatable(opts, self)
  self.__index = self
  return opts
end

--[[
  Because of the way XML is parsed, leading spaces get truncated. So simply add
  a "\" when a space or "\" is detected as the first character. This will be
  decoded automatically by Cure
--]]
function xml:encodeTruncEsc(str)
  local first = str:sub(1,1)
  if first:match("%s") or first == "\\" then
    return "\\"..str
  end
  return str
end

--[[
  Certain characters need to be escaped to work properly in the XML. Because XML
  uses < and > to denote tags, they have to be escaped to &lt; and &gt; for use
  in properties and scripts.
--]]
function xml:escape(str)
  local out = ""
  for i = 1, #str do
    local char = str:sub(i,i)
    if self.escapeChars[char] then
      char = "&"..self.escapeChars[char]..";"
    elseif not char:match("^[\10\13\32-\126]$") then
      char = "&#"..char:byte()..";"
    end
    out = out..char
  end
  return out
end

--[[
  Append the arguments onto the self.contents table. Later on, all the strings
  in self.contents are concatenated into a single string, which gets turned into
  an XML file.
--]]
function xml:concat(...)
  local args = {...}

  local function concat(arg)
    if type(arg) == "table" then
      concat(unpack(arg))
    else
      self.contents[#self.contents+1] = tostring(arg)
    end
  end

  for i = 1, #args do
    concat(args[i])
  end
end

--[[
  Indents a line to make reading the XML easier. Who wants to read unindented
  markup?

  An indent size of 0 will not indent the line. Note that indentation is
  relative to the previous line's indentation.

  Example:

    <roblox ...>
      <Item class="Script">                   -- xml:indent( 1)
        <Properties>                          -- xml:indent( 1)
          <string name="Name">Script</string> -- xml:indent( 1)
          <ProtectedString name="Source"></ProtectedString> -- no indentation needed
        </Properties>                         -- xml:indent(-1)
      </Item>                                 -- xml:indent(-1)
    </roblox>

  @param number indentSize Number of times you want to indent the next lines.
--]]
function xml:indent(indentSize)
  if indentSize then
    xml.indentLevel = xml.indentLevel + indentSize
  end
  self:concat(string.rep("\t", xml.indentLevel))
  return self
end

--[[
  Append any number of values to a table containing XML strings.

  @param ... Any number of values that can be turned into a string.
--]]
function xml:write(...)
  self:concat(..., "\n")
  return self
end





--[[
  Roblox Models
  ==============================================================================
--]]

local rbxm = {
  -- ID used for the "referent" attribute. This value is incremented each time
  -- an object is converted to XML.
  objectId = 0
}

--[[
  Create a Value instance (Int, String, Bool, etc).

  @param string className  Any Roblox instance that ends in "Value"
  @param string name       Name of the Value
  @param any    value      Depends on which instance you use. If you're using a
                           StringValue then this must be a string.
--]]
function rbxm:createValue(className, name, value)
  return {
    ClassName = className .. "Value",
    Name = { "string", name },
    Value = { className:lower(), value }
  }
end

--[[
  Generate a new Script instance. Wrappers for this method are found below it.

  @param string className  Type of script. Eg. "Script" or "LocalScript"
  @param string name       Name of the script
  @param string source     The Lua source of the script
  @param bool   disabled   If the script can run automatically
--]]
function rbxm:createScript(className, name, source, disabled)
  local obj = {
    ClassName = className;
    Name = { "string", name };
    Source = { "ProtectedString", source };
  }

  if disabled then
    obj.Disabled = { "bool", true };
  end

  return obj
end

function rbxm:createServerScript(...)
  return self:createScript("Script", ...)
end

function rbxm:createLocalScript(...)
  return self:createScript("LocalScript", ...)
end

--[[
  Create an IntValue containing the ID of a Roblox asset. Things like Models,
  Decals and T-Shirts are all assets, and you can find their ID at the end of
  the URL.

  @param string name  Name of the value
  @param number value ID of a Roblox asset. The number at the end of the URL on
                      an item. Eg. 42891177, 40469899, 39053953
--]]
function rbxm:createAsset(name, value)
  content = tonumber(content)

  if not content then
    print("WARNING: content of `" .. file .. "` must be a number")
  end

  return createValue("Int", name, content)
end

--[[
  Split apart the contents of the file into multiple StringValues, contained
  inside a BoolValue.

  Example (varies, depending on size):

    extremely-large-file.lua

  Turns into:

    extremely-large-file
    - 1
    - 2
    - 3
    - etc.
--]]
function rbxm:splitFileParts(content)
  local chunk = MAX_STRING_LENGTH
  local length = #content
  local container = rbxm:createValue("Bool", name, true)

  for i = 1, math.ceil(length/chunk) do
    local a = (i - 1)*chunk + 1
    local b = a + chunk - 1
    b = b > length and length or b
    container[i] = rbxm:createValue("String", tostring(i), content:sub(a, b))
  end

  return container
end

--[[
  Lua files are checked for syntax errors. Note that a file with an error will
  still be built regardless.
--]]
function rbxm:checkScriptSyntax(source)
  local func, err = loadstring(source, "")
  if not func then
    print("WARNING: " .. err:gsub("^%[.-%]:", "line "))
  end
end

--[[
  The "referent" attribute is used as a unique identifier for each instance in
  the game. This increments the current objectId property to always return a
  unique value that can be used as the referent.
--]]
function rbxm:referent()
  self.objectId = self.objectId + 1
  return self.objectId
end

--[[
  Extract the properties from an instance.

  @param table object A table contaiing key/value pairs that replicate the
                      properties of a Roblox instance.

  [1] The ClassName is applied as an XML attribute and must be omitted from the
      list of properties.
  [2] Keep everything consistent by sorting the properties.
--]]
function rbxm:getProperties(object)
  local sorted = {}
  for k in pairs(object) do
    if type(k) == "string" and k ~= "ClassName" then -- [1]
      sorted[#sorted+1] = k
    end
  end
  table.sort(sorted) -- [2]
  return sorted
end

--[[
  Creates the body of the XML file. All of the Item tags with their properties
  are generated by this method.

  @param table object Tabularized directory structure that will be converted
                      into XML.

  [1] Indent the property list.
  [1] This needs to stay inside of the writeXML function, otherwise the
      properties won't change when recursing through new objects.
  [3] Recurse and add children.
--]]
function rbxm:body(object)
  local body = xml:new()

  local function writeXML(object)
    body:indent(0):write(string.format("<Item class=\"%s\" referent=\"RBX%s\">", object.ClassName, rbxm:referent()))
    body:indent(1):write("<Properties>")
    body:indent(1) -- [1]

    local props = rbxm:getProperties(object) -- [2]

    for i = 1, #props do
      local propName  = props[i]
      local propType  = object[propName][1]
      local propValue = tostring(object[propName][2])
      body:write(string.format("<%s name=\"%s\">%s</%s>", propType, propName, propValue, propType))
    end

    body:indent(-1):write("</Properties>")

    for i = 1, #object do -- [3]
      writeXML(object[i])
    end

    body:indent(-1):write("</Item>")
  end
  writeXML(object)

  return table.concat(body.contents)
end

--[[
  Runs tasks to compile the directory structure into an XML file.

  @param table object Tabularized directory structure that will be converted
                      into XML.
--]]
function rbxm:tabToStr(object)
  if type(object) ~= "table" then
    error("table expected", 2)
  end

  local body = self:body(object)
  local file = xml:new()
  file:write("<roblox "..
    "xmlns:xmime=\"http://www.w3.org/2005/05/xmlmime\" "..
    "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" "..
    "xsi:noNamespaceSchemaLocation=\"http://www.roblox.com/roblox.xsd\" "..
    "version=\"4\">")
  file:write(body)
  file:write("</roblox>")

  return table.concat(file.contents)
end

-- Saves an RBXM string or table.
function rbxm:save(var, filename)
  if type(var) == "table" then
    var = self:tabToStr(var)
  end
  if type(var) == "string" then
    local file = assert(io.open(filename, "w"))
    file:write(var)
    file:flush()
    file:close()
  else
    error("bad type", 2)
  end
end





--[[
  Cure
  ==============================================================================
--]]

local cure = {}

function cure:server(content)
  return rbxm:createServerScript("cure.server", content)
end

function cure:client(content)
  return rbxm:createLocalScript("cure.client", content)
end





--[[
  Compiling
  ==============================================================================
--]]

--[[
  Run functions for specific types of files.

  @param string path       Full path to the current file. LFS needs this to read
                           the file.
  @param string file       Name and extension of the file.
  @param bool   subfolder  Cure's scripts live in the root of the source dir, if
                           'subfolder' is true it's safe to assume that the
                           following scripts belong to Cure.
--]]
local function handleFile(path, file, subfolder)
  local content = getFileContents(path)
  local name, extension = splitName(file)
  local subName, subExtension = splitName(name)

  extension = extension:lower()
  subExtension = subExtension:lower()

  -- Special handling for the main Cure scripts
  if not subfolder then
    rbxm:checkScriptSyntax(content)

    if file:lower() == "cure.server.lua" then
      return cure:server(content)
    elseif file:lower() == "cure.client.lua" then
      return cure:client(content)
    end
  end

  if extension == "lua" then
    rbxm:checkScriptSyntax(content)

    if subExtension == "script" then
      return rbxm:createServerScript(subName, content)
    elseif subExtension == "localscript" then
      return rbxm:createLocalScript(subName, content)
    else
      local chunk = MAX_STRING_LENGTH
      local length = #content

      if length <= chunk then
        -- Create a StringValue to hold the source of the file
        return rbxm:createValue("String", name, content)
      else
        -- If the file is too big, split it into multiple parts
        return rbxm:splitFileParts(content)
      end
    end
  elseif ext == "asset" then
    -- Create an IntValue containing a Roblox AssetID
    return rbxm:createAsset(name, content)
  else
    -- Disable and comment out anything else
    return rbxm:createServerScript(name, "--[==[\n"..content.."\n--]==]", true)
  end
end

local function recurseDir(path, obj, r)
  print("DIR", path)

  for name in lfs.dir(path) do
    if name ~= ".." and name ~= "." and name ~= ".gitignore" then
      local joinedPath = path .. "/" .. name

      if isDir(joinedPath) then
        obj[#obj+1] = recurseDir(joinedPath, {
          ClassName = CONTAINER_CLASS,
          Name = { "string", name }
        }, true)
      else
        print("FILE", joinedPath)
        obj[#obj+1] = handleFile(joinedPath, name, r)
      end
    end
  end

  return obj
end

--[[
  Compile the directory structure and the source code into a Roblox-compatible
  file. Configure the paths and filenames at the top of this file.

  @param String args
    Arguments from the command-line. Only supports one argument, which alters
    the path that the model file is built to.
--]]
function compile(args)
  local rbxmObj = recurseDir(SOURCE_DIR, {
    ClassName = CONTAINER_CLASS,
    Name = { "string", "cure" }
  })

  local rbxmPath = BUILD_DIR.."/"..(args[1] or RBXM_FILE)

  -- Make sure the output directory exists
  lfs.mkdir(BUILD_DIR)

  -- Generate the model
  rbxm:save(rbxmObj, rbxmPath)

  -- Save the model to other locations
  for i,v in ipairs(LOCATIONS) do
    rbxm:save(rbxmObj, LOCATIONS[i])
  end
end

compile({...})
