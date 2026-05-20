# agent-collab 全局安装脚本 (PowerShell)
#
# 用法:
#   .\install-global.ps1                      # 安装到默认全局目录
#   .\install-global.ps1 -Target "D:\custom"  # 安装到指定目录
#   .\install-global.ps1 -WhatIf              # 预览操作，不实际执行
#
# 说明:
#   将 agent-collab 插件安装到 OpenCode 全局配置目录，使审批门控、
#   Git 保护等能力在所有项目中生效。项目的协作状态和配置仍然按项目独立。

param(
    [string]$Target = "$env:USERPROFILE\.config\opencode",
    [switch]$WhatIf
)

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------

function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Step {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor White
}

# ---------------------------------------------------------------------------
# 变量
# ---------------------------------------------------------------------------

$GlobalDir = $Target
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginEntry = "./plugins/agent-collab"

# ---------------------------------------------------------------------------
# 开头说明
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  agent-collab 全局安装" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host ""
Write-Info "全局安装说明："
Write-Host "  - JS 插件的审批门控和 Git 保护将在所有项目中生效"
Write-Host "  - 每个项目的协作状态和配置 (agent-collab.config.json) 仍然按项目独立"
Write-Host "  - 如需自定义某项目的配置，在该项目的 .opencode/ 目录下创建"
Write-Host "    agent-collab.config.json 即可覆盖全局默认"
Write-Host "  - 安装完成后需要重启 OpenCode"
Write-Host ""

if ($WhatIf) {
    Write-Warn "[WhatIf 模式] 以下操作仅预览，不会实际执行"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# 步骤 1：创建目标目录结构
# ---------------------------------------------------------------------------

Write-Info "[1/4] 创建全局目录结构..."

$Directories = @(
    (Join-Path $GlobalDir "agents")
    (Join-Path $GlobalDir "skills")
    (Join-Path $GlobalDir "plugins\agent-collab")
    (Join-Path $GlobalDir "scripts\agent-collab")
)

foreach ($Dir in $Directories) {
    if (-not (Test-Path $Dir)) {
        Write-Step "创建目录: $Dir"
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        }
    }
}

# ---------------------------------------------------------------------------
# 步骤 2：复制组件
# ---------------------------------------------------------------------------

Write-Info "[2/4] 复制组件到全局目录..."

# Agents
$AgentsSource = Join-Path $ScriptDir ".opencode\agents\*"
$AgentsDest = Join-Path $GlobalDir "agents\"
if (Test-Path $AgentsSource) {
    Write-Step "Agents -> $AgentsDest"
    if (-not $WhatIf) {
        Copy-Item -Recurse -Force $AgentsSource $AgentsDest
    }
} else {
    Write-Warn "  跳过 Agents（源目录不存在）"
}

# Skills
$SkillsSource = Join-Path $ScriptDir ".opencode\skills\*"
$SkillsDest = Join-Path $GlobalDir "skills\"
if (Test-Path $SkillsSource) {
    Write-Step "Skills -> $SkillsDest"
    if (-not $WhatIf) {
        Copy-Item -Recurse -Force $SkillsSource $SkillsDest
    }
} else {
    Write-Warn "  跳过 Skills（源目录不存在）"
}

# JS Plugin
$PluginSource = Join-Path $ScriptDir "plugin\*"
$PluginDest = Join-Path $GlobalDir "plugins\agent-collab\"
if (Test-Path $PluginSource) {
    Write-Step "JS Plugin -> $PluginDest"
    if (-not $WhatIf) {
        Copy-Item -Recurse -Force $PluginSource $PluginDest
    }
} else {
    Write-Warn "  跳过 JS Plugin（源目录不存在）"
}

# 默认配置（仅当目标不存在时复制，避免覆盖用户已有配置）
$ConfigSource = Join-Path $ScriptDir "agent-collab.config.json"
$ConfigDest = Join-Path $GlobalDir "agent-collab.config.json"
if (Test-Path $ConfigSource) {
    if (Test-Path $ConfigDest) {
        Write-Warn "  默认配置已存在，跳过（不覆盖）: $ConfigDest"
    } else {
        Write-Step "默认配置 -> $ConfigDest"
        if (-not $WhatIf) {
            Copy-Item -Force $ConfigSource $ConfigDest
        }
    }
} else {
    Write-Warn "  跳过默认配置（源文件不存在）"
}

# Scripts（可选）
$ScriptsSource = Join-Path $ScriptDir "scripts\*"
$ScriptsDest = Join-Path $GlobalDir "scripts\agent-collab\"
if (Test-Path $ScriptsSource) {
    Write-Step "Scripts -> $ScriptsDest"
    if (-not $WhatIf) {
        Copy-Item -Recurse -Force $ScriptsSource $ScriptsDest
    }
} else {
    Write-Warn "  跳过 Scripts（源目录不存在）"
}

# Commands（可选）
$CommandsSource = Join-Path $ScriptDir "commands\*"
$CommandsDest = Join-Path $GlobalDir "commands\"
if (Test-Path $CommandsSource) {
    Write-Step "Commands -> $CommandsDest"
    if (-not $WhatIf) {
        if (-not (Test-Path $CommandsDest)) {
            New-Item -ItemType Directory -Path $CommandsDest -Force | Out-Null
        }
        Copy-Item -Recurse -Force $CommandsSource $CommandsDest
    }
} else {
    Write-Warn "  跳过 Commands（源目录不存在）"
}

# ---------------------------------------------------------------------------
# 步骤 3：注册插件到全局 opencode.json
# ---------------------------------------------------------------------------

Write-Info "[3/4] 注册插件到全局 opencode.json..."

$OpenCodeJson = Join-Path $GlobalDir "opencode.json"

if (Test-Path $OpenCodeJson) {
    # 已有配置文件：合并 plugin 数组
    try {
        $config = Get-Content $OpenCodeJson -Raw | ConvertFrom-Json
        $plugins = @()
        if ($config.plugin) {
            $plugins = @($config.plugin)
        }
        if ($plugins -notcontains $PluginEntry) {
            Write-Step "将 agent-collab 添加到 plugin 数组"
            if (-not $WhatIf) {
                $plugins += $PluginEntry
                $config | Add-Member -NotePropertyName "plugin" -NotePropertyValue $plugins -Force
                $config | ConvertTo-Json -Depth 10 | Set-Content $OpenCodeJson -Encoding UTF8
            }
        } else {
            Write-Step "agent-collab 插件已注册，跳过"
        }
    } catch {
        Write-Warn "  无法解析 $OpenCodeJson，请手动添加 `"plugin`": [`"$PluginEntry`"]"
    }
} else {
    # 无配置文件：创建新的
    Write-Step "创建 $OpenCodeJson 并注册插件"
    if (-not $WhatIf) {
        @{
            '$schema' = "https://opencode.ai/config.json"
            plugin    = @($PluginEntry)
        } | ConvertTo-Json -Depth 10 | Set-Content $OpenCodeJson -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# 步骤 4：完成
# ---------------------------------------------------------------------------

Write-Info "[4/4] 安装完成"
Write-Host ""

if ($WhatIf) {
    Write-Warn "[WhatIf 模式] 以上操作未实际执行。去掉 -WhatIf 参数以执行安装。"
} else {
    Write-Success "agent-collab 已全局安装到: $GlobalDir"
    Write-Host ""
    Write-Host "请重启 OpenCode 以使插件生效。" -ForegroundColor Yellow
}
Write-Host ""
