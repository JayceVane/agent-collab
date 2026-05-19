# agent-collab 安装脚本 (PowerShell)
# 用法: .\install.ps1 [项目目录]
#       默认安装到当前目录

param(
    [string]$Target = "."
)

$OpenCodeDir = Join-Path $Target ".opencode"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path $Target)) {
    Write-Error "目标目录不存在: $Target"
    exit 1
}

New-Item -ItemType Directory -Path (Join-Path $OpenCodeDir "agents") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OpenCodeDir "skills") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OpenCodeDir "plugins\agent-collab") -Force | Out-Null

Copy-Item -Recurse -Force (Join-Path $ScriptDir ".opencode\agents\*") (Join-Path $OpenCodeDir "agents\")
Copy-Item -Recurse -Force (Join-Path $ScriptDir ".opencode\skills\*") (Join-Path $OpenCodeDir "skills\")
Copy-Item -Recurse -Force (Join-Path $ScriptDir "plugin\*") (Join-Path $OpenCodeDir "plugins\agent-collab\")
Copy-Item -Force (Join-Path $ScriptDir "agent-collab.config.json") (Join-Path $OpenCodeDir "agent-collab.config.json")

# FIX #5: 自动生成或更新 .opencode/opencode.json 注册插件
$OpenCodeJson = Join-Path $OpenCodeDir "opencode.json"
$PluginEntry = "./plugins/agent-collab"

if (Test-Path $OpenCodeJson) {
    # 已有配置文件：合并 plugin 数组
    try {
        $config = Get-Content $OpenCodeJson -Raw | ConvertFrom-Json
        $plugins = @()
        if ($config.plugin) {
            $plugins = @($config.plugin)
        }
        if ($plugins -notcontains $PluginEntry) {
            $plugins += $PluginEntry
            $config | Add-Member -NotePropertyName "plugin" -NotePropertyValue $plugins -Force
            $config | ConvertTo-Json -Depth 10 | Set-Content $OpenCodeJson -Encoding UTF8
            Write-Host "已将 agent-collab 插件注册到 $OpenCodeJson"
        } else {
            Write-Host "agent-collab 插件已在 $OpenCodeJson 中注册，跳过"
        }
    } catch {
        Write-Warning "无法解析 $OpenCodeJson，请手动添加 `"plugin`": [`"$PluginEntry`"]"
    }
} else {
    # 无配置文件：创建新的
    @{
        '$schema' = "https://opencode.ai/config.json"
        plugin    = @($PluginEntry)
    } | ConvertTo-Json -Depth 10 | Set-Content $OpenCodeJson -Encoding UTF8
    Write-Host "已创建 $OpenCodeJson 并注册 agent-collab 插件"
}

Write-Host ""
Write-Host "已安装到 $OpenCodeDir"
Write-Host "重启 OpenCode 或重新加载会话后生效。"
