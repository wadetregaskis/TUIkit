# TUIkit Project Creator

CLI tool for creating TUIkit terminal applications.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/wadetregaskis/TUIkit/main/project-template/install.sh | bash
```

This installs the `tuikit` command globally on your system.

## Usage

```bash
tuikit init MyApp                     # Basic app
tuikit init git MyApp                 # With Git repository (initial commit)
tuikit init sqlite MyApp              # With SQLite database
tuikit init testing MyApp             # With Swift Testing
tuikit init xctest MyApp              # With XCTest
tuikit init git sqlite testing MyApp  # With Git, SQLite and Testing
```

## What Gets Created

```
MyApp/
├── Package.swift           # Swift Package with TUIkit dependency
├── Sources/
│   ├── App.swift           # Main entry point
│   ├── ContentView.swift   # Root view
│   └── Database.swift      # (if sqlite option used)
├── Tests/                  # (if testing/xctest option used)
├── README.md
└── .gitignore
```

## Features

- Creates native Swift Packages (not .xcodeproj)
- Optional GRDB (SQLite) integration
- Optional Swift Testing or XCTest
- Xcode-ready Swift Package (Xcode generates the scheme on first open)
- Cross-platform (macOS, Linux)
- XDG Base Directory compliant

## Installation Details

The installer:
- Detects your platform (macOS/Linux)
- Installs to `/usr/local/bin` or `~/.local/bin`
- Offers to update your shell PATH automatically
- Creates `tuikit-uninstall` command for easy removal

## Manual Installation

```bash
git clone https://github.com/wadetregaskis/TUIkit.git
cd TUIkit/project-template
./install.sh
```

## Uninstall

```bash
tuikit-uninstall
```

## Requirements

- macOS 15+ or Linux (generated projects target macOS 15; the TUIkit library itself needs only macOS 14+)
- Swift 6.2+ (TUIkit requires a Swift 6.2 toolchain)
- Bash shell

## Documentation

- [TUIkit Documentation](https://swiftpackageindex.com/wadetregaskis/TUIkit/main/documentation/tuikit)
- [TUIkit GitHub](https://github.com/wadetregaskis/TUIkit)

## License

MIT License
