local process = require("@lune/process")
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local LuaEncode = require("@pkg/luaencode")

local fileSeparator = process.os == "windows" and "\\" or "/"

local Bundler = {}

function Bundler.IsBundleable(inputFilePath: string): (boolean, string?)
    local fileExtension = string.match(inputFilePath, `.?([^.{fileSeparator}/]*)$`)
    if fileExtension ~= "luau" and fileExtension ~= "rbxm" then
        return false, "The file extension is not supported."
    end

    if not fs.isFile(inputFilePath) then
        return false, "The file does not exist."
    end

    if fileExtension == "luau" then
        return true
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

function Bundler.Bundle(input: string, trackLines: boolean, rootOverride: string, logFn: (message: string) -> ()): string
    local paths = string.split(rootOverride, ".")
    local modelRoot = roblox.deserializeModel(input)

    if rootOverride then
        for _, childName in paths do
            local oldModelRoot = modelRoot
            for _, childInstance in modelRoot do
                if childInstance.Name == childName then
                    modelRoot = childInstance:GetChildren()
                end
            end

            if modelRoot == oldModelRoot then
                error(`An instance named '{childName}' could not be found in the root override '{rootOverride}'.`)
            end
        end
    end

    for _, child in modelRoot do
        
    end
end

return Bundler