--// Types are duplicates from `RuntimeTypes.luau`
type Solder = {
    --[[
        Invokes the real `require` function, instead of the virtualized one.
    ]]
    require: typeof(require),

    --[[
        The environment name that will be emitted in unhandled errors.

        Example: `<SolderRuntime> • (SomeFolder.Handler): An unexpected error occured.`, where `SolderRuntime` is the environment name.
    ]]
    environmentName: string,

    --[[
        The "real script", aka the `script` global in the current Luau environment.

        May be nil if ran outside of Roblox, such as Luau runtimes like Lune.
    ]]
    script: LuaSourceContainer?,

    --[[
        Reports whether line tracking was enabled for this build.
    ]]
    lineTrackingEnabled: boolean,

    --[[
        Gets the "real line", aka the line that would be in the original file.

        Example: A module calls `solder.getRealLine` and passes line 7100, and the module starts at line 7000 in the bundled file, then it would return 100.
    ]]
    getRealLine: (line: number) -> number,
}

type SolderClassNames = "Folder" | "Script" | "LocalScript" | "ModuleScript"
type ISolderInstance = {
    ClassName: SolderClassNames,
    Parent: SolderInstance?,
    Name: string,

    Children: {SolderInstance}
}

type SolderInstanceImpl = {
    __index: SolderInstanceImpl,
    new: (name: string, className: SolderClassNames, parent: SolderInstance?, childrenSize: number?) -> SolderInstance,

    GetFullName: (self: SolderInstance) -> string,
    FindFirstChild: (self: SolderInstance, name: string, recursive: boolean?) -> SolderInstance?,
    WaitForChild: (self: SolderInstance, name: string, timeout: number?) -> SolderInstance?, --// Note that timeout is ignored.
}

type SolderInstance = typeof(setmetatable({} :: ISolderInstance, {} :: SolderInstanceImpl))

type SolderInitClosure = (solder: Solder, require: typeof(require), script: (SolderInstance & LuaSourceContainer)?) -> ((...any?) -> any?)

local closures: {SolderInitClosure} = {
--MARKER:CLOSURES
}

local lineOffsets: {number} = {
--MARKER:TRACKEDLINES
}

local chunkNames: {string} = {
--MARKER:CHUNKNAMES
}

local SolderInstance = {} :: SolderInstanceImpl
SolderInstance.__index = SolderInstance --// For typechecking
rawset(SolderInstance, "__index", function(self: SolderInstance, index: string): any | SolderInstance
    local solderMethod = SolderInstance[index]
    if solderMethod then
        return solderMethod
    end

    local child = self:FindFirstChild(index)
    if (not child) and index ~= "Parent" then
        error(`{index} is not a valid member of {self.ClassName} "{self:GetFullName()}"`, 2)
    end

    return child
end)

function SolderInstance.new(name, className, parent, childrenSize)
    local self = setmetatable({
        Name = name,
        ClassName = className,
        Parent = parent,
        Children = table.create(childrenSize or 0),
    } :: ISolderInstance, SolderInstance)

    if parent then
        table.insert(parent.Children, self)
    end

    return self
end

function SolderInstance:FindFirstChild(name, recursive)
    for _, child in self.Children do
        if child.Name == name then
            return child
        end

        if not recursive then
            continue
        end

        local potentialChild = child:FindFirstChild(name, recursive)
        if potentialChild then
            return potentialChild
        end
    end

    return nil
end

function SolderInstance:GetFullName()
    local fullName = self.Name

    local parent = self.Parent
    while parent do
        fullName = `{parent.Name}.{fullName}`
        parent = parent.Parent
    end

    return fullName
end

local scripts: {[number]: SolderInstance} = {}
--MARKER:SCRIPTS

local entryPoints: {number} = {
--MARKER:ENTRYPOINTS
}

local solder = {} :: Solder

solder.require = require
solder.environmentName = [[--MARKER:ENVNAME]]
solder.script = script
solder.lineTrackingEnabled = #lineOffsets ~= 0

local lineCache: {number} = {}
solder.getRealLine = function(line)
    if not solder.lineTrackingEnabled then
        error("solder::getRealLine is not available because line tracking is disabled.", 2)
    end

    if lineCache[line] then
        return lineCache[line]
    end

    local closest: number = lineOffsets[1]
    local closestDifference = math.huge

    for _, lineOffset in lineOffsets do
        if lineOffset - 1 < line then
            local difference = line - lineOffset
            if difference < closestDifference then
                closestDifference = difference
                closest = lineOffset
            end
        end
    end

    local realLine = (line - closest) + 1
    lineCache[line] = realLine

    return realLine
end

local constructorDebugLine = debug.info(SolderInstance.new, "l") :: number
local function buildErrorTree(closureId: number, message: string): string
    local treeBranchMiddle, treeBranchEnd = "├", "└"

    local errorLine = debug.info(3, "l")
    local errorDisplayLine = errorLine ~= -1 and `:{solder.getRealLine(errorLine)}` or ""
    local displayMessage = `<{solder.environmentName}> • ({chunkNames[closureId] or "?"}{errorDisplayLine}): \`{message}\``

    for level = 4, math.huge do
        local line = debug.info(level, "l")
        local nextLine = debug.info(level + 1, "l")
        if (not line) then
            break
        end

        if line == -1 or line >= constructorDebugLine then
            continue --// skip C closures & internal closures
        end

        local displayLine = solder.getRealLine(line)
        local branchCharacter = (nextLine and nextLine ~= -1) and treeBranchMiddle or treeBranchEnd
        displayMessage ..= `\n\t{branchCharacter} '{chunkNames[closureId] or "?"}', line {displayLine}`
    end

    return displayMessage
end

local isRobloxEnv = solder.script and true or false
local cachedRequires: {[SolderInstance]: any} = {}
local function errorIfInvalidRet(ret: {[number]: any, n: number}): ()
    ret.n -= 1 --// adjust for pcall result
    local isInvalidRet = isRobloxEnv and ret.n ~= 1 or ret.n < 1
    local isInvalidType = false

    if not isRobloxEnv then
        for idx: string | number, value in ret do
            if idx == "n" then
                continue
            end

            local valueType = type(value)
            if valueType ~= "table" and valueType ~= "function" then
                isInvalidType = true
                break
            end
        end
    end

    if isInvalidRet and isRobloxEnv then
        return error("Module code did not return exactly one value", 4)
    elseif isInvalidRet then
        return error("module must return a value", 4)
    elseif isInvalidType then
        return error("module must return a table or function", 4)
    end
end

local function getInvalidTargetError(target: string, default: string): string
    if isRobloxEnv then
        return `Unable to require module from given path '{target}'`
    end

    return default
end

local function getInvalidComponentError(target: string, component: string)
    return getInvalidTargetError(target, `error requiring module "{target}": could not resolve child component "{component}"`)
end

local function getClosureFromSolderInstance(target: SolderInstance): SolderInitClosure
    return closures[table.find(scripts, target) :: number]
end

local internalSolderInstanceRequire = nil

local solderInstanceIndex = SolderInstance.__index
local function makeVirtualRequire(script: SolderInstance): typeof(require)
    local function virtualRequire(target: any): any
        local targetType = type(target)
        local isSolderInstance = targetType == "table" and type(getmetatable(target)) == "table" and getmetatable(target).__index == solderInstanceIndex
        if (not isSolderInstance) and targetType ~= "string" then
            if isRobloxEnv then
                error("Attempted to call require with invalid argument(s).", 2)
            end

            error(`invalid argument #1 to 'require' (string expected, got {targetType})`, 2)
        end

        if isSolderInstance and (target :: SolderInstance).ClassName ~= "ModuleScript" then
            error("Attempted to call require with invalid argument(s).", 2)
        elseif isSolderInstance then
            return internalSolderInstanceRequire(target)
        end

        local components = string.split(target, "/")
        local currentInstance: SolderInstance
        local pathPrefix = string.sub(components[1], 1, 1)
        if pathPrefix == "@" and components[1] ~= "@self" then
            error(getInvalidTargetError(target, `error requiring module "{target}": {components[1]} is not a valid alias`), 2)
        end

        if components[1] ~= ".." and components[1] ~= "." and pathPrefix ~= "@" then
            error(getInvalidTargetError(target, `error requiring module "{target}": require path must start with a valid prefix: ./, ../, or @`), 2)
        end

        if components[1] == "@self" then
            currentInstance = script
        elseif components[1] == "." then
            if not script.Parent then
                error(getInvalidComponentError(target, "./"), 2)
            end

            currentInstance = script.Parent
        else
            if (not script.Parent) or (not script.Parent.Parent) then
                error(getInvalidComponentError(target, "../"), 2)
            end

            currentInstance = script.Parent.Parent
        end

        for idx = 2, #components do
            local component = components[idx]
            if component == "." and (not script.Parent) then
                error(getInvalidComponentError(target, "./"), 2)
            elseif component == "." then
                currentInstance = script.Parent :: SolderInstance
                continue
            end

            if component == ".." and ((not script.Parent) or (not script.Parent.Parent)) then
                error(getInvalidComponentError(target, "../"), 2)
            elseif component == ".." then
                currentInstance = (script.Parent :: SolderInstance).Parent :: SolderInstance
                continue
            end

            local instance = currentInstance:FindFirstChild(component)
            if not instance then
                error(getInvalidComponentError(target, component), 2)
            end

            currentInstance = instance
        end

        if currentInstance.ClassName ~= "ModuleScript" then --// No need to check for isRobloxEnv, as every script is a ModuleScript except the entry point if bundled for vanilla Luau / Lune
            error(`Unable to require module from given path '{target}'`, 2)
        end

        return internalSolderInstanceRequire(currentInstance)
    end

    return virtualRequire
end

internalSolderInstanceRequire = function(target: SolderInstance): {boolean | any?}
    if cachedRequires[target] then
        return cachedRequires[target]
    end

    local closure = getClosureFromSolderInstance(target)(solder, makeVirtualRequire(target), target :: (LuaSourceContainer & SolderInstance))
    local output = table.pack(pcall(closure))
    if not output[1] then
        if isRobloxEnv then
            error("Requested module experienced an error while loading", 3)
        end

        error(output[2], 3)
    end

    table.remove(output, 1)
    errorIfInvalidRet(output)

    return table.unpack(output)
end

for _, entryPointIdx in entryPoints do
    local virtualScript = scripts[entryPointIdx] --// They're still used internally to represent files

    local closure = closures[entryPointIdx](solder, makeVirtualRequire(virtualScript), (isRobloxEnv and virtualScript or nil) :: (SolderInstance & LuaSourceContainer)?)

    if solder.lineTrackingEnabled then
        task.spawn(xpcall, closure, function(message)
            warn(buildErrorTree(entryPointIdx, message))
        end)
    else
        task.spawn(closure)
    end
end