# 打包 EZ THEME 为 Xboard 后台可上传的主题 ZIP（本地构建，不依赖服务器性能）
# 用法：powershell -ExecutionPolicy Bypass -File scripts\build-xboard-package.ps1 [-SkipBuild]
param(
    [switch]$SkipBuild,          # 跳过 npm run build（dist 已最新时）
    [string]$ThemeName = "EZTheme",
    [string]$Version = "2.5.2",  # 必须高于服务器已装版本，否则上传器拒绝覆盖
    [string]$ApiUrlMode = "auto" # auto=跟随当前域名 | static=写死 staticBaseUrl
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

function Say($m) { Write-Host "`n== $m" -ForegroundColor Cyan }

# 1. 构建前端
if (-not $SkipBuild) {
    Say "1/6 构建前端 (npm run build)"
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "build 失败" }
}
if (-not (Test-Path "$root\dist\index.html")) { throw "dist/index.html 不存在" }

# 2. 准备打包目录
Say "2/6 准备打包目录"
$stage = "$root\.pkg\$ThemeName"
if (Test-Path "$root\.pkg") { Remove-Item "$root\.pkg" -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item "$root\dist\*" $stage -Recurse -Force

# 3. 把 dist/index.html 转换成 dashboard.blade.php
Say "3/6 生成 dashboard.blade.php"
$html = Get-Content "$stage\index.html" -Raw -Encoding UTF8

# 3.1 相对路径 -> /theme/{{ $theme }}/ 绝对路径（static/、images/、随机配置 js 等）
$html = $html -replace '(\.\./|\./)', '/theme/{{ $theme }}/'

# 3.2 标题与描述交给 Xboard 后台（$$ 是 .NET 正则替换里的字面量 $）
$html = [regex]::Replace($html, '<title>.*?</title>', '<title>{{ $title }}</title>')
if ($html -notmatch '<meta name="description"') {
    $descTag = '<meta charset="UTF-8">' + "`n" + '    <meta name="description" content="{{ $description }}" >'
    $html = [regex]::Replace($html, '(<meta charset="UTF-8">)', $descTag, 1)
}

# 3.3 注入 Xboard 后台"主题设置"下发的值（baseConfig 读取 window.EZ_THEME_SETTINGS）
$nl = [Environment]::NewLine
$settingsScript = $nl +
    '    <script>' + $nl +
    '        window.EZ_THEME_SETTINGS = {!! json_encode($theme_config ?? [], JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT) !!};' + $nl +
    '    </script>'
$html = [regex]::Replace($html, '<head(\s[^>]*)?>', { param($m) $m.Value + $settingsScript }, 1)

# 3.4 </body> 前注入后台可填的自定义 HTML（公告条 / 统计代码等）
# 键名用平键 ez_custom_html（field_name 不允许点号），兼容旧点号键；$theme_config 必须转义防 PowerShell 插值
$customHtml = "    {!! (`$theme_config['ez_custom_html'] ?? (`$theme_config['EZ_CUSTOM_HTML'] ?? '')) !!}" + $nl
$html = $html.Replace('</body>', $customHtml + '</body>')

# dashboard.blade.php 同样写成无 BOM UTF-8（BOM 会被原样输出到页面顶部）
[System.IO.File]::WriteAllText("$stage\dashboard.blade.php", $html, (New-Object System.Text.UTF8Encoding($false)))
Remove-Item "$stage\index.html" -Force -ErrorAction SilentlyContinue

# 4. config.json：声明后台可编辑字段（Xboard 按 configs 生成表单，default_value 播种数据库）
Say "4/6 生成 config.json"
$config = @{
    name        = $ThemeName
    description = "EZ THEME frontend for XBoard (giftcard/wallet fixed, admin-editable)"
    version     = $Version
    images      = ""
    configs     = @(
        # 注意：field_name 必须是"平键"（不能含点号）。
        # 后台表单 react-hook-form 会把点号当嵌套路径，后端 updateConfig 的 only() 只认平键，
        # 两者不匹配会导致点号字段被全部过滤 -> 保存后写入 null -> 表单回退。
        # 平键 -> 内部配置的映射在 src/utils/baseConfig.js 的 EZ_FIELD_MAP 中完成。
        @{
            label = "主题色"; field_name = "ez_primary_color"; field_type = "select"
            placeholder = "选择全局主题色（按钮/导航高亮/卡片悬浮随之变化）"
            select_options = @{
                "#355cc2" = "主题蓝"; "#00947c" = "青绿"; "#7c3aed" = "紫罗兰"
                "#f97316" = "活力橙"; "#ef4444" = "警示红"; "#0e7490" = "深青"
            }
            default_value = "#355cc2"
        }
        @{
            label = "默认外观模式"; field_name = "ez_default_theme"; field_type = "select"
            placeholder = "首次访问的明暗模式"
            select_options = @{ "light" = "浅色"; "dark" = "深色" }
            default_value = "light"
        }
        @{
            label = "站点名称"; field_name = "ez_site_name"; field_type = "input"
            placeholder = "显示于顶栏 Logo 旁与浏览器标题"; default_value = "EZ THEME"
        }
        @{
            label = "站点描述"; field_name = "ez_site_description"; field_type = "input"
            placeholder = "用于 SEO 描述"; default_value = "EZ UI"
        }
        @{
            label = "版权文案"; field_name = "ez_copyright"; field_type = "input"
            placeholder = "页脚版权行"; default_value = "© EZ THEME. All Rights Reserved."
        }
        @{
            label = "首页标语（中文）"; field_name = "ez_landing_text_zh"; field_type = "input"
            placeholder = "Landing 页大标题"; default_value = "探索全球网络无限可能"
        }
        @{
            label = "API 地址模式"; field_name = "ez_api_url_mode"; field_type = "select"
            placeholder = "auto=自动跟随当前访问域名；static=使用包内写死地址"
            select_options = @{ "auto" = "auto（推荐，换域名无需重打包）"; "static" = "static（写死地址）" }
            default_value = $ApiUrlMode
        }
        @{
            label = "自定义 HTML"; field_name = "ez_custom_html"; field_type = "textarea"
            placeholder = "注入到页面底部，可放公告条/统计代码（支持 HTML）"; default_value = ""
        }
        @{
            label = "节点详情按钮"; field_name = "ez_node_detail_btn"; field_type = "select"
            placeholder = '节点卡片右上角的三个点按钮（点击弹出节点详情）'
            select_options = @{ "true" = "显示"; "false" = "隐藏" }
            default_value = "false"
        }
        @{
            label = "礼品卡入口"; field_name = "ez_show_giftcard"; field_type = "select"
            placeholder = "顶栏礼盒按钮与用户中心的礼品卡兑换入口"
            select_options = @{ "true" = "显示"; "false" = "隐藏" }
            default_value = "true"
        }
        @{
            label = "钱包入口"; field_name = "ez_show_wallet_entry"; field_type = "select"
            placeholder = '头像下拉菜单的"我的钱包"及"更多"页钱包入口'
            select_options = @{ "true" = "显示"; "false" = "隐藏" }
            default_value = "true"
        }
        @{
            label = "充值余额卡片"; field_name = "ez_show_recharge_card"; field_type = "select"
            placeholder = '"更多"页的充值余额卡片'
            select_options = @{ "true" = "显示"; "false" = "隐藏" }
            default_value = "true"
        }
        @{
            label = "客服链接"; field_name = "ez_service_url"; field_type = "input"
            placeholder = "https:// 开头的外链（如 Telegram/Tawto）；留空则用内置客服页"; default_value = ""
        }
        @{
            label = "商店须知弹窗"; field_name = "ez_announcement_enabled"; field_type = "select"
            placeholder = '进入商店页时弹出的"用户须知"弹窗'
            select_options = @{ "true" = "开启"; "false" = "关闭" }
            default_value = "false"
        }
        @{
            label = "商店弹窗标题"; field_name = "ez_announcement_title"; field_type = "input"
            placeholder = "弹窗标题"; default_value = "用户须知"
        }
        @{
            label = "商店弹窗内容"; field_name = "ez_announcement_content"; field_type = "textarea"
            placeholder = "弹窗内容（支持 HTML）"; default_value = ""
        }
        @{
            label = "iOS客户端下载地址"; field_name = "ez_client_ios"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
        @{
            label = "Android客户端下载地址"; field_name = "ez_client_android"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
        @{
            label = "Windows客户端下载地址"; field_name = "ez_client_windows"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
        @{
            label = "MacOS客户端下载地址"; field_name = "ez_client_macos"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
        @{
            label = "Openwrt客户端下载地址"; field_name = "ez_client_openwrt"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
        @{
            label = "Linux客户端下载地址"; field_name = "ez_client_linux"; field_type = "input"
            placeholder = "请输入下载地址"; default_value = ""
        }
    )
}
$config | ConvertTo-Json -Depth 6 | ForEach-Object {
    # 必须写成无 BOM 的 UTF-8：PowerShell 5.1 的 Set-Content -Encoding UTF8 会带 BOM，
    # PHP json_decode() 遇到 BOM 返回 null，Xboard 会报 "Theme name not configured"。
    [System.IO.File]::WriteAllText("$stage\config.json", $_, (New-Object System.Text.UTF8Encoding($false)))
}

# 5. 打成 ZIP（上传器限制：≤10MB、文件名仅 ASCII）
# 注意：PowerShell 5.1 的 Compress-Archive 会在 ZIP 内写反斜杠路径，Linux 侧解压会失败，
#      因此用 .NET ZipArchive 手动写入并强制正斜杠路径。
Say "5/6 打包 ZIP"
$out = "$root\EZTheme.zip"
if (Test-Path $out) { Remove-Item $out -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$fs = [System.IO.File]::Open($out, [System.IO.FileMode]::CreateNew)
$archive = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
$stageFull = (Resolve-Path $stage).Path
Get-ChildItem $stage -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($stageFull.Length).TrimStart('\') -replace '\\', '/'
    $entry = $archive.CreateEntry("$ThemeName/$rel", [System.IO.Compression.CompressionLevel]::Optimal)
    $es = $entry.Open()
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $es.Write($bytes, 0, $bytes.Length)
    $es.Close()
}
$archive.Dispose()
$fs.Close()
$zipItem = Get-Item $out
"{0}  ({1:N2} MB)" -f $out, ($zipItem.Length / 1MB)
if ($zipItem.Length -gt 10MB) { throw "超过 Xboard 上传限制 10MB" }

# 6. 校验包结构
Say "6/6 校验包结构"
$zip = [System.IO.Compression.ZipFile]::OpenRead($out)
$entries = $zip.Entries.FullName
$zip.Dispose()
if (($entries | Where-Object { $_ -match '\\' }).Count -gt 0) { throw "ZIP 内存在反斜杠路径，Linux 无法正确解压" }
$required = @("$ThemeName/config.json", "$ThemeName/dashboard.blade.php")
foreach ($r in $required) {
    if ($entries -notcontains $r) { throw "ZIP 缺少 $r" }
}
$entries | Where-Object { $_ -notmatch '/static/' } | ForEach-Object { "  $_" }
Write-Host "`n完成。后台上传：系统设置 -> 主题设置 -> 上传主题" -ForegroundColor Green
Write-Host "提示：主题名 $ThemeName 与现有 EZThemeFixed 不同，上传后作为新主题出现在列表，切换即可。" -ForegroundColor Yellow
