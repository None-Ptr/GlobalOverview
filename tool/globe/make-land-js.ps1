# 把 App 用的陆地轮廓数据转成网页版地球能直接引用的 JS。
#
#   powershell -ExecutionPolicy Bypass -File tool\globe\make-land-js.ps1
#
# 源：assets/geo/world_land.json（Natural Earth 110m 简化，public domain）
# 产：docs/land.js —— 内联成 window.GO_LAND，不用 fetch（file:// 下 fetch 本地文件会被 CORS 拦）。
# 坐标保留 1 位小数：对 400px 级别的球足够，体积能小一半。
param()

$src = Join-Path (Split-Path $PSScriptRoot -Parent) '..\assets\geo\world_land.json'
$src = [System.IO.Path]::GetFullPath($src)
$out = Join-Path (Split-Path $PSScriptRoot -Parent) '..\docs\land.js'
$out = [System.IO.Path]::GetFullPath($out)

$json = Get-Content $src -Raw -Encoding UTF8 | ConvertFrom-Json
$ci = [System.Globalization.CultureInfo]::InvariantCulture
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append('// 由 tool\globe\make-land-js.ps1 生成，请勿手改。源：assets/geo/world_land.json' + "`n")
[void]$sb.Append('window.GO_LAND=[')
foreach ($ring in $json.polys) {
    [void]$sb.Append('[')
    $pts = @()
    foreach ($p in $ring) {
        $pts += ('{0},{1}' -f [math]::Round([double]$p[0], 1).ToString('0.0', $ci), [math]::Round([double]$p[1], 1).ToString('0.0', $ci))
    }
    [void]$sb.Append(($pts -join ','))
    [void]$sb.Append('],')
}
[void]$sb.Append('];' + "`n")

[IO.File]::WriteAllText($out, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
$size = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "已生成 $out（$size KB，$(@($json.polys).Count) 环）"
