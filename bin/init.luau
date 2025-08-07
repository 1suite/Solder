--[[
    Command Line Interface
]]

assert(string.match(_VERSION, "^Lune 0.10.1"), "Solder requires running on Lune 0.10.1!")

type Option = "--help" | "--version" | "--input" | "--output" | "--quiet" | "--track-lines" | "--override-root" | "--env-name"

local Bundler = require("./src")

local process = require("@lune/process")
local stdio = require("@lune/stdio")
local serde = require("@lune/serde")
local fs = require("@lune/fs")

local CLI_HELP_TEXT = [[
Usage:
    solder [options]

Options:
    --help                      Show this help message and exit.
    --version                   Show version information.
    --input <file>              Specify input file.
    --output <file>             Specify output file.
    --quiet                     Suppress non-essential output.
    --track-lines               Save the line offsets for debugging purposes in error messages.
    --override-root <path>      Define the path to start bundling at (if the input file is a Roblox Model).
    --env-name <name>           Define the environment name of the bundled script.

Commands:
    init                    Initialize a new project.
    build                   Build the project.
]]

local parsedArguments: {[Option]: boolean | string} = {}

local function failBecause(reason: string)
    stdio.ewrite(`<Solder> • {reason}\n\nPlease run this program with the '--help' option for more information.`)
    process.exit(1)
end

local supportedOptions: {Option} = {"--help", "--version", "--input", "--output", "--quiet", "--track-lines", "--override-root", "--env-name"}
local optionsToReadValue = {"--input", "--output", "--override-root", "--env-name"}
local optionToRead: Option

for _, argument in process.args do
    if optionToRead then
        parsedArguments[optionToRead :: Option] = argument
        optionToRead = (nil :: Option?) :: Option
        continue
    end

    if (not table.find(supportedOptions, argument)) then
        failBecause(`Unknown option '{argument}'.`)
    end

    if (not table.find(optionsToReadValue, argument)) then
        parsedArguments[argument] = true
        continue
    end

    optionToRead = argument
end

if parsedArguments["--help" :: Option] then
    stdio.write(CLI_HELP_TEXT)
    process.exit(0)
end

if parsedArguments["--version" :: Option] then
    local binFilePath = debug.info(1, "s") :: string
    local readSuccess, readOutput = pcall(fs.readFile, binFilePath .. "/../pesde.toml")

    if not readSuccess then
        failBecause(`Failed to get the current version: {readOutput}`)
    end

    local serdeSuccess, serdeOutput = pcall(serde.decode, "toml" :: "toml", readOutput) --// Luau type checker tomfoolery
    if not serdeSuccess then
        failBecause(`Failed to get the current version: {serdeOutput}`)
    end

    local pesdeToml = serdeOutput :: { version: string }
    if not pesdeToml.version then
        failBecause(`Failed to get the current version: the 'version' string is not present in the 'pesde.toml' file.`)
    end

    stdio.write(`Solder {pesdeToml.version}`)
    process.exit(0)
end

if not parsedArguments["--input" :: Option] then
    failBecause("The option '--input' is missing or is invalid.")
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
local bundleSuccess, output = pcall(Bundler.Bundle,
    fs.readFile(parsedArguments["--input" :: Option] :: string),
    parsedArguments["--track-lines" :: Option] :: boolean,
    parsedArguments["--override-root" :: Option] :: string,
    parsedArguments["--env-name" :: Option] :: string,
    log
)

if not bundleSuccess then
    failBecause(`Failed to bundle: {output}`)
end

log("Writing output...")
local writeSuccess, err = pcall(fs.writeFile, parsedArguments["--output" :: Option] :: string, output)
if not writeSuccess then
    failBecause(`Failed to write output: {err}`)
end