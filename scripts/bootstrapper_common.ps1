$ErrorActionPreference = "Stop"

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Get-BootstrapperRoot {
    param([Parameter(Mandatory = $true)][string]$CallerRoot)
    return (Resolve-Path -LiteralPath $CallerRoot).Path
}

function ConvertTo-NativeArgument {
    param([AllowNull()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $result = '"'
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes += 1
            continue
        }

        if ($character -eq '"') {
            $result += ('\' * (($backslashes * 2) + 1))
            $result += '"'
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            $result += ('\' * $backslashes)
            $backslashes = 0
        }

        $result += $character
    }

    if ($backslashes -gt 0) {
        $result += ('\' * ($backslashes * 2))
    }

    $result += '"'
    return $result
}

function Join-NativeArguments {
    param([string[]]$ArgumentList = @())

    return (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument -Argument $_ }) -join " ")
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$FailureMessage = "",
        [string]$WorkingDirectory = ""
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $false
    $startInfo.RedirectStandardError = $false
    $startInfo.Arguments = Join-NativeArguments -ArgumentList $ArgumentList

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    if ($exitCode -ne 0) {
        if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
            $FailureMessage = "$FilePath failed with exit code $exitCode."
        }
        throw $FailureMessage
    }
}

function Invoke-NativeProbe {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = Join-NativeArguments -ArgumentList $ArgumentList

    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $null = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $process.Dispose()
        return $exitCode
    } catch {
        return 1
    }
}

function Ensure-Command {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$InstallHint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $InstallHint"
    }
}

function Add-UvCandidateDirsToPath {
    $candidateDirs = @(
        (Join-Path $env:USERPROFILE ".local\bin"),
        (Join-Path $env:LOCALAPPDATA "Programs\uv"),
        (Join-Path $env:ProgramFiles "uv\bin")
    )

    foreach ($candidateDir in $candidateDirs) {
        if ((Test-Path -LiteralPath $candidateDir) -and ($env:PATH -notlike "*$candidateDir*")) {
            $env:PATH = "$candidateDir;$env:PATH"
        }
    }
}

function Ensure-Uv {
    Add-UvCandidateDirsToPath
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        return
    }

    Write-Step "Installing uv"
    $installed = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            Invoke-NativeCommand `
                -FilePath "winget" `
                -ArgumentList @(
                    "install",
                    "--id", "astral-sh.uv",
                    "-e",
                    "--accept-package-agreements",
                    "--accept-source-agreements",
                    "--disable-interactivity"
                ) `
                -FailureMessage "winget could not install uv."
            $installed = $true
        } catch {
            Write-Warning $_.Exception.Message
            Write-Warning "Falling back to the official uv installer."
        }
    }

    if (-not $installed) {
        $powerShellPath = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
        try {
            Invoke-NativeCommand `
                -FilePath $powerShellPath `
                -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-Command",
                    "irm https://astral.sh/uv/install.ps1 | iex"
                ) `
                -FailureMessage "The official uv installer failed."
        } catch {
            throw "uv is not installed and automatic installation failed. Install uv from https://astral.sh/uv and run this script again. Last error: $($_.Exception.Message)"
        }
    }

    Add-UvCandidateDirsToPath
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw "uv was installed, but it is not available in this shell yet. Open a new terminal and run this script again."
    }
}

function Ensure-Git {
    Ensure-Command -Name "git" -InstallHint "Install Git for Windows from https://git-scm.com/download/win."
}

function Get-RequiredPythonVersion {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $pythonVersionPath = Join-Path $ProjectRoot ".python-version"
    if (Test-Path -LiteralPath $pythonVersionPath) {
        $pythonVersion = (Get-Content -LiteralPath $pythonVersionPath -Raw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($pythonVersion)) {
            return $pythonVersion
        }
    }

    return "3.11"
}

function Get-ProjectPythonPath {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $windowsPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    if (Test-Path -LiteralPath $windowsPython) {
        return $windowsPython
    }

    $posixPython = Join-Path $ProjectRoot ".venv/bin/python"
    if (Test-Path -LiteralPath $posixPython) {
        return $posixPython
    }

    return $windowsPython
}

function Assert-ProjectPython {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $pythonPath = Get-ProjectPythonPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $pythonPath)) {
        throw "Project .venv is not installed. Run setup-uv.bat first, or run without -NoSync."
    }

    return $pythonPath
}

function Test-PythonEnvironmentInstalled {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $pythonPath = Get-ProjectPythonPath -ProjectRoot $ProjectRoot
    if (-not (Test-Path -LiteralPath $pythonPath)) {
        return $false
    }

    if (-not (Test-PythonInstallerRuntime -FilePath $pythonPath)) {
        return $false
    }

    $probe = @"
import importlib.metadata as metadata
required = [
    "accelerate",
    "bitsandbytes",
    "diffusers",
    "library",
    "torch",
    "torchvision",
    "xformers",
]
missing = []
for package in required:
    try:
        metadata.version(package)
    except metadata.PackageNotFoundError:
        missing.append(package)
raise SystemExit(1 if missing else 0)
"@

    $exitCode = Invoke-NativeProbe -FilePath $pythonPath -ArgumentList @("-c", $probe)
    return ($exitCode -eq 0)
}

function Test-PythonInstallerRuntime {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    if (-not ((Test-Path -LiteralPath $FilePath) -or (Get-Command $FilePath -ErrorAction SilentlyContinue))) {
        return $false
    }

    $probe = "import sys; raise SystemExit(0 if (3, 10, 9) <= sys.version_info[:3] < (3, 12, 0) else 1)"
    $exitCode = Invoke-NativeProbe -FilePath $FilePath -ArgumentList ($ArgumentList + @("-c", $probe))
    return ($exitCode -eq 0)
}

function Get-SdScriptsDir {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)
    return (Join-Path $ProjectRoot "sd-scripts")
}

function Update-SdScriptsRepo {
    param([Parameter(Mandatory = $true)][string]$SdScriptsDir)

    if (-not (Test-Path -LiteralPath (Join-Path $SdScriptsDir ".git"))) {
        throw "sd-scripts exists but is not a git repository: $SdScriptsDir"
    }

    $gitRepoArgs = @("-c", "safe.directory=$SdScriptsDir", "-C", $SdScriptsDir)

    Write-Step "Fetching sd-scripts updates"
    Invoke-NativeCommand -FilePath "git" -ArgumentList ($gitRepoArgs + @("fetch", "--tags", "--prune")) -FailureMessage "git fetch failed for sd-scripts."

    $branch = (& git @gitRepoArgs branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Could not determine the current sd-scripts branch."
    }

    if ([string]::IsNullOrWhiteSpace($branch)) {
        Write-Warning "sd-scripts is in detached HEAD mode. Fetched updates, but did not pull."
    } else {
        $upstream = ((& git @gitRepoArgs for-each-ref "--format=%(upstream:short)" "refs/heads/$branch" 2>$null) | Select-Object -First 1)
        if ($LASTEXITCODE -ne 0) {
            $upstream = ""
        }

        $mergeTarget = if ($null -eq $upstream) { "" } else { $upstream.Trim() }
        if ([string]::IsNullOrWhiteSpace($mergeTarget)) {
            $originBranch = "origin/$branch"
            & git @gitRepoArgs rev-parse --verify --quiet $originBranch *> $null
            if ($LASTEXITCODE -eq 0) {
                $mergeTarget = $originBranch
                Write-Warning "Branch '$branch' has no upstream. Updating from '$mergeTarget' without changing branch tracking."
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($mergeTarget)) {
            Invoke-NativeCommand -FilePath "git" -ArgumentList ($gitRepoArgs + @("merge", "--ff-only", $mergeTarget)) -FailureMessage "git merge --ff-only failed for sd-scripts. Resolve local changes or branch divergence, then run again."
        } else {
            Write-Warning "Branch '$branch' has no upstream and origin/$branch was not found. Fetched updates, but did not merge."
        }
    }

    Invoke-NativeCommand -FilePath "git" -ArgumentList ($gitRepoArgs + @("submodule", "update", "--init", "--recursive")) -FailureMessage "git submodule update failed for sd-scripts."
}

function Ensure-SdScriptsRepo {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$RepoUrl
    )

    $sdScriptsDir = Get-SdScriptsDir -ProjectRoot $ProjectRoot

    if (-not (Test-Path -LiteralPath $sdScriptsDir)) {
        Write-Step "Cloning sd-scripts"
        Invoke-NativeCommand -FilePath "git" -ArgumentList @("clone", "--recursive", $RepoUrl, $sdScriptsDir) -FailureMessage "git clone failed for sd-scripts."
    }

    Update-SdScriptsRepo -SdScriptsDir $sdScriptsDir
    return $sdScriptsDir
}

function Add-TorchLibraryToPath {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $torchLib = Join-Path $ProjectRoot ".venv\Lib\site-packages\torch\lib"
    if ((Test-Path -LiteralPath $torchLib) -and ($env:PATH -notlike "*$torchLib*")) {
        $env:PATH = "$env:PATH;$torchLib"
    }
}

function Move-ProjectVenvAside {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Reason
    )
    $venvDir = Join-Path $ProjectRoot ".venv"
    if (-not (Test-Path -LiteralPath $venvDir)) {
        return
    }

    $rootFullPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\', '/')
    $sourceFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $venvDir).Path)
    if (-not $sourceFullPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to move invalid venv outside project root: $sourceFullPath"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $ProjectRoot ".venv.invalid-$timestamp"
    $backupFullPath = [System.IO.Path]::GetFullPath($backupDir)
    if (-not $backupFullPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to move invalid venv backup outside project root: $backupFullPath"
    }

    Write-Warning "Project .venv $Reason Moving it to: $backupDir"
    Move-Item -LiteralPath $venvDir -Destination $backupDir
}

function Move-InvalidProjectVenv {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    $venvDir = Join-Path $ProjectRoot ".venv"
    if (-not (Test-Path -LiteralPath $venvDir)) {
        return
    }

    $windowsPython = Join-Path $venvDir "Scripts\python.exe"
    $posixPython = Join-Path $venvDir "bin\python"
    if ((Test-Path -LiteralPath $windowsPython) -or (Test-Path -LiteralPath $posixPython)) {
        return
    }

    Move-ProjectVenvAside -ProjectRoot $ProjectRoot -Reason "exists but has no Python executable."
}

function Use-ProjectUvCache {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    Remove-Item Env:UV_NO_PROGRESS -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($env:UV_CACHE_DIR)) {
        $uvCacheDir = Join-Path $ProjectRoot ".uv-cache"
        New-Item -ItemType Directory -Path $uvCacheDir -Force | Out-Null
        $env:UV_CACHE_DIR = $uvCacheDir
    }

    if ([string]::IsNullOrWhiteSpace($env:UV_PYTHON_INSTALL_DIR)) {
        $uvPythonDir = Join-Path $ProjectRoot ".uv-python"
        New-Item -ItemType Directory -Path $uvPythonDir -Force | Out-Null
        $env:UV_PYTHON_INSTALL_DIR = $uvPythonDir
    }
}

function Ensure-ProjectPythonVenv {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    Ensure-Uv
    Use-ProjectUvCache -ProjectRoot $ProjectRoot
    Move-InvalidProjectVenv -ProjectRoot $ProjectRoot

    $pythonPath = Get-ProjectPythonPath -ProjectRoot $ProjectRoot
    if (Test-Path -LiteralPath $pythonPath) {
        if (Test-PythonInstallerRuntime -FilePath $pythonPath) {
            return $pythonPath
        }

        Move-ProjectVenvAside -ProjectRoot $ProjectRoot -Reason "uses an unsupported Python version."
    }

    $requiredPython = Get-RequiredPythonVersion -ProjectRoot $ProjectRoot
    $venvDir = Join-Path $ProjectRoot ".venv"

    Write-Step "Preparing Python $requiredPython with uv"
    Invoke-NativeCommand -FilePath "uv" -ArgumentList @("python", "install", "--install-dir", $env:UV_PYTHON_INSTALL_DIR, $requiredPython) -WorkingDirectory $ProjectRoot -FailureMessage "uv could not install Python $requiredPython."
    Invoke-NativeCommand -FilePath "uv" -ArgumentList @("venv", "--python", $requiredPython, "--managed-python", "--seed", $venvDir) -WorkingDirectory $ProjectRoot -FailureMessage "uv could not create the project virtual environment."

    if (-not (Test-Path -LiteralPath $pythonPath)) {
        throw "uv created .venv, but Python was not found: $pythonPath"
    }

    return $pythonPath
}

function Invoke-PythonInstallerScript {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$SdScriptsDir
    )

    $installerPath = Join-Path $ProjectRoot "scripts\install_kohya_windows.py"
    if (-not (Test-Path -LiteralPath $installerPath)) {
        throw "Python installer was not found: $installerPath"
    }

    $installerArgs = @(
        $installerPath,
        "--project-root", $ProjectRoot,
        "--sd-scripts-dir", $SdScriptsDir
    )

    $projectPython = Ensure-ProjectPythonVenv -ProjectRoot $ProjectRoot
    Write-Host "Using project Python: $projectPython"
    if ([string]::IsNullOrWhiteSpace($env:PYTHONIOENCODING)) {
        $env:PYTHONIOENCODING = "utf-8"
    }
    Invoke-NativeCommand -FilePath $projectPython -ArgumentList $installerArgs -FailureMessage "Python dependency installation failed."
}

function Invoke-PythonProjectInstall {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [string]$SdScriptsDir = "",
        [switch]$ForceReinstall
    )

    Write-Step "Installing Python environment"
    if ([string]::IsNullOrWhiteSpace($SdScriptsDir)) {
        $SdScriptsDir = Get-SdScriptsDir -ProjectRoot $ProjectRoot
    }

    if ($ForceReinstall) {
        Move-ProjectVenvAside -ProjectRoot $ProjectRoot -Reason "will be reinstalled."
    }

    Invoke-PythonInstallerScript -ProjectRoot $ProjectRoot -SdScriptsDir $SdScriptsDir

    Add-TorchLibraryToPath -ProjectRoot $ProjectRoot
}

function Resolve-ProjectPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $ProjectRoot $Path)).Path
}

function Get-TomlScalarValue {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $pattern = "^\s*$([regex]::Escape($Key))\s*=\s*(?<value>""(?:\\.|[^""\\])*""|'[^']*'|[^\r\n#]+)"

    foreach ($line in Get-Content -LiteralPath $ConfigPath) {
        $match = [regex]::Match($line, $pattern)
        if (-not $match.Success) {
            continue
        }

        $rawValue = $match.Groups["value"].Value.Trim()

        if ($rawValue.StartsWith('"') -and $rawValue.EndsWith('"')) {
            try {
                return ($rawValue | ConvertFrom-Json)
            } catch {
                return $rawValue.Substring(1, $rawValue.Length - 2)
            }
        }

        if ($rawValue.StartsWith("'") -and $rawValue.EndsWith("'")) {
            return $rawValue.Substring(1, $rawValue.Length - 2)
        }

        return ($rawValue -replace "\s+#.*$", "").Trim()
    }

    return $null
}

function Resolve-OutputDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [Parameter(Mandatory = $true)][string]$WorkingDir
    )

    $expandedOutputDir = [Environment]::ExpandEnvironmentVariables($OutputDir)
    if ($expandedOutputDir -eq "~" -or $expandedOutputDir.StartsWith("~\") -or $expandedOutputDir.StartsWith("~/")) {
        $expandedOutputDir = Join-Path $env:USERPROFILE $expandedOutputDir.Substring(2)
    }

    if ([System.IO.Path]::IsPathRooted($expandedOutputDir)) {
        return [System.IO.Path]::GetFullPath($expandedOutputDir)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $WorkingDir $expandedOutputDir))
}

function Get-ModelOutputExtension {
    param([string]$SaveModelAs)

    if ([string]::IsNullOrWhiteSpace($SaveModelAs)) {
        return ".safetensors"
    }

    switch ($SaveModelAs.ToLowerInvariant()) {
        "safetensors" { return ".safetensors" }
        "ckpt" { return ".ckpt" }
        "pt" { return ".pt" }
        default { return $null }
    }
}

function Get-ExistingOutputArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDir,
        [Parameter(Mandatory = $true)][string]$OutputName,
        [string]$Extension
    )

    if (-not (Test-Path -LiteralPath $OutputDir)) {
        return @()
    }

    $escapedOutputName = [regex]::Escape($OutputName)
    $escapedExtension = if ($null -eq $Extension) { $null } else { [regex]::Escape($Extension) }

    $patterns = @()
    if ($null -ne $escapedExtension) {
        $patterns += "^$escapedOutputName$escapedExtension$"
        $patterns += "^$escapedOutputName-\d{6}$escapedExtension$"
        $patterns += "^$escapedOutputName-step\d{8}$escapedExtension$"
    } else {
        $patterns += "^$escapedOutputName$"
        $patterns += "^$escapedOutputName-\d{6}$"
        $patterns += "^$escapedOutputName-step\d{8}$"
    }

    $patterns += "^$escapedOutputName-state$"
    $patterns += "^$escapedOutputName-\d{6}-state$"
    $patterns += "^$escapedOutputName-step\d{8}-state$"

    $artifacts = @()
    foreach ($item in Get-ChildItem -LiteralPath $OutputDir -Force) {
        foreach ($pattern in $patterns) {
            if ($item.Name -match $pattern) {
                $artifacts += $item.FullName
                break
            }
        }
    }

    return $artifacts
}

function Confirm-OverwriteArtifacts {
    param(
        [string[]]$Artifacts = @(),
        [switch]$ForceOverwrite
    )

    if ($Artifacts.Count -eq 0 -or $ForceOverwrite) {
        return $true
    }

    Write-Host ""
    Write-Warning "Existing output artifacts were found and may be overwritten:"
    foreach ($artifact in ($Artifacts | Select-Object -First 10)) {
        Write-Host "  $artifact"
    }
    if ($Artifacts.Count -gt 10) {
        Write-Host "  ... and $($Artifacts.Count - 10) more"
    }

    $message = "Existing output artifacts were found and may be overwritten.`n`nContinue training?"

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Confirm overwrite",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
    } catch {
        $answer = Read-Host "Continue training and allow overwrite? (Y/N)"
        return ($answer -match "^(Y|y|YES|yes)$")
    }
}

function Prepare-TrainingOutput {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$WorkingDir,
        [switch]$ForceOverwrite
    )

    $outputDirValue = Get-TomlScalarValue -ConfigPath $ConfigPath -Key "output_dir"
    if ([string]::IsNullOrWhiteSpace($outputDirValue)) {
        throw "output_dir was not found in config: $ConfigPath"
    }

    $outputNameValue = Get-TomlScalarValue -ConfigPath $ConfigPath -Key "output_name"
    if ([string]::IsNullOrWhiteSpace($outputNameValue)) {
        $outputNameValue = "last"
    }

    $saveModelAsValue = Get-TomlScalarValue -ConfigPath $ConfigPath -Key "save_model_as"
    $outputExtension = Get-ModelOutputExtension -SaveModelAs $saveModelAsValue
    $resolvedOutputDir = Resolve-OutputDirectory -OutputDir $outputDirValue -WorkingDir $WorkingDir

    if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
        Write-Step "Creating output directory"
        New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
    }

    $existingArtifacts = @(Get-ExistingOutputArtifacts -OutputDir $resolvedOutputDir -OutputName $outputNameValue -Extension $outputExtension)
    if (-not (Confirm-OverwriteArtifacts -Artifacts $existingArtifacts -ForceOverwrite:$ForceOverwrite)) {
        throw "Training was cancelled because existing output artifacts were not approved for overwrite."
    }

    Write-Host "Output directory: $resolvedOutputDir"
}

function Resolve-TrainingScriptName {
    param(
        [Parameter(Mandatory = $true)][string]$SdScriptsDir,
        [Parameter(Mandatory = $true)][string[]]$TrainScriptNames
    )

    foreach ($trainScriptName in $TrainScriptNames) {
        $trainScriptPath = Join-Path $SdScriptsDir $trainScriptName
        if (Test-Path -LiteralPath $trainScriptPath) {
            return $trainScriptName
        }
    }

    throw "None of these training scripts were found in sd-scripts: $($TrainScriptNames -join ', ')"
}

function Start-SdScriptsTraining {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string[]]$TrainScriptNames,
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$SdScriptsUrl,
        [switch]$SkipUpdate,
        [switch]$NoSync,
        [switch]$ForceOverwrite,
        [string[]]$ExtraArgs = @()
    )

    $sdScriptsDir = Get-SdScriptsDir -ProjectRoot $ProjectRoot
    $resolvedConfigPath = Resolve-ProjectPath -ProjectRoot $ProjectRoot -Path $ConfigPath

    Ensure-Git
    if ($SkipUpdate) {
        if (-not (Test-Path -LiteralPath (Join-Path $sdScriptsDir ".git"))) {
            throw "sd-scripts is not installed. Run setup-uv.bat first, or run without -SkipUpdate."
        }
    } else {
        $sdScriptsDir = Ensure-SdScriptsRepo -ProjectRoot $ProjectRoot -RepoUrl $SdScriptsUrl
    }

    $trainScriptName = Resolve-TrainingScriptName -SdScriptsDir $sdScriptsDir -TrainScriptNames $TrainScriptNames

    Prepare-TrainingOutput -ConfigPath $resolvedConfigPath -WorkingDir $sdScriptsDir -ForceOverwrite:$ForceOverwrite

    if (-not $NoSync) {
        Invoke-PythonProjectInstall -ProjectRoot $ProjectRoot -SdScriptsDir $sdScriptsDir
    }

    $pythonPath = Assert-ProjectPython -ProjectRoot $ProjectRoot
    Add-TorchLibraryToPath -ProjectRoot $ProjectRoot

    $trainingArgs = @(
        "-m",
        "accelerate.commands.launch",
        "--num_cpu_threads_per_process", "1",
        $trainScriptName,
        "--config_file", $resolvedConfigPath
    )

    if ($ExtraArgs.Count -gt 0) {
        $trainingArgs += $ExtraArgs
    }

    Write-Host ""
    Write-Host "Starting $DisplayName training"
    Write-Host "Project:    $ProjectRoot"
    Write-Host "sd-scripts: $sdScriptsDir"
    Write-Host "Python:     $pythonPath"
    Write-Host "Script:     $trainScriptName"
    Write-Host "Config:     $resolvedConfigPath"
    Write-Host ""

    if ([string]::IsNullOrWhiteSpace($env:PYTHONIOENCODING)) {
        $env:PYTHONIOENCODING = "utf-8"
    }

    Invoke-NativeCommand -FilePath $pythonPath -ArgumentList $trainingArgs -WorkingDirectory $sdScriptsDir -FailureMessage "$DisplayName training failed."
}
