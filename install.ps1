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

Write-Host "已安装到 $OpenCodeDir"
Write-Host "重启 OpenCode 或重新加载会话后生效。"
