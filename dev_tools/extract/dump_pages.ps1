param([string]$DataWin, [string]$OutDir, [string]$Pages)

$d = [System.IO.File]::ReadAllBytes($DataWin)
function I([int]$o) { [BitConverter]::ToInt32($d, $o) }

# localizar el chunk TXTR
$pos = 8
$txtr = 0
while ($pos + 8 -le $d.Length) {
    $name = [Text.Encoding]::ASCII.GetString($d, $pos, 4)
    $len = I ($pos + 4)
    if ($name -eq 'TXTR') { $txtr = $pos + 8; break }
    $pos += 8 + $len
}
$count = I $txtr
$blobs = @()
for ($t = 0; $t -lt $count; $t++) {
    $entry = I ($txtr + 4 + 4 * $t)
    for ($k = 0; $k -lt 32; $k += 4) {
        $p = I ($entry + $k)
        if ($p -gt 0 -and $p + 8 -lt $d.Length -and $d[$p] -eq 0x32 -and $d[$p+1] -eq 0x7A -and $d[$p+2] -eq 0x6F -and $d[$p+3] -eq 0x71) {
            $blobs += $p
            break
        }
    }
}
Write-Output "paginas con 2zoq: $($blobs.Count) de $count"

foreach ($pg in ($Pages -split ',')) {
    $i = [int]$pg
    $start = $blobs[$i]
    if ($i + 1 -lt $blobs.Count) { $end = $blobs[$i + 1] } else { $end = $d.Length }
    $len = $end - $start
    $outFile = Join-Path $OutDir "blob_$i.bin"
    $buf = New-Object byte[] $len
    [Array]::Copy($d, $start, $buf, 0, $len)
    [System.IO.File]::WriteAllBytes($outFile, $buf)
    $hex = ($buf[0..31] | ForEach-Object { $_.ToString('x2') }) -join ' '
    Write-Output "pagina $i : offset $start longitud $len"
    Write-Output "  cabecera: $hex"
}
