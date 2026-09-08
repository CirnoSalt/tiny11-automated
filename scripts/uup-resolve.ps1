<#
.SYNOPSIS
    解析 Windows 版本 / 语言 / 版本 -> UUP dump 的下载包（zip），供后续组装 ISO 用。
    也就是说：用户不用自己去 UUP dump 找"/版本"/"/链接"，选几个选项即可。

.DESCRIPTION
    本脚本使用"混合式构建ID解析"：
      1. 若显式传入 -BuildId，则直接使用；
      2. 否则优先尝试实时抓取 UUP dump 分类页（known.php）中该版本最新的 amd64 构建；
         抓取被 Cloudflare 拦截或解析不到时，自动回退到 config/builds.json 里的快照；
      3. 最终用解析出的 build id + 语言 + 版本，POST get.php 生成"下载包"(zip)。
         （zip 内含微软永久 CDN 直链清单 + 组装脚本，就是我们要跑的原料包）

.PARAMETER Version
    Windows 版本 id，如 26H2 / 25H2 / 24H2。需存在于 config/builds.json。

.PARAMETER Language
    UUP 语言包代码，如 zh-cn（简体中文）/ en-us / zh-tw ... 需存在于 config/builds.json。

.PARAMETER Edition
    版本 id：home / pro / education / enterprise。

.PARAMETER BuildId
    （可选，高级）显式指定 build id 以覆盖自动解析与快照。适合想追最新构建的用户。

.PARAMETER IncludeUpdates
    （可选）是否把更新包含进 ISO（UUP get.php 的 updates=1）。默认 true。

.PARAMETER OutDir
    （可选）下载包输出目录。默认使用脚本所在目录下的 downloads。

.PARAMETER DryRun
    只打印解析结果与将要请求的 URL，不实际下载。

.EXAMPLE
    .\scripts\uup-resolve.ps1 -Version 26H2 -Language zh-cn -Edition pro -DryRun
    .\scripts\uup-resolve.ps1 -Version 25H2 -Language en-us -Edition enterprise -OutDir D:\uup
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [Parameter(Mandatory = $true)]
    [ValidateSet('zh-cn', 'zh-tw', 'en-us', 'ja-jp', 'ko-kr', 'ru-ru', 'de-de', 'fr-fr')]
    [string]$Language,
    [Parameter(Mandatory = $true)]
    [ValidateSet('home', 'pro', 'education', 'enterprise')]
    [string]$Edition,
    [string]$BuildId,
    [switch]$IncludeUpdates = $true,
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$OutDir,
    [switch]$DryRun,
    # 可选：本地可能需要肉炸代理（境外网络）。示例：-Proxy 'http://127.0.0.1:10808'
    [string]$Proxy
)

$ErrorActionPreference = 'Stop'
$scriptPath = $PSScriptRoot
$configPath = Join-Path ($scriptPath | Split-Path -Parent) 'config\builds.json'
$baseUrl = 'https://uupdump.net'

function Write-Step { param([string]$m) Write-Host "[uup-resolve] $m" -ForegroundColor Cyan }
function Invoke-Get {
    param([string]$Uri, [scriptblock]$OnSuccess)
    $params = @{ Uri = $Uri; UseBasicParsing = $true; UserAgent = 'Mozilla/5.0' }
    if ($Proxy) { $params.Proxy = $Proxy }
    $r = Invoke-WebRequest @params
    return ($OnSuccess.Invoke($r))
}

# ---------------------------------------------------------------- 1. 读配置
if (-not (Test-Path $configPath)) { throw "找不到配置文件: $configPath" }
$cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ver = $cfg.versions | Where-Object { $_.id -eq $Version }
if (-not $ver) { throw "config/builds.json 中不存在该版本: $Version" }
if ($null -eq $cfg.languages.($Language)) { throw "不支持的语言代码: $Language" }
$ed = $cfg.editions.($Edition)
if (-not $ed) { throw "不支持的版本 id: $Edition" }

# ---------------------------------------------------------------- 2. 解析 build id（三层混合）
$resolvedBuildId = $null
$resolvedSource = ''
if ($BuildId) {
    $resolvedBuildId = $BuildId
    $resolvedSource = "参数 -BuildId 显式指定"
} else {
    # 2a. 尝试实时抓取该版本最新 amd64 构建（可能被 Cloudflare 拦截 -> 非致命）
    try {
        $cat = $ver.category
        $html = Invoke-Get -Uri "$baseUrl/known.php?q=category:$cat" -OnSuccess { param($r) $r.Content } -ErrorAction Stop
        $newer = $null
        [regex]::Matches($html, 'selectlang\.php\?id=([0-9a-fA-F-]{36})[^>]*>\s*Windows 11,\s*version\s+' + [regex]::Escape($ver.id) + '\s*\((\d+\.\d+)\)\s*amd64') |
            ForEach-Object {
                $b = $_.Groups[2].Value
                $bid = $_.Groups[1].Value
                if ([version]$b -ge [version]$ver.build) {
                    if (-not $newer -or ([version]$b -gt [version]$newer.build)) {
                        $newer = [pscustomobject]@{ build = $b; build_id = $bid }
                    }
                }
            }
        if ($newer) {
            $resolvedBuildId = $newer.build_id
            $resolvedSource = "实时抓取 latest ($($newer.build))"
        }
    } catch {
        Write-Warning "实时抓取失败（可能被 Cloudflare 拦截），将使用快照: $($_.Exception.Message)"
    }
    # 2b. 回退到快照
    if (-not $resolvedBuildId) {
        $resolvedBuildId = $ver.build_id
        $resolvedSource = "config/builds.json 快照 ($($ver.build))"
    }
}

$resolved = [pscustomobject]@{
    version = $ver.id; build = $ver.build; arch = $ver.arch
    build_id = $resolvedBuildId; source = $resolvedSource
    language = $Language; language_name = $cfg.languages.($Language)
    edition = $Edition; edition_name = $ed.name
    autodl = [int]$ed.autodl; use_enterprise = ($Edition -eq 'enterprise')
    tiny11_index = [int]$ed.tiny11_index
}

Write-Host '────────────────────────────────────────────'
Write-Step "版本   : $($resolved.version) (build $($resolved.build))"
Write-Step "构建ID : $($resolved.build_id)  [来源: $($resolved.source)]"
Write-Step "语言   : $($resolved.language) ($($resolved.language_name))"
Write-Step "版本   : $($resolved.edition) ($($resolved.edition_name))"
Write-Step "tiny11 目标索引: $($resolved.tiny11_index)  (home=1 pro=6 edu=4)"
Write-Host '────────────────────────────────────────────'

# 把解析结果写到一个一起提交使用的环境文件/JSON，方便流程后续步骤读取
$resolvedJson = $resolved | ConvertTo-Json -Compress
if ($env:GITHUB_ENV) {
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_VERSION=$($resolved.version)"
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_BUILD_ID=$($resolved.build_id)"
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_LANG=$($resolved.language)"
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_EDITION=$($resolved.edition)"
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_AUTODL=$($resolved.autodl)"
    Add-Content -Path $env:GITHUB_ENV -Value "UUP_USE_ENTERPRISE=$($resolved.use_enterprise)"
    Add-Content -Path $env:GITHUB_ENV -Value "TINY11_INDEX=$($resolved.tiny11_index)"
}

# ---------------------------------------------------------------- 3. 生成下载包请求
$getUrl = "$baseUrl/get.php?id=$($resolved.build_id)&pack=$($resolved.language)&edition=$($ed.uup)"
$updFlag = $(if ($IncludeUpdates) { 1 } else { 0 })
$body = "autodl=$($resolved.autodl)&updates=$updFlag&cleanup=1"
if ($resolved.use_enterprise) {
    $body = "autodl=3&updates=$updFlag&cleanup=1&virtualEditions[]=Enterprise"
}

if ($DryRun) {
    Write-Step "【DryRun】不下载。将 POST: $getUrl"
    Write-Step "【DryRun】Body: $body"
    return
}

# ---------------------------------------------------------------- 4. 下载下载包 zip
if (-not $OutDir) { $OutDir = Join-Path $scriptPath 'downloads' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$outZip = Join-Path $OutDir "UUP-$($resolved.version)-$($resolved.language)-$($resolved.edition).zip"
Write-Step "正在请求下载包 -> $outZip"

try {
    $p = @{
        Uri = $getUrl; Method = 'Post'; Body = $body; ContentType = 'application/x-www-form-urlencoded'
        OutFile = $outZip; UserAgent = 'Mozilla/5.0'; ErrorAction = 'Stop'
    }
    if ($Proxy) { $p.Proxy = $Proxy }
    Invoke-WebRequest @p
} catch {
    # 个别网关需要 Referer，重试一次带 Referer
    Write-Warning "首次请求失败，带 Referer 重试: $($_.Exception.Message)"
    $p2 = @{
        Uri = $getUrl; Method = 'Post'; Body = $body; ContentType = 'application/x-www-form-urlencoded'
        OutFile = $outZip; UserAgent = 'Mozilla/5.0'; ErrorAction = 'Stop'
        Headers = @{ Referer = $baseUrl }
    }
    if ($Proxy) { $p2.Proxy = $Proxy }
    Invoke-WebRequest @p2
}

if (-not (Test-Path $outZip)) { throw "下载包下载失败: $outZip" }
$sizeMB = [math]::Round((Get-Item $outZip).Length / 1MB, 2)
Write-Step "下载包已就绪: $outZip ($sizeMB MB)"
Write-Output $outZip