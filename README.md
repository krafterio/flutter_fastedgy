Flutter-FastEdgy
----------------

The package to facilitate integration between a FastEdgy server and a Flutter application.

## Installation

### Step 1: Create the deps directory and add as git submodule

```bash
mkdir -p deps
git submodule add -b main https://github.com/krafterio/flutter-fastedgy.git deps/flutter_fastedgy
```

### Step 2: Add the dependency to your pubspec.yaml

```yaml
dependencies:
  flutter_fastedgy:
    path: deps/flutter_fastedgy
```

### Step 3: Install dependencies

```bash
flutter pub get
```

## Commit message format convention

This project uses the **[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0)** naming convention.

### Basic structure of a Conventional commit

```
<type>(<scope>): <description>
```

- **type**: the type of modification made (required)
- **scope**: the scope (optional, but recommended)
- **description**: a short explanation (imperative, no capital letters, no period)

### Conventional Commits Types used

| Type     | Description                                                                    |
|----------|--------------------------------------------------------------------------------|
| feat     | New feature                                                                    |
| fix      | Bug fix                                                                        |
| docs     | Change in documentation                                                        |
| style    | Change of format (indentation, spaces, etc.) without functional impact         |
| refactor | Refactoring the code without adding or correcting functionality                |
| revert   | Reverting a previous commit                                                    |
| merge    | Merging branches                                                               |
| test     | Adding or modifying tests                                                      |
| chore    | Miscellaneous tasks without direct impact (build, dependencies, configs, etc.) |
| perf     | Performance improvement                                                        |
| ci       | Changes to CI/CD files (Github Actions, Gitlab CI, etc.)                       |
| release  | Creating a new release                                                         |

### Conventional Commits Scopes used

| Scope    | Description                       |
|----------|-----------------------------------|
| core     | Core logic and main features      |
| flutter  | Widgets or extensions for Flutter |
| provider | Features for Provider             |

Contributing
------------

Flutter-FastEdgy is an Open Source, community-driven project.

Issues and feature requests are tracked in the [Github issue tracker][3].

Pull Requests are tracked in the [Github pull request tracker][4].

License
-------

FastEdgy is released under the [MIT License][1].

About
-----

FastEdgy was originally created by [Krafter][2].

[1]: LICENSE
[2]: https://krafter.io
[3]: https://github.com/krafterio/flutter-fastedgy/issues
[4]: https://github.com/krafterio/flutter-fastedgy/pulls
