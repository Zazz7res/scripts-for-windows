#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Linux Kernel 官网访问工具
.DESCRIPTION
    以管理员权限访问 Linux Kernel 官方网站 (https://www.kernel.org/)
    包含连接测试、错误处理和备份恢复功能
.NOTES
    需要管理员权限运行，确保网络连接正常
#>

$ErrorActionPreference = 'Continue'

# 设置执行策略
try {
    $Policy = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction Stop
    if ($Policy -notin @('RemoteSigned', 'Unrestricted', 'Bypass')) {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "🔐 已设置执行策略：RemoteSigned" -ForegroundColor Green
    }
} catch {
    Write-Warning "无法设置执行策略，可能影响脚本运行。"
}

Write-Host "`n🚀 正在启动 Linux Kernel 官网访问工具..." -ForegroundColor Cyan
Write-Host "🌐 目标网站: https://www.kernel.org/" -ForegroundColor Yellow

# 1. 测试网络连接
Write-Host "`n🔍 测试网络连接..." -ForegroundColor Cyan
$internetTest = Test-Connection -ComputerName "www.google.com" -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($internetTest) {
    Write-Host "✅ 网络连接正常" -ForegroundColor Green
} else {
    Write-Warning "⚠️ 网络连接可能有问题，但将继续尝试访问 kernel.org"
}

# 2. 测试 kernel.org 的 DNS 解析
Write-Host "`n📡 测试 kernel.org 的 DNS 解析..." -ForegroundColor Cyan
try {
    $dnsResult = Resolve-DnsName -Name "www.kernel.org" -Server 8.8.8.8 -Type A -ErrorAction Stop
    if ($dnsResult) {
        $resolvedIP = $dnsResult[0].IPAddress
        Write-Host "✅ DNS 解析成功: www.kernel.org -> $resolvedIP" -ForegroundColor Green
    }
} catch {
    Write-Warning "⚠️ DNS 解析失败: $_"
    Write-Host "💡 将尝试直接访问网站" -ForegroundColor Yellow
}

# 3. 检查并清理旧的 hosts 条目（如果存在）
$HostsPath = "$env:windir\System32\drivers\etc\hosts"
$BackupPath = "$HostsPath.backup.kernel.$(Get-Date -Format 'yyyyMMddHHmmss')"

try {
    if (Test-Path $HostsPath) {
        $hostsContent = Get-Content $HostsPath -ErrorAction Stop
        if ($hostsContent -match "kernel\.org") {
            Write-Host "`n🧹 检测到旧的 kernel.org hosts 条目，正在备份..." -ForegroundColor Yellow
            Copy-Item $HostsPath $BackupPath -Force
            Write-Host "✅ 已备份 hosts 文件到: $BackupPath" -ForegroundColor Green
            
            # 清理旧的 kernel.org 条目
            $newContent = $hostsContent | Where-Object { $_ -notmatch "kernel\.org" -and $_ -notmatch "# Linux Kernel" }
            $newContent | Set-Content $HostsPath -Force
            Write-Host "✅ 已清理旧的 kernel.org hosts 条目" -ForegroundColor Green
        }
    }
} catch {
    Write-Warning "无法处理 hosts 文件: $_"
}

# 4. 刷新 DNS 缓存
Write-Host "`n🔄 刷新 DNS 缓存..." -ForegroundColor Cyan
ipconfig /flushdns | Out-Null
Write-Host "✅ DNS 缓存已刷新" -ForegroundColor Green

# 5. 尝试访问 kernel.org
Write-Host "`n🌐 尝试访问 https://www.kernel.org/ ..." -ForegroundColor Cyan

try {
    # 使用 Invoke-WebRequest 测试连接
    $webResponse = Invoke-WebRequest -Uri "https://www.kernel.org/" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    if ($webResponse.StatusCode -eq 200) {
        Write-Host "✅ 成功连接到 Linux Kernel 官网!" -ForegroundColor Green
        Write-Host "📊 网站标题: $($webResponse.ParsedHtml.title)" -ForegroundColor Cyan
    }
} catch {
    Write-Warning "⚠️ 无法通过 PowerShell 直接访问网站: $_"
    Write-Host "💡 将尝试通过浏览器打开" -ForegroundColor Yellow
}

# 6. 通过默认浏览器打开网站
try {
    Write-Host "`n🚀 正在通过默认浏览器打开 https://www.kernel.org/ ..." -ForegroundColor Cyan
    Start-Process "https://www.kernel.org/"
    Write-Host "✅ 已成功启动浏览器访问 Linux Kernel 官网" -ForegroundColor Green
    
    # 额外打开内核下载页面
    $openDownloadPage = Read-Host "`n是否同时打开内核下载页面? (Y/N) [默认: N]"
    if ($openDownloadPage -like "Y*") {
        Start-Process "https://www.kernel.org/category/releases.html"
        Write-Host "✅ 已打开内核下载页面" -ForegroundColor Green
    }
} catch {
    Write-Error "❌ 无法打开浏览器: $_"
    Write-Host "`n💡 请手动访问以下网址:" -ForegroundColor Yellow
    Write-Host "   https://www.kernel.org/" -ForegroundColor Cyan
    Write-Host "   https://www.kernel.org/category/releases.html" -ForegroundColor Cyan
}

# 7. 显示额外信息
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "          🐧 Linux Kernel 信息" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "🏠 官方网站: https://www.kernel.org/"
Write-Host "📚 文档: https://www.kernel.org/doc/"
Write-Host "📧 邮件列表: https://www.kernel.org/category/lists.html"
Write-Host "🛠️ 源码: https://git.kernel.org/"
Write-Host "🔧 Bug 跟踪: https://bugzilla.kernel.org/"

Write-Host "`n💡 实用提示:" -ForegroundColor Yellow
Write-Host "   • 如果访问速度慢，可以尝试使用镜像站点"
Write-Host "   • 中国大陆用户可访问清华镜像: https://mirrors.tuna.tsinghua.edu.cn/kernel/"
Write-Host "   • 如需恢复 hosts 备份，使用: copy '$BackupPath' '$HostsPath'"

# 8. 防止窗口立即关闭
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "          🎯 操作完成！" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "`n✅ 脚本执行完毕，浏览器应已打开 Linux Kernel 官网"
Write-Host "`n📌 按任意键关闭此窗口..." -ForegroundColor Yellow
$null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")