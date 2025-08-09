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

## 📦 Installation

Solder runs on **Lune 0.10.1** and is designed to be installed via [Pesde](https://pesde.dev/):

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

## ⚙️ How It Works

1. **Traversal**, in terms recursively visiting the hierarchy, serializing each instance into an internal [`SolderInstance`](src/RuntimeTypes.luau).

2. **Closure Bundling**, which collects script sources as closures and injects them into [a prebuilt runtime module template](src/Snippets/BundledModule.luau).

3. **Output Generation**
   Writes the final Luau file containing:
   * All script sources (into "Virtual Closures")
   * Control-flow based instance hierarchy reconstruction logic (for memory efficiency)
   * Optional debug line mappings (if `--track-lines` is specified)
   * Custom environment name (defaults to `SolderRuntime` if not specified)

## 📋 Requirements

* **Pesde 0.7.0** or above
* Roblox `.rbxm` or `.rbxmx` model file as input
* Model must only contain:
  * Folders
  * Script / LocalScript / ModuleScript instances

## 📜 License

This project is licensed under the MIT License.
See [LICENSE](LICENSE.txt) for details.