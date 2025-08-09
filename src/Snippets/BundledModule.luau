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
    ]]
    script: LuaSourceContainer,

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
    Parent: (Instance | SolderInstance)?,
    Name: string,

    _Children: {SolderInstance}
}

type SolderInstanceImpl = {
    __index: SolderInstanceImpl,
    new: (name: string, className: SolderClassNames, parent: typeof(({} :: ISolderInstance).Parent), childrenSize: number?) -> SolderInstance,

    GetFullName: (self: SolderInstance) -> string,
    FindFirstChild: (self: SolderInstance, name: string, recursive: boolean?) -> SolderInstance?,
    WaitForChild: (self: SolderInstance, name: string, timeout: number?) -> SolderInstance?, --// Note that timeout is ignored.
    GetChildren: (self: SolderInstance) -> typeof(({} :: ISolderInstance)._Children)
}

type SolderInstance = typeof(setmetatable({} :: ISolderInstance, {} :: SolderInstanceImpl))

type SolderInitClosure = (require: typeof(require), script: (SolderInstance & LuaSourceContainer)?) -> ((...any?) -> ...any?)

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
        _Children = table.create(childrenSize or 0),
    } :: ISolderInstance, SolderInstance)

    if parent and typeof(parent) ~= "Instance" then
        table.insert((parent :: SolderInstance)._Children, self)
    end

    return self
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

function SolderInstance:FindFirstChild(name, recursive)
    for _, child in self._Children do
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

function SolderInstance:WaitForChild(name, timeout)
    --// Timeout is ignored
    return self:FindFirstChild(name)
end

function SolderInstance:GetChildren()
    return self._Children
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

local cachedRequires: {[SolderInstance]: any} = {}
local function errorIfInvalidRet(ret: {[number]: any, n: number}): ()
    if ret.n ~= 2 then --// adjust for pcall result
        error("Module code did not return exactly one value", 4)
    end
end

local function getClosureFromSolderInstance(target: SolderInstance): (SolderInitClosure, number)
    local closureId = table.find(scripts, target) :: number
    return closures[closureId], closureId
end

local internalSolderInstanceRequire = nil

local sdkTable = { SDK = solder }
local solderInstanceIndex = SolderInstance.__index
local function makeVirtualRequire(script: SolderInstance): typeof(require)
    local function virtualRequire(target: any): any
        local targetType = type(target)
        local isSolderInstance = targetType == "table" and type(getmetatable(target)) == "table" and getmetatable(target).__index == solderInstanceIndex

        if (not isSolderInstance) and targetType ~= "string" and targetType ~= "number" then
            error("Attempted to call require with invalid argument(s).", 2)
        end

        if targetType == "number" then
            return (require)(target) --// Wrapping require to silence warning
        end

        if isSolderInstance and (target :: SolderInstance).ClassName ~= "ModuleScript" then
            error("Attempted to call require with invalid argument(s).", 2)
        elseif isSolderInstance then
            return internalSolderInstanceRequire(target)
        end

        if targetType == "string" and string.match(target, "^@%w+/solder$") then
            return sdkTable
        end

        local components = string.split(target, "/")
        local currentInstance: SolderInstance
        local pathPrefix = string.sub(components[1], 1, 1)
        if pathPrefix == "@" and components[1] ~= "@self" then
            error(`Unable to require module from given path '{target}'`, 2)
        end

        if components[1] ~= ".." and components[1] ~= "." and pathPrefix ~= "@" then
            error(`Unable to require module from given path '{target}'`, 2)
        end

        if components[1] == "@self" then
            currentInstance = script
        elseif components[1] == "." then
            if not script.Parent then
                error(`Unable to require module from given path '{target}'`, 2)
            end

            currentInstance = script.Parent :: SolderInstance
        else
            if (not script.Parent) or (not script.Parent.Parent) then
                error(`Unable to require module from given path '{target}'`, 2)
            end

            currentInstance = (script.Parent :: SolderInstance).Parent :: SolderInstance
        end

        for idx = 2, #components do
            local component = components[idx]
            if component == "." and (not script.Parent) then
                error(`Unable to require module from given path '{target}'`, 2)
            elseif component == "." then
                currentInstance = script.Parent :: SolderInstance
                continue
            end

            if component == ".." and ((not script.Parent) or (not script.Parent.Parent)) then
                error(`Unable to require module from given path '{target}'`, 2)
            elseif component == ".." then
                currentInstance = (script.Parent :: SolderInstance).Parent :: SolderInstance
                continue
            end

            local instance = currentInstance:FindFirstChild(component)
            if not instance then
                error(`Unable to require module from given path '{target}'`, 2)
            end

            currentInstance = instance
        end

        if currentInstance.ClassName ~= "ModuleScript" then
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

    local closure, closureId = getClosureFromSolderInstance(target)
    local output = table.pack(xpcall(closure(makeVirtualRequire(target), target :: (LuaSourceContainer & SolderInstance)), function(message)
        warn(buildErrorTree(closureId, message))
    end))

    if not output[1] then
        error("Requested module experienced an error while loading", 3)
    end

    table.remove(output, 1)
    errorIfInvalidRet(output)

    return table.unpack(output)
end

for _, entryPointIdx in entryPoints do
    local virtualScript = scripts[entryPointIdx]
    local closure = closures[entryPointIdx](makeVirtualRequire(virtualScript), virtualScript :: (SolderInstance & LuaSourceContainer))

    if solder.lineTrackingEnabled then
        task.spawn(xpcall, closure, function(message)
            warn(buildErrorTree(entryPointIdx, message))
        end)
    else
        task.spawn(closure)
    end
end