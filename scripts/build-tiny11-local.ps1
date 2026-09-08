<#
.SYNOPSIS
    本地一键：用 UUP dump 制作中文 Tiny11 精简镜像（标准版 Standard）。
    等价于 GitHub Actions 里的 "Build Tiny11 (UUP)" 工作流，但跑在你自己电脑上。

.DESCRIPTION
    使用方法（Windows，必须以【管理员身份】运行 PowerShell）：
      Set-ExecutionPolicy Bypass -Scope Process
      .\scripts\build-tiny11-local.ps1 -Version 26H2 -Language zh-cn -Edition pro

    它会：
      1. 调 scripts\uup-resolve.ps1 解析并下载 UUP"下载包"
      2. 解包并运行 UUP 组装脚本，把微软文件在本地合成一个 Windows 11 ISO
      3. 挂载该 ISO
      4. 调 scripts\tiny11maker-headless.ps1 做标准版精简
      5. 最后把精简 ISO 放到当前目录（或 -WorkDir 指定的目录）

.PARAMETER Version
    Windows 版本 id：26H2 / 25H2 / 24H2。

.PARAMETER Language
    UUP 语言包代码：zh-cn（简体中文，默认）/ zh-tw / en-us / ja-jp / ko-kr ...

.PARAMETER Edition
    版本：home / pro（默认）/ education / enterprise。

.PARAMETER WorkDir
    工作目录，用于放 UUP 下载包、合成 ISO 与精简产物。默认当前目录。

.PARAMETER SkipCleanup
    传给 tiny11 的调试开关：保留中间临时文件。

.EXAMPLE
    .\scripts\build-tiny11-local.ps1 -Version 26H2 -Language zh-cn -Edition pro
    .\scripts\build-tiny11-local.ps1 -Version 25H2 -Edition enterprise
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('26H2', '25H2', '24H2')]
    [string]$Version,
    [string]$Language = 'zh-cn',
    [ValidateSet('home', 'pro', 'education', 'enterprise')]
    [string]$Edition = 'pro',
    [string]$WorkDir,
    [switch]$SkipCleanup
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not $WorkDir) { $WorkDir = (Get-Location).Path }
$uupDir = Join-Path $WorkDir "uup_work"

function Step { param([string]$m) Write-Host ""; Write-Host "==== $m ====" -ForegroundColor Green }

# 管理员自检（UUP 组装需要管理员）
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())`
    .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "建议以管理员身份运行 PowerShell，UUP 组装步骤需要管理员权限。继续尝试……"
}

# 1. 解析并下载 UUP 下载包
Step "1/5 解析 UUP 下载包（$Version / $Language / $Edition）"
New-Item -ItemType Directory -Path $uupDir -Force | Out-Null
$zip = & "$PSScriptRoot\uup-resolve.ps1" `
    -Version $Version -Language $Language -Edition $Edition `
    -OutDir (Join-Path $uupDir "pkg") | Select-Object -Last 1
if (-not (Test-Path $zip)) { throw "未获得 UUP 下载包: $zip" }

# 2. 解包并组装 ISO
Step "2/5 解包并组装 Windows 11 ISO（需管理员与耐心，x64 中文包约 5~6 GB）"
$pkgDir = Join-Path $uupDir ("pkg_extract_" + [guid]::NewGuid().ToString('N').Substring(0, 6))
New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null
Expand-Archive -Path $zip -DestinationPath $pkgDir -Force
$cmd = Join-Path $pkgDir "uup_download_windows.cmd"
if (-not (Test-Path $cmd)) { throw "下载包内缺少 uup_download_windows.cmd" }
Push-Location $pkgDir
try {
    cmd /c "uup_download_windows.cmd"
} finally {
    Pop-Location
}

$iso = Get-ChildItem $pkgDir -Filter *.ISO -File -ErrorAction SilentlyContinue | Where-Object Length -gt 1GB | Select-Object -First 1
if (-not $iso) { $iso = Get-ChildItem $pkgDir -Filter *.iso -File | Select-Object -First 1 }
if (-not $iso) { throw "未在 $pkgDir 找到组装好的 ISO" }
Write-Host "组装完成: $($iso.FullName)"

# 3. 挂载 ISO
Step "3/5 挂载 ISO"
$mount = Mount-DiskImage -ImagePath $iso.FullName -PassThru -StorageType ISO
$driveLetter = ($mount | Get-Volume).DriveLetter
Write-Host "已挂载到盘符: ${driveLetter}:"

# 4. 跑 tiny11 标准精简
Step "4/5 运行 tiny11 标准精简（约 45~80 分钟）"
$index = @{ home = 1; pro = 6; education = 4; enterprise = 6 }[$Edition]
if ($Edition -eq 'enterprise') {
    # 企业版在合成的 wim 里是"附加版本"，tiny11 无内置映射，这里显式定位它的索引
    $src = "${driveLetter}:\sources\install.wim"
    if (-not (Test-Path $src)) { $src = "${driveLetter}:\sources\install.esd" }
    $ent = Get-WindowsImage -ImagePath $src -ErrorAction SilentlyContinue |
           Where-Object { $_.ImageName -like 'Windows 11 Enterprise*' } | Select-Object -First 1
    if ($ent) { $index = $ent.ImageIndex; Write-Host "企业版图像索引: $index" }
    else { Write-Warning "未定位到企业版图像，将按索引 $index 处理（可能不对，请人工检查）" }
}

$params = @("-ISO", $driveLetter, "-INDEX", [string]$index)
if ($SkipCleanup) { $params += "-SkipCleanup" }
& "$PSScriptRoot\tiny11maker-headless.ps1" @params
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) { throw "tiny11 脚本返回非零: $LASTEXITCODE" }

# 5. 收集产物
Step "5/5 收集精简 ISO 产物"
$out = Get-ChildItem $PSScriptRoot -Filter *.iso -File | Where-Object Name -like 'tiny11*' | Select-Object -First 1
if (-not $out) { $out = Get-ChildItem $PSScriptRoot\scripts -Filter *.iso -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $out) {
    $out = Get-ChildItem $PSScriptRoot -Filter *.iso -File | Select-Object -Last 1
}
if ($out) {
    $dest = Join-Path $WorkDir ("tiny11-$Version-$Language-$Edition-" + $out.Name)
    Copy-Item $out.FullName $dest -Force -ErrorAction SilentlyContinue
    Write-Host "精简完成: $dest"
} else {
    Write-Warning "未在当前目录找到 tiny11 产物，请到 scripts 目录检查 tiny11.iso"
}

# 清理挂载
Get-DiskImage -ImagePath $iso.FullName | Dismount-DiskImage -ErrorAction SilentlyContinue
Write-Host "全部完成。"