# Solder

**Solder** is a `.rbxm` / `.rbxmx` bundler written in **Luau** for the [Lune](https://lune-org.github.io/docs) runtime.

It packages Roblox model files containing only scripts and folders into a single Luau module, ready to be distributed or embedded. This makes Solder especially useful for security projects that require embedding or distributing Roblox scripts in a controlled and verifiable way.

The bundling process preserves your project's hierarchy, can optionally track original line numbers for better debugging, and supports custom environment naming for error reporting.

## ✨ Features

- **Bundle `.rbxm` / `.rbxmx` files** into a standalone Luau module
- **Customizable environment name** shown in runtime errors
- **Optional line tracking** for accurate error locations
- **Root override** to start bundling from a specific path inside the model
- **Quiet mode** for scripting/automation
- **Validation** to ensure input models contain only supported instance types:
  - `Folder`
  - `Script`
  - `LocalScript`
  - `ModuleScript`

## 💻 Installation

Solder runs on **Lune 0.10.1** and is designed to be installed via **[Pesde](https://pesde.dev/) 0.7.0**:

```sh
pesde install 1suite/solder
```

## 🚀 Usage

```sh
solder [options]

# Alternatively you can use it outside a pesde project like this:

pesde x 1suite/solder [options]
```

### Options

| Option                   | Description                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------- |
| `--help`                 | Show help and exit                                                                 |
| `--version`              | Show version information                                                           |
| `--input <file>`         | Path to the `.rbxm` / `.rbxmx` file to bundle                                      |
| `--output <file>`        | Path to write the bundled output                                                   |
| `--quiet`                | Suppress non-essential output                                                      |
| `--track-lines`          | Store original line offsets for better debugging                                   |
| `--override-root <path>` | Start bundling from a specific model path (e.g. `SomeFolder.MainHandler`)          |
| `--env-name <name>`      | Set the environment name displayed in runtime errors (defaults to `SolderRuntime`) |

## 📄 Examples

### Basic bundling

```sh
solder --input MyModel.rbxm --output BundledModule.luau
```

### With line tracking and custom environment name

```sh
solder \
  --input MyModel.rbxm \
  --output BundledModule.luau \
  --track-lines \
  --env-name "MyRuntime"
```

### Bundling from a specific folder inside the model

```sh
solder \
  --input MyModel.rbxm \
  --output BundledModule.luau \
  --override-root "Server.MainHandler"
```

## 🛠️ Using the Runtime SDK

To use the runtime SDK with a syncing tool such as Rojo, simply require the module like this in your Luau code:

```luau
-- replace the @pkg alias with the require alias you use for packages
local solder = require("@pkg/solder").SDK
```

With this, you gain a virtual solder table that can be utilized in unbundled code, whether for testing or other use cases.

At runtime, this `require` call returns a table containing the `SDK` field. This `SDK` field resolves to the main `solder` table, which provides the core API accessible in your code.

### What You Get

The returned `solder` table includes:

* **`require`**: The real underlying `require` function, bypassing the virtualized version.
* **`environmentName`**: A string used as the environment name in unhandled error messages.
* **`script`**: The actual `script` global for the current Luau environment.
* **`lineTrackingEnabled`**: A boolean indicating if line tracking is enabled for this build.
* **`getRealLine(line: number): number`**: A function to convert a bundled file line number to the original source line number.

## 📦 Using the Lune Bundler API

If you append the `.Bundler` suffix to your require path, like this:

```luau
local bundler = require("@pkg/solder").Bundler
```

you will get access to the **Bundler API**, which provides additional functionality for bundling scripts programmatically and **is only compatible with the Lune runtime. It is not available on bundled models.**

## 📋 Requirements

* **Pesde 0.7.0** or above
* Roblox `.rbxm` or `.rbxmx` model file as input
* Model must only contain:
  * Folders
  * Script / LocalScript / ModuleScript instances

## 📜 License

This project is licensed under the MIT License.
See [LICENSE](LICENSE.txt) for details.