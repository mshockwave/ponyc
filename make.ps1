﻿Param(
    [Parameter(Position=0, Mandatory=$true, HelpMessage="Enter the action to take, e.g. libs, configure, build, clean, cleanlibs.")]
    [string]
    $Command,

    [Parameter(HelpMessage="The build configuration (Release, Debug, RelWithDebInfo, MinSizeRel).")]
    [string]
    $Config = "Release",

    [Parameter(HelpMessage="The CMake generator, e.g. `"Visual Studio 16 2019`"")]
    [string]
    $Generator = "default"
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# Sanitize config to conform to CMake build configs.
switch ($Config.ToLower())
{
    "release" { $Config = "Release"; break; }
    "debug" { $Config = "Debug"; break; }
    "relwithdebinfo" { $Config = "RelWithDebInfo"; break; }
    "minsizerel" { $Config = "MinSizeRel"; break; }
    default { throw "'$Config' is not a valid config; use Release, Debug, RelWithDebInfo, or MinSizeRel)." }
}

if ($Generator -eq "default")
{
    try
    {
        $Generator = cmake --help | Where-Object { $_ -match '\* (.*) (\[arch\])? =' } | Foreach-Object { $Matches[1] }
    }
    catch { }
}

Write-Output "make.ps1 $Command -Config $Config -Generator `"$Generator`""

$srcDir = Split-Path $script:MyInvocation.MyCommand.Path
$buildDir = Join-Path -Path $srcDir -ChildPath "build"
$libsDir = Join-Path -Path $buildDir -ChildPath "libs"
$outDir = Join-Path -Path $buildDir -ChildPath $Config

# Write-Output "Source directory: $srcDir"
# Write-Output "Build directory:  $buildDir"
# Write-Output "Libs directory:   $libsDir"
# Write-Output "Output directory: $outDir"

if (($Command.ToLower() -ne "libs") -and ($Command.ToLower() -ne "distclean") -and !(Test-Path -Path $libsDir))
{
    throw "Libs directory '$libsDir' does not exist; you may need to run 'make.ps1 libs' first."
}

switch ($Command.ToLower())
{
    "libs"
    {
        if (!(Test-Path -Path $libsDir))
        {
            New-Item -ItemType "directory" -Path $libsDir | Out-Null
        }

        $libsBuildDir = Join-Path -Path $buildDir -ChildPath "libsbuild"
        if (!(Test-Path -Path $libsBuildDir))
        {
            New-Item -ItemType "directory" -Path $libsBuildDir | Out-Null
        }

        $libsSrcDir = Join-Path -Path $srcDir -ChildPath "lib"
        Write-Output "Configuring libraries..."
        Write-Output "cmake.exe -B `"$libsBuildDir`" -S `"$libsSrcDir`" -G `"$Generator`" -A x64 -Thost=x64 -DCMAKE_INSTALL_PREFIX=`"$libsDir`" -DCMAKE_BUILD_TYPE=Release"
        & cmake.exe -B "$libsBuildDir" -S "$libsSrcDir" -G "$Generator" -A x64 -Thost=x64 -DCMAKE_INSTALL_PREFIX="$libsDir" -DCMAKE_BUILD_TYPE=Release
        if (!$?) { throw "Error: exit code $LastExitCode" }

        Write-Output "Building libraries..."
        Write-Output "cmake.exe --build `"$libsBuildDir`" --target install --config Release"
        & cmake.exe --build "$libsBuildDir" --target install --config Release
        if (!$?) { throw "Error: exit code $LastExitCode" }
        break
    }
    "cleanlibs"
    {
        if (Test-Path -Path $libsDir)
        {
            Write-Output "Removing $libsDir..."
            Remove-Item -Path $libsDir -Recurse
        }
        break
    }
    "configure"
    {
        Write-Output "cmake.exe -B `"$buildDir`" -S `"$srcDir`" -G `"$Generator`" -A x64 -Thost=x64 -DCMAKE_BUILD_TYPE=`"$Config`""
        & cmake.exe -B "$buildDir" -S "$srcDir" -G "$Generator" -A x64 -Thost=x64 -DCMAKE_BUILD_TYPE="$Config"
        if (!$?) { throw "Error: exit code $LastExitCode" }
        break
    }
    "build"
    {
        Write-Output "cmake.exe --build `"$buildDir`" --config $Config --target ALL_BUILD"
        & cmake.exe --build "$buildDir" --config $Config --target ALL_BUILD
        if (!$?) { throw "Error: exit code $LastExitCode" }
        break
    }
    "clean"
    {
        Write-Output "Remove-Item -Path $outDir -Recurse"
        Remove-Item -Path $outDir -Recurse
        break
    }
    "distclean"
    {
        if (Test-Path $buildDir)
        {
            Write-Output "Remove-Item -Path $buildDir -Recurse"
            Remove-Item -Path $buildDir -Recurse
        }
        break
    }
    "test"
    {
        $numTestSuitesRun = 0
        $failedTestSuites = @()

        & $outDir\ponyc.exe --version

        # libponyrt.tests
        $numTestSuitesRun += 1;
        Write-Output "$outDir\libponyrt.tests.exe --gtest_shuffle"
        & $outDir\libponyrt.tests.exe --gtest_shuffle
        if (!$?) { $failedTestSuites += 'libponyrt.tests' }

        # libponyc.tests
        $numTestSuitesRun += 1;
        Write-Output "$outDir\libponyc.tests.exe --gtest_shuffle"
        & $outDir\libponyc.tests.exe --gtest_shuffle
        if (!$?) { $failedTestSuites += 'libponyc.tests' }

        # stdlib-debug
        $numTestSuitesRun += 1;
        Write-Output "$outDir\ponyc.exe -d --checktree --verify -b stdlib-debug -o $outDir $srcDir\packages\stdlib"
        & $outDir\ponyc.exe -d --checktree --verify -b stdlib-debug -o $outDir $srcDir\packages\stdlib
        if ($LastExitCode -eq 0)
        {
            Write-Output "$outDir\stdlib-debug.exe"
            & $outDir\stdlib-debug.exe
            if (!$?) { $failedTestSuites += 'stdlib-debug' }
        }
        else
        {
            $failedTestSuites += 'compile stdlib-debug'
        }

        # stdlib-release
        $numTestSuitesRun += 1;
        Write-Output "$outDir\ponyc.exe --checktree --verify -b stdlib-release -o $outDir $srcDir\packages\stdlib"
        & $outDir\ponyc.exe --checktree --verify -b stdlib-release -o $outDir $srcDir\packages\stdlib
        if ($LastExitCode -eq 0)
        {
            Write-Output "$outDir\stdlib-release.exe"
            & $outDir\stdlib-release.exe
            if (!$?) { $failedTestSuites += 'stdlib-release' }
        }
        else
        {
            $failedTestSuites += 'compile stdlib-release'
        }

        # grammar
        $numTestSuitesRun += 1
        Write-Output "$outDir\ponyc.exe --antlr > $outDir\pony.g.test"
        & $outDir\ponyc.exe --antlr | Out-File -Encoding ASCII "$outDir\pony.g.test"
        if ($LastExitCode -eq 0)
        {
            $origHash = Get-FileHash -Path "$srcDir\pony.g"
            $testHash = Get-FileHash -Path "$outDir\pony.g.test"

            if ($origHash.Hash -ne $testHash.Hash)
            {
                $failedTestSuites += 'generated grammar file differs from baseline'
            }
        }
        else
        {
            $failedTestSuites += 'generate grammar'
        }

        #
        $numTestSuitesFailed = $failedTestSuites.Length
        Write-Output "Test suites run: $numTestSuitesRun, num failed: $numTestSuitesFailed"
        if ($numTestSuitesFailed -ne 0)
        {
            $failedTestSuitesList = [string]::Join(', ', $failedTestSuites)
            Write-Output "Test suites failed: ($failedTestSuitesList)"
            exit $numTestSuitesFailed
        }
    }
    default
    {
        throw "Unknown command $Command; libs, cleanlibs, configure, build, clean, distclean, test"
    }
}
