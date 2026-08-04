#!/usr/bin/env pwsh
#
# Run `swift <arguments>` against the official Swift Windows container image.
#
# Why this exists: GitHub Actions' `container:` key is Linux-only, so a Windows
# toolchain image has to be driven through an explicit `docker run`. Without
# this helper every CI step repeats the same long invocation, and every one of
# them has to remember that PowerShell does NOT propagate a native executable's
# exit code — so a failing `swift build` would silently report success.
#
# The script re-enters itself inside the container: called with -Image it is the
# launcher, called without it is the payload. One file, one copy of the logic.
#
# Usage:
#   Tools/ci-windows-swift.ps1 -Image swift:6.3-windowsservercore-ltsc2022 `
#                              -Arguments "build --target TUIkitCore"
#
# -Arguments is one string rather than a list of positional parameters on
# purpose: PowerShell binds any leading-dash token to a parameter name, so a
# bare `--version` or `--build-tests` would be swallowed by the parser instead
# of reaching swift. The string is split on whitespace, which is sufficient
# because no swift argument used here contains a space.
#
# The repository is mounted at C:\source, which is also where the payload runs.

param(
    # Omitted when running inside the container.
    [string]$Image,
    [Parameter(Mandatory = $true)]
    [string]$Arguments
)

# Deliberately NOT setting $ErrorActionPreference = 'Stop': from PowerShell 7.4
# on, that also makes a failing native command throw, which would pre-empt the
# explicit `exit $LASTEXITCODE` below. One mechanism for propagating failure is
# easier to reason about than two.

# The `-split` operator, not String.Split(): the launcher runs under pwsh 7
# (the runner default) but the payload runs under the container's
# `powershell.exe`, which is Windows PowerShell 5.1 — and 5.1's .NET Framework
# has no Split(string, StringSplitOptions) overload.
$swiftArgs = @($Arguments -split '\s+' | Where-Object { $_ })

if ($Image) {
    # ── Launcher ──
    $workspace = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Location).Path }

    docker run --rm `
        --volume "${workspace}:C:\source" `
        $Image `
        powershell.exe -NoLogo -File C:\source\Tools\ci-windows-swift.ps1 -Arguments "$Arguments"

    exit $LASTEXITCODE
}

# ── Payload (inside the container) ──
Set-Location C:\source
& swift @swiftArgs
exit $LASTEXITCODE
