--[[
    Command Line Interface
]]

assert(string.match(_VERSION, "^Lune 0.10.1"), "Solder requires running on Lune 0.10.1!")

type Option = "--help" | "--version" | "--input" | "--output" | "--quiet" | "--track-lines"

local Bundler = require("@self/Bundler")

local process = require("@lune/process")
local stdio = require("@lune/stdio")
local fs = require("@lune/fs")

local fileSeparator = process.os == "windows" and "\\" or "/"
local fileName, fileExtension = string.match(debug.info(1, "s"), `([^/{fileSeparator}]+)%.?([^.{fileSeparator}/]*)$`) --// Luau LSP / Typechecker bug

local CLI_HELP_TEXT = string.format([[
Usage:
    %s [options]

Options:
    --help                      Show this help message and exit.
    --version                   Show version information.
    --input <file>              Specify input file.
    --output <file>             Specify output file.
    --quiet                     Suppress non-essential output.
    --track-lines               Save the line offsets for debugging purposes in error messages.
    --override-root <path>      Define the path to start bundling at (if the input file is a Roblox Model).

Commands:
    init                    Initialize a new project.
    build                   Build the project.
]], if fileExtension == "exe" and process.os == "windows" then fileName elseif fileExtension then `{fileName}.{fileExtension}` else fileName)

local parsedArguments: {[Option]: boolean | string} = {}

local function failBecause(reason: string)
    stdio.ewrite(`<Solder> • {reason}\n\nPlease run this program with the '--help' option for more information.`)
    process.exit(1)
end

local supportedOptions = {"--help", "--version", "--input", "--output", "--quiet", "--track-lines"}
local optionToRead: Option
for _, argument in process.args do
    if (not optionToRead) and (argument ~= "--output" and argument ~= "--input") then
        parsedArguments[argument] = true
        continue
    elseif (not optionToRead) and (not table.find(supportedOptions, argument)) then
        failBecause(`Unknown option '{argument}'.`)
    elseif (not optionToRead) then
        optionToRead = argument
        continue
    end

    parsedArguments[optionToRead :: Option] = argument
    optionToRead = (nil :: Option?) :: Option
end

if parsedArguments["--help" :: Option] then
    stdio.write(CLI_HELP_TEXT)
    process.exit(0)
end

if parsedArguments["--version" :: Option] then
    stdio.write("Solder v0.1.0")
    process.exit(0)
end

if not parsedArguments["--input" :: Option] then
    failBecause("The option '--output' is missing or is invalid.")
end

if not parsedArguments["--output" :: Option] then
    failBecause("The option '--output' is missing or is invalid.")
end

local isQuiet = parsedArguments["--quiet" :: Option]
local function log(message: string): ()
    if isQuiet then
        return
    end

    stdio.write(`<Solder> • {message}\n`)
end

local bundleable, reason = Bundler.IsBundleable(parsedArguments["--input" :: Option] :: string)
if not bundleable then
    failBecause(reason :: string)
end

log("The input file is bundleable.")

Bundler.Bundle(fs.readFile(parsedArguments["--input" :: Option] :: string), parsedArguments["--track-lines" :: Option] :: boolean, log)