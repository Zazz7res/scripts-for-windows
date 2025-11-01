<#
.SYNOPSIS
    诊断 GitHub 连接问题并智能更新 hosts 文件。
.DESCRIPTION
    本脚本专为仅需访问 GitHub 的用户设计，不依赖 Google 等其他境外网站。
    它通过检测 GitHub 域名的 DNS 解析与 TCP 连通性，判断是否为 DNS 污染，
    并据此智能更新 hosts 文件，提升访问成功率。
.NOTES
    Author: Harry
    Date: 2025-11-01
    重要提示：请务必以管理员身份运行此脚本！否则无法写入 hosts 文件。
#>

# ==============================
# 第一部分：配置常量
# ==============================

# 定义需要解析的 GitHub 核心域名
$GitHubDomains = @(
    "github.com",
    "www.github.com",
    "gist.github.com",
    "api.github.com",
    "raw.githubusercontent.com",      # 用于 raw 文件（如代码、图片）
    "assets-cdn.github.com"          # 用于静态资源（如头像、CSS/JS）
)

# 使用 Google Public DNS (8.8.8.8) 作为“干净 DNS”源，用于获取未被污染的 IP
$ReliableDNS = "8.8.8.8"

# ==============================
# 第二部分：诊断阶段（仅围绕 GitHub）
# ==============================

Write-Host "🔍 [诊断阶段] 正在分析 GitHub 访问问题（不依赖 Google 或其他外网）..." -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------
# 2.1 DNS 污染检测：对比本地 DNS 与干净 DNS (8.8.8.8) 的解析结果
# ----------------------------------------
Write-Host "📡 正在测试 GitHub 域名的 DNS 解析是否被污染..." -ForegroundColor Yellow
$IsDnsPolluted = $false
$ValidIps = @{}

foreach ($domain in $GitHubDomains) {
    try {
        # 本地 DNS 解析结果
        $LocalIP = (Resolve-DnsName -Name $domain -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress
        # 通过 8.8.8.8 获取“干净”IP
        $CleanIP = (Resolve-DnsName -Name $domain -Server $ReliableDNS -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1).IPAddress

        if ($LocalIP -ne $CleanIP) {
            $IsDnsPolluted = $true
            Write-Host "   - 发现污染: $domain (本地: $LocalIP, 清洁: $CleanIP)" -ForegroundColor DarkYellow
        } else {
            Write-Host "   - 解析正常: $domain ($CleanIP)" -ForegroundColor Green
        }
        $ValidIps[$domain] = $CleanIP
    } catch {
        Write-Host "   - 解析失败: $domain，使用后备 IP" -ForegroundColor Red
        switch ($domain) {
            "github.com" { $ValidIps[$domain] = "20.205.243.166" }
            "gist.github.com" { $ValidIps[$domain] = "20.205.243.166" }
            "api.github.com" { $ValidIps[$domain] = "20.205.243.166" }
            "assets-cdn.github.com" { $ValidIps[$domain] = "20.205.243.166" }
            "raw.githubusercontent.com" { 
                $ValidIps[$domain] = @("185.199.108.133", "185.199.109.133", "185.199.110.133", "185.199.111.133") 
            }
            default { $ValidIps[$domain] = "20.205.243.166" }
        }

        if ($domain -eq "raw.githubusercontent.com") {
            Write-Host "     使用后备 CDN IP: $($ValidIps[$domain] -join ', ')"
        } else {
            Write-Host "     使用后备 IP: $($ValidIps[$domain])"
        }
    }
}

# ----------------------------------------
# 2.2 TCP 连通性测试：验证能否连接到 GitHub 的 IP（端口 443）
# ----------------------------------------
Write-Host ""
Write-Host "🔌 正在测试到 GitHub 服务器的 TCP 连通性（端口 443）..." -ForegroundColor Yellow
$CanConnectToIP = $false
$TestDomain = "github.com"
$TestIP = $ValidIps[$TestDomain]

try {
    $Result = Test-NetConnection -ComputerName $TestIP -Port 443 -InformationLevel Quiet -TimeoutSeconds 5
    if ($Result.TcpTestSucceeded) {
        $CanConnectToIP = $true
    }
} catch {
    $CanConnectToIP = $false
}

# 如果连 GitHub 的 IP 都无法建立 TCP 连接，说明网络层被阻断
if (-not $CanConnectToIP) {
    Write-Host "🛑 [诊断结论] GitHub IP 被 TCP 重置/阻断" -ForegroundColor Red
    Write-Host "   - 无法连接到 GitHub 服务器（IP: $TestIP），即使 IP 正确。"
    Write-Host "   - 原因：网络层阻断（如防火墙 RST）"
    Write-Host "   - hosts 方案成功率：<10%"
    Write-Host "   - 建议：请使用代理工具（如 Clash、V2Ray）绕过阻断。"
    exit
}

# ----------------------------------------
# 2.3 诊断总结（仅基于 GitHub 行为）
# ----------------------------------------
Write-Host ""
if ($IsDnsPolluted) {
    Write-Host "✅ [诊断结论] DNS 污染（最常见）" -ForegroundColor Green
    Write-Host "   - 本地 DNS 返回了错误的 GitHub IP。"
    Write-Host "   - hosts 方案成功率：高（70%~90%）"
    Write-Host "   - 操作：即将更新 hosts 文件..."
} else {
    Write-Host "⚠️ [诊断结论] 可能是 hosts 条目过期或 CDN IP 变动" -ForegroundColor DarkYellow
    Write-Host "   - DNS 解析正常，但旧 hosts 可能失效。"
    Write-Host "   - hosts 方案成功率：中（30%~50%）"
    Write-Host "   - 操作：仍将更新 hosts 以确保最新。"
}

# ==============================
# 第三部分：更新 hosts 文件
# ==============================
Write-Host ""
Write-Host "🛠️ [执行阶段] 正在更新 hosts 文件..." -ForegroundColor Cyan

$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$BackupPath = "$HostsPath.github_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Copy-Item -Path $HostsPath -Destination $BackupPath
Write-Host "   - 已备份原始 hosts 文件到: $BackupPath" -ForegroundColor Gray

# 读取并清理旧的 GitHub hosts 块
$HostsContent = Get-Content -Path $HostsPath -ErrorAction Stop
$NewHostsContent = @()
$InGitHubBlock = $false

foreach ($line in $HostsContent) {
    if ($line -match "# =+ GitHub Hosts Start =+") {
        $InGitHubBlock = $true
        continue
    }
    if ($line -match "# =+ GitHub Hosts End =+") {
        $InGitHubBlock = $false
        continue
    }
    if (-not $InGitHubBlock) {
        $NewHostsContent += $line
    }
}

# 构建新的 hosts 块
$GitHubHostsBlock = @()
$GitHubHostsBlock += "# =================================================="
$GitHubHostsBlock += "# GitHub Hosts Start"
$GitHubHostsBlock += "# Updated by Update-GitHubHosts.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$GitHubHostsBlock += "# This block is managed by script. Do not edit manually."
$GitHubHostsBlock += "# =================================================="

foreach ($domain in $GitHubDomains) {
    $ips = $ValidIps[$domain]
    if ($ips -is [array]) {
        foreach ($ip in $ips) {
            $GitHubHostsBlock += "$ip`t$domain"
        }
    } else {
        $GitHubHostsBlock += "$ips`t$domain"
    }
}

$GitHubHostsBlock += "# =================================================="
$GitHubHostsBlock += "# GitHub Hosts End"
$GitHubHostsBlock += "# =================================================="

# 写入 hosts（使用 ASCII 编码避免 BOM 问题）
$FinalContent = $NewHostsContent + $GitHubHostsBlock
Set-Content -Path $HostsPath -Value ($FinalContent -join "`n") -Encoding ASCII -Force

ipconfig /flushdns | Out-Null
Write-Host "   - hosts 文件已成功更新，并刷新了 DNS 缓存。" -ForegroundColor Green

# ==============================
# 第四部分：完成提示
# ==============================
Write-Host ""
Write-Host "✅ [完成] hosts 文件更新成功！" -ForegroundColor Green
Write-Host "   - 请尝试访问 https://github.com 进行验证。"
Write-Host "   - 建议每周运行一次此脚本，以应对 GitHub IP 变动。"
Write-Host "   - 若仍无法访问，可能需使用代理工具。"