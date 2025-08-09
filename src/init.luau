local process = require("@lune/process")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local fileSeparator = process.os == "windows" and "\\" or "/"

local Bundler = {}

function Bundler.IsBundleable(inputFilePath: string): (boolean, string?)
    local fileExtension = string.match(inputFilePath, `.?([^.{fileSeparator}/]*)$`)
    if fileExtension ~= "rbxm" then
        return false, "The input file's extension is not supported."
    end

    if not fs.isFile(inputFilePath) then
        return false, "The input file does not exist."
    end

    local readSuccess, readRet = pcall(fs.readFile, inputFilePath)
    if not readSuccess then
        return false, readRet
    end

    local function checkChildren(children: {Instance}): (boolean, string?)
        for _, child in children do
            local ok, reason = checkChildren(child:GetChildren())
            if not ok then
                return false, reason
            end

            if (not child:IsA("LuaSourceContainer")) and child.ClassName ~= "Folder" then
                return false, `The instance '{child:GetFullName()}' is of class '{child.ClassName}', which is not supported.`
            end
        end

        return true, nil
    end

    local serdeSuccess, serdeRet = pcall(roblox.deserializeModel, readRet)
    if not serdeSuccess then
        return false, (serdeRet :: any) :: string
    end

    return checkChildren(serdeRet :: {roblox.Instance & Instance}) --// To get Luau LSP's type definitions
end

function Bundler.Bundle(input: string, trackLines: boolean, rootOverridePath: string, _environmentName: string?, logFn: (message: string) -> ()): string
    local environmentName = _environmentName or "SolderRuntime"
    local modelRoot = roblox.deserializeModel(input)

    if rootOverridePath then
        local paths = string.split(rootOverridePath, ".")

        for _, childName in paths do
            local oldModelRoot = modelRoot
            for _, childInstance in modelRoot do
                if childInstance.Name == childName then
                    modelRoot = childInstance:GetChildren()
                end
            end

            if modelRoot == oldModelRoot then
                error(`An instance named '{childName}' could not be found in the root override '{rootOverridePath}'.`)
            end
        end
    end

    local currentPath = debug.info(1, "s") :: string
    local bundledModule = fs.readFile(currentPath .. "/../src/Snippets/BundledModule.luau")
    local closuresMarkerLineNumber = table.find(string.split(string.gsub(bundledModule, "\r", ""), "\n"), "--MARKER:CLOSURES") :: number --// Stupid CRLF

    assert(type(closuresMarkerLineNumber) == "number", "must be a number")

    local closuresString = ""
    local lines: {number} = {}
    local chunkNames: {string} = {}
    local entryPoints: {number} = {}

    local currentClosureId = 0
    local everAddedParent = false
    local lastVisitedInstance: roblox.Instance

    local function visitChildrenAndBuildStrings(children: {roblox.Instance}): string
        local parentClosureId = currentClosureId
        local scripts = ""

        for _, child in children do
            local childFullName = child:GetFullName()
            logFn(`Visiting '{childFullName}'...`)

            local childChildren = child:GetChildren()
            local addedDoScope = false

            if (not lastVisitedInstance) or lastVisitedInstance.Parent ~= child.Parent then
                local doScope = everAddedParent and "do\n" or ""
                if not child:IsA("LuaSourceContainer") then
                    addedDoScope = everAddedParent
                    scripts ..= `{doScope}local _parent = SolderInstance.new("{child.Name}", "{child.ClassName}", {if child.Parent then "_parent" else "script.Parent"}, {#childChildren})\n`
                end

                everAddedParent = true
            end

            lastVisitedInstance = child

            if not child:IsA("LuaSourceContainer") then
                if #childChildren ~= 0 then
                    local childScripts = visitChildrenAndBuildStrings(childChildren)
                    scripts ..= `do\n{childScripts}end\n`
                end

                if addedDoScope then
                    scripts ..= `end\n`
                end

                continue
            end

            --// It's a LuaSourceContainer, so we increment the currentClosureId
            currentClosureId += 1

            if trackLines then
                local linesCount = #string.split(closuresString, "\n")
                table.insert(lines, closuresMarkerLineNumber + linesCount + 1)
                table.insert(chunkNames, `"{childFullName}"`)
            end

            if child.ClassName ~= "ModuleScript" then
                table.insert(entryPoints, currentClosureId)
            end

            local scriptSource = (child :: ((LocalScript | ModuleScript | Script) & roblox.Instance)).Source

            logFn(`Compile-checking '{childFullName}'...`)
            local compileSuccess, reason = pcall(luau.compile, scriptSource)
            if not compileSuccess then
                error(`Failed to compile: {reason}`)
            end

            closuresString ..= string.format([==[function(require, script)
                return function(...)
                    %s
                end
            end,]==] .. "\n", (child :: ((LocalScript | ModuleScript | Script) & roblox.Instance)).Source)

            scripts ..= `scripts[{currentClosureId}] = SolderInstance.new("{child.Name}", "{child.ClassName}", _parent, {#childChildren})\n`

            if #childChildren ~= 0 then
                local preClosureId = currentClosureId
                local childScripts = visitChildrenAndBuildStrings(childChildren)
                scripts ..= `do\nlocal _parent = scripts[{preClosureId}]\n{childScripts}end\n`
            end

            if addedDoScope then
                scripts ..= `end\n`
            end
        end

        scripts ..= `_parent = nil\n`
        return scripts
    end

    local scriptsStringsLines = string.split(visitChildrenAndBuildStrings(modelRoot), "\n")
    local scriptsStrings = ""
    local indent = 0
    for idx, line in scriptsStringsLines do
        if line == "end" then
            indent -= 1
        end

        scriptsStrings ..= string.rep("\t", indent) .. line .. "\n"

        if line == "do" then
            indent += 1
            continue
        end
    end

    local moduleWithScripts = string.gsub(bundledModule, "--MARKER:SCRIPTS", scriptsStrings)
    local moduleWithClosures = string.gsub(moduleWithScripts, "--MARKER:CLOSURES", closuresString)
    local moduleWithChunkNames = string.gsub(moduleWithClosures, "--MARKER:CHUNKNAMES", table.concat(chunkNames, ","))
    local moduleWithTrackedLines = string.gsub(moduleWithChunkNames, "--MARKER:TRACKEDLINES", table.concat(lines, ","))
    local moduleWithEntryPoints = string.gsub(moduleWithTrackedLines, "--MARKER:ENTRYPOINTS", table.concat(entryPoints, ","))
    local moduleWithEnvironmentName = string.gsub(moduleWithEntryPoints, "--MARKER:ENVNAME", environmentName)

    return moduleWithEnvironmentName
end

return {
    Bundler = Bundler,
    SDK = require("@self/SDK")
}