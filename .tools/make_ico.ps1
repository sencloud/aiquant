# 从 app_icon.png 生成多尺寸 Windows .ico
# 用法：powershell -ExecutionPolicy Bypass -File .tools\make_ico.ps1
Add-Type -AssemblyName System.Drawing

$src = "d:\GitHub\aiquant\assets\branding\app_icon.png"
$out = "d:\GitHub\aiquant\windows\runner\resources\app_icon.ico"
$sizes = @(16, 32, 48, 64, 128, 256)

$imgs = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($src)
    if ($bmp.Width -ne $s) {
        $scaled = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($scaled)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($bmp, 0, 0, $s, $s)
        $g.Dispose()
        $bmp.Dispose()
        $bmp = $scaled
    }
    $imgs += ,$bmp
}

# ICO 格式：6 字节头 + 每图 16 字节目录项 + PNG 数据
# Windows Vista+ 支持 PNG 压缩嵌入，256px 推荐 PNG。
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

# ICONDIR
$bw.Write([UInt16]0)          # reserved
$bw.Write([UInt16]1)          # type = icon
$bw.Write([UInt16]$imgs.Count)

# 计算数据区起始偏移
$offset = 6 + 16 * $imgs.Count
$dataBlocks = @()
foreach ($bmp in $imgs) {
    $pngMs = New-Object System.IO.MemoryStream
    $bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
    $dataBlocks += ,$pngMs.ToArray()

    $w = if ($bmp.Width -ge 256) { 0 } else { $bmp.Width }
    $h = if ($bmp.Height -ge 256) { 0 } else { $bmp.Height }
    $bw.Write([Byte]$w)
    $bw.Write([Byte]$h)
    $bw.Write([Byte]0)        # color count
    $bw.Write([Byte]0)        # reserved
    $bw.Write([UInt16]1)      # color planes
    $bw.Write([UInt16]32)     # bits per pixel
    $bw.Write([UInt32]$pngMs.Length)
    $bw.Write([UInt32]$offset)
    $offset += $pngMs.Length
    $bmp.Dispose()
}
foreach ($d in $dataBlocks) { $bw.Write($d) }
$bw.Flush()

[System.IO.File]::WriteAllBytes($out, $ms.ToArray())
$bw.Dispose()
Write-Output "ico written: $out ($((Get-Item $out).Length) bytes)"
