```powershell
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    诊断 GitHub 连接问题并智能优化 hosts 文件
.DESCRIPTION
    本脚本专为仅需访问 GitHub 的用户设计，不依赖 Google 等其他境外网站。
    它通过检测 GitHub 域名的 DNS 解析与 TCP 连通性，判断是否为 DNS 污染，
    并据此智能更新 hosts 文件，提升访问成功率。
    新增功能：IP测速优选、彩色用户界面、自动验证
.NOTES
    Author: Harry (增强版)
    Date: 2025-11-09
    重要提示：请务必以管理员身份运行此脚本！否则无法写入 hosts 文件。
#>

$ErrorActionPreference = 'Continue'

# ==============================
# 第零部分：初始化设置
# ==============================

# 设置执行策略（如果需要）
try {
    $Policy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    if ($Policy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "🔐 已设置执行策略：RemoteSigned" -ForegroundColor Green
    }
} catch {
    Write-Warning "无法设置执行策略，可能影响脚本运行。请以管理员身份运行。"
}

Write-Host "`n🚀 正在启动 GitHub 智能优化器 (2025增强版)..." -ForegroundColor Cyan
Write-Host "🔍 本脚本将诊断 GitHub 连接问题并优化访问速度..." -ForegroundColor Yellow

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

# 使用 Google Public DNS (8.8.8.8) 作为"干净 DNS"源，用于获取未被污染的 IP
$ReliableDNS = "8.8.8.8"

# ==============================
# 第二部分：辅助函数
# ==============================

# 测速并选择最佳IP的函数
function Get-FastestIP {
    param(
        [string[]]$IPs,
        [string]$Domain,
        [int]$TestCount = 2
    )
    
    $bestIP = $null
    $lowestLatency = [int]::MaxValue
    
    Write-Host "⚡ 正在对$Domain的 $($IPs.Count) 个候选IP进行测速..." -ForegroundColor Cyan
    
    foreach ($ip in $IPs) {
        $totalLatency = 0
        $successCount = 0
        
        for ($i = 0; $i -lt $TestCount; $i++) {
            $pingResult = Test-Connection -TargetName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($pingResult) {
                $pingTime = (Test-Connection -TargetName $ip -Count 1 -ErrorAction SilentlyContinue).ResponseTime
                $totalLatency += $pingTime
                $successCount++
            }
        }
        
        if ($successCount -gt 0) {
            $avgLatency = [math]::Round($totalLatency / $successCount, 2)
            Write-Host "  📶 $ip : 平均延迟 $avgLatency ms ($successCount/$TestCount 成功)" -ForegroundColor Gray
            
            if ($avgLatency -lt $lowestLatency) {
                $lowestLatency = $avgLatency
                $bestIP = $ip
            }
        } else {
            Write-Host "  ❌ $ip : 无法连接" -ForegroundColor DarkGray
        }
    }
    
    if ($bestIP) {
        Write-Host "🏆 $Domain 最佳IP: $bestIP (平均延迟 $lowestLatency ms)" -ForegroundColor Green
        return $bestIP
    } else {
        Write-Warning "⚠️ 无法确定$Domain的最佳IP，将使用第一个可用IP"
        return $IPs[0]
    }
}

# ==============================
# 第三部分：诊断阶段（仅围绕 GitHub）
# ==============================

Write-Host "`n🔍 [诊断阶段] 正在分析 GitHub 访问问题（不依赖 Google 或其他外网）..." -ForegroundColor Cyan

# ----------------------------------------
# 3.1 DNS 污染检测：对比本地 DNS 与干净 DNS (8.8.8.8) 的解析结果
# ----------------------------------------
Write-Host "`n📡 正在测试 GitHub 域名的 DNS 解析是否被污染..." -ForegroundColor Yellow
$IsDnsPolluted = $false
$ValidIps = @{}

foreach ($domain in $GitHubDomains) {
    try {
        # 本地 DNS 解析结果
        $LocalResult = Resolve-DnsName -Name $domain -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1
        $LocalIP = $LocalResult.IPAddress
        
        # 通过 8.8.8.8 获取"干净"IP
        $CleanResult = Resolve-DnsName -Name $domain -Server $ReliableDNS -ErrorAction Stop | Where-Object { $_.QueryType -eq 'A' } | Select-Object -First 1
        $CleanIP = $CleanResult.IPAddress

        if ($LocalIP -ne $CleanIP) {
            $IsDnsPolluted = $true
            Write-Host "   - 🚨 发现污染: $domain (本地: $LocalIP, 清洁: $CleanIP)" -ForegroundColor DarkYellow
        } else {
            Write-Host "   - ✅ 解析正常: $domain ($CleanIP)" -ForegroundColor Green
        }
        $ValidIps[$domain] = $CleanIP
    } catch {
        Write-Host "   - ❌ 解析失败: $domain，使用后备 IP" -ForegroundColor Red
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
            Write-Host "     🔧 使用后备 CDN IP: $($ValidIps[$domain] -join ', ')"
        } else {
            Write-Host "     🔧 使用后备 IP: $($ValidIps[$domain])"
        }
    }
}

# ----------------------------------------
# 3.2 TCP 连通性测试：验证能否连接到 GitHub 的 IP（端口 443）
# ----------------------------------------
Write-Host "`n🔌 正在测试到 GitHub 服务器的 TCP 连通性（端口 443）..." -ForegroundColor Yellow
$CanConnectToIP = $false
$TestDomain = "github.com"
$TestIP = $ValidIps[$TestDomain]

try {
    $tcpResult = Test-NetConnection -ComputerName $TestIP -Port 443 -InformationLevel Detailed -TimeoutSeconds 5 -ErrorAction Stop
    if ($tcpResult.TcpTestSucceeded) {
        $CanConnectToIP = $true
        Write-Host "   - ✅ 成功连接到 $TestDomain ($TestIP:443)" -ForegroundColor Green
    } else {
        Write-Host "   - ❌ 无法连接到 $TestDomain ($TestIP:443)" -ForegroundColor Red
    }
} catch {
    Write-Host "   - ⚠️ 连接测试异常: $_" -ForegroundColor Yellow
    $CanConnectToIP = $false
}

# 如果连 GitHub 的 IP 都无法建立 TCP 连接，说明网络层被阻断
if (-not $CanConnectToIP) {
    Write-Host "`n🛑 [诊断结论] GitHub IP 被 TCP 重置/阻断" -ForegroundColor Red
    Write-Host "   - 无法连接到 GitHub 服务器（IP: $TestIP），即使 IP 正确。"
    Write-Host "   - 原因：网络层阻断（如防火墙 RST）"
    Write-Host "   - hosts 方案成功率：<10%"
    Write-Host "   - 建议：请使用代理工具（如 Clash、V2Ray）绕过阻断。"
    
    # 仍然询问是否要继续优化
    $continue = Read-Host "`n是否仍要继续更新 hosts 文件？(Y/N) [默认: N]"
    if ($continue -notlike "Y*") {
        exit
    }
}

# ----------------------------------------
# 3.3 诊断总结（仅基于 GitHub 行为）
# ----------------------------------------
Write-Host "`n📊 [诊断总结]" -ForegroundColor Cyan
if ($IsDnsPolluted) {
    Write-Host "✅ [诊断结论] DNS 污染（最常见）" -ForegroundColor Green
    Write-Host "   - 本地 DNS 返回了错误的 GitHub IP。"
    Write-Host "   - hosts 方案成功率：高（70%~90%）"
    Write-Host "   - 操作：即将更新 hosts 文件并进行IP测速优化..."
} else {
    Write-Host "⚠️ [诊断结论] 可能是 hosts 条目过期或 CDN IP 变动" -ForegroundColor DarkYellow
    Write-Host "   - DNS 解析正常，但旧 hosts 可能失效。"
    Write-Host "   - hosts 方案成功率：中（30%~50%）"
    Write-Host "   - 操作：仍将更新 hosts 以确保最新。"
}

# ==============================
# 第四部分：IP测速优化
# ==============================
Write-Host "`n⚡ [优化阶段] 正在对获取到的IP进行测速优选..." -ForegroundColor Cyan

$OptimizedIps = @{}
foreach ($domain in $GitHubDomains) {
    $ips = $ValidIps[$domain]
    
    if ($ips -is [array]) {
        if ($ips.Count -gt 1) {
            $bestIP = Get-FastestIP -IPs $ips -Domain $domain
            $OptimizedIps[$domain] = $bestIP
        } else {
            $OptimizedIps[$domain] = $ips[0]
            Write-Host "✅ $domain 直接使用获取到的IP: $($ips[0])" -ForegroundColor Green
        }
    } else {
        # 单个IP也进行简单验证
        $pingResult = Test-Connection -TargetName $ips -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($pingResult) {
            $pingTime = (Test-Connection -TargetName $ips -Count 1 -ErrorAction SilentlyContinue).ResponseTime
            Write-Host "✅ $domain 验证通过: $ips (延迟: $pingTime ms)" -ForegroundColor Green
        } else {
            Write-Host "⚠️ $domain 无法ping通: $ips，但仍将使用此IP" -ForegroundColor Yellow
        }
        $OptimizedIps[$domain] = $ips
    }
}

# ==============================
# 第五部分：更新 hosts 文件
# ==============================
Write-Host "`n🛠️ [执行阶段] 正在更新 hosts 文件..." -ForegroundColor Cyan

$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$BackupPath = "$HostsPath.github_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

try {
    Copy-Item -Path $HostsPath -Destination $BackupPath -Force
    Write-Host "✅ 已备份原始 hosts 文件到: $BackupPath" -ForegroundColor Green
} catch {
    Write-Warning "⚠️ 无法备份 hosts 文件，但将继续执行: $_"
}

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
$GitHubHostsBlock += "# Updated by GitHub Optimizer on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$GitHubHostsBlock += "# This block is managed by script. Do not edit manually."
$GitHubHostsBlock += "# =================================================="

foreach ($domain in $GitHubDomains) {
    $ip = $OptimizedIps[$domain]
    $GitHubHostsBlock += "$ip`t$domain"
    Write-Host "  • 添加: $ip`t$domain" -ForegroundColor Gray
}

$GitHubHostsBlock += "# =================================================="
$GitHubHostsBlock += "# GitHub Hosts End"
$GitHubHostsBlock += "# =================================================="

# 写入 hosts（使用 ASCII 编码避免 BOM 问题）
$FinalContent = $NewHostsContent + $GitHubHostsBlock
try {
    Set-Content -Path $HostsPath -Value ($FinalContent -join "`n") -Encoding ASCII -Force
    Write-Host "`n✅ hosts 文件已成功更新！" -ForegroundColor Green
} catch {
    Write-Error "❌ 写入hosts文件失败: $_"
    Write-Host "💡 请尝试手动以管理员身份运行记事本，然后打开并保存hosts文件" -ForegroundColor Yellow
    exit 1
}

# 刷新DNS缓存
Write-Host "🔄 正在刷新 DNS 缓存..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Write-Host "✅ DNS 缓存已刷新。" -ForegroundColor Green

# ==============================
# 第六部分：验证测试
# ==============================
Write-Host "`n🔍 [验证阶段] 正在验证 GitHub 连接..." -ForegroundColor Cyan

# 测试主要域名
$testDomains = @("github.com", "raw.githubusercontent.com")
foreach ($domain in $testDomains) {
    Write-Host "🌐 测试访问 $domain..." -NoNewline
    try {
        $resolvedIP = (Resolve-DnsName $domain -ErrorAction Stop).IPAddress
        $result = Test-Connection -TargetName $resolvedIP -Count 2 -Quiet -ErrorAction Stop
        if ($resolvedIP -and $result) {
            Write-Host " ✔️ 成功 (解析到 $resolvedIP)" -ForegroundColor Green
        } else {
            Write-Host " ❌ 失败 (解析到 $resolvedIP)" -ForegroundColor Red
        }
    } catch {
        Write-Host " ❌ 错误: $_" -ForegroundColor Red
    }
}

# ==============================
# 第七部分：自动验证
# ==============================
Write-Host "`n🎉 [完成] 正在尝试打开 GitHub 页面验证效果..." -ForegroundColor Green
try {
    Start-Process "https://github.com"
    Write-Host "✅ 已启动浏览器打开 GitHub" -ForegroundColor Green
    
    # 额外打开内核下载页面
    $openRaw = Read-Host "`n是否同时打开 raw.githubusercontent.com 测试页面? (Y/N) [默认: N]"
    if ($openRaw -like "Y*") {
        Start-Process "https://raw.githubusercontent.com/github/docs/main/README.md"
        Write-Host "✅ 已打开 raw.githubusercontent.com 测试页面" -ForegroundColor Green
    }
} catch {
    Write-Warning "⚠️ 无法自动打开浏览器，请手动访问 https://github.com"
}

# ==============================
# 第八部分：完成提示
# ==============================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "          🎯 GitHub 优化完成！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "✅ 您现在应该可以快速访问 GitHub 及其相关服务"
Write-Host "📌 本次使用的最佳 IP:"
foreach ($domain in $GitHubDomains) {
    Write-Host "   • $domain -> $($OptimizedIps[$domain])"
}

Write-Host "`n💡 实用提示:" -ForegroundColor Yellow
Write-Host "   • 如果访问速度不理想，可以重新运行此脚本获取最新IP"
Write-Host "   • 如需恢复原始设置，请复制备份文件:"
Write-Host "     copy '$BackupPath' '$HostsPath'"
Write-Host "     然后运行: ipconfig /flushdns"
Write-Host "`n   • 建议每周运行一次此脚本，以应对 GitHub IP 变动。"
Write-Host "   • 若仍无法访问，可能需使用代理工具。"

# 防止窗口立即关闭
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "          操作完成！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "`n✅ 脚本执行完毕，浏览器应已打开 GitHub"
Write-Host "`n📌 按任意键关闭此窗口..." -ForegroundColor Yellow
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
```