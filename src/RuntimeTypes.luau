export type Solder = {
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
export type ISolderInstance = {
    ClassName: SolderClassNames,
    Parent: SolderInstance?,
    Name: string,

    _Children: {SolderInstance}
}

export type SolderInstanceImpl = {
    __index: SolderInstanceImpl,
    new: (name: string, className: SolderClassNames, parent: SolderInstance?, childrenSize: number?) -> SolderInstance,

    GetFullName: (self: SolderInstance) -> string,
    FindFirstChild: (self: SolderInstance, name: string, recursive: boolean?) -> SolderInstance?,
    WaitForChild: (self: SolderInstance, name: string, timeout: number?) -> SolderInstance?, --// Note that timeout is ignored.
    GetChildren: (self: SolderInstance) -> typeof(({} :: ISolderInstance)._Children)
}

export type SolderInstance = typeof(setmetatable({} :: ISolderInstance, {} :: SolderInstanceImpl))

return nil