param([string]$BlobDir, [string]$OutDir)

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;

public static class QoiSheet
{
    public static Bitmap Decode(string path)
    {
        byte[] d = File.ReadAllBytes(path);
        int w = BitConverter.ToUInt16(d, 4), h = BitConverter.ToUInt16(d, 6);
        int p = 12;
        byte[] px = new byte[w * h * 4];
        byte[] idx = new byte[64 * 4];
        byte r = 0, g = 0, b = 0, a = 255;
        int run = 0;
        for (int i = 0; i < w * h; i++)
        {
            if (run > 0) run--;
            else if (p < d.Length)
            {
                int op = d[p++];
                if (op == 0xFE) { r = d[p++]; g = d[p++]; b = d[p++]; }
                else if (op == 0xFF) { r = d[p++]; g = d[p++]; b = d[p++]; a = d[p++]; }
                else if ((op & 0xC0) == 0x00) { int k = op * 4; r = idx[k]; g = idx[k + 1]; b = idx[k + 2]; a = idx[k + 3]; }
                else if ((op & 0xC0) == 0x40)
                {
                    r = (byte)(r + ((op >> 4) & 3) - 2);
                    g = (byte)(g + ((op >> 2) & 3) - 2);
                    b = (byte)(b + (op & 3) - 2);
                }
                else if ((op & 0xC0) == 0x80)
                {
                    int b2 = d[p++];
                    int vg = (op & 0x3F) - 32;
                    r = (byte)(r + vg - 8 + ((b2 >> 4) & 0x0F));
                    g = (byte)(g + vg);
                    b = (byte)(b + vg - 8 + (b2 & 0x0F));
                }
                else run = op & 0x3F;
                int h64 = (r * 3 + g * 5 + b * 7 + a * 11) % 64;
                idx[h64 * 4] = r; idx[h64 * 4 + 1] = g; idx[h64 * 4 + 2] = b; idx[h64 * 4 + 3] = a;
            }
            px[i * 4] = b; px[i * 4 + 1] = g; px[i * 4 + 2] = r; px[i * 4 + 3] = a;
        }
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        System.Runtime.InteropServices.Marshal.Copy(px, 0, bd.Scan0, px.Length);
        bmp.UnlockBits(bd);
        return bmp;
    }

    // frames: sx,sy,sw,sh,tx,ty por fotograma
    public static void Sheet(Bitmap page, int[][] frames, int w, int h, string output, int scale)
    {
        int n = frames.Length, cols = Math.Min(n, 6), rows = (n + cols - 1) / cols;
        int cw = w * scale + 8, ch = h * scale + 26;
        var sheet = new Bitmap(cols * cw, rows * ch);
        using (var g = Graphics.FromImage(sheet))
        {
            g.Clear(Color.FromArgb(60, 70, 85));
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            for (int i = 0; i < n; i++)
            {
                int cx = (i % cols) * cw, cy = (i / cols) * ch;
                var f = frames[i];
                var frame = new Bitmap(w, h, PixelFormat.Format32bppArgb);
                using (var fg = Graphics.FromImage(frame))
                    fg.DrawImage(page, new Rectangle(f[4], f[5], f[2], f[3]), new Rectangle(f[0], f[1], f[2], f[3]), GraphicsUnit.Pixel);
                g.DrawImage(frame, new Rectangle(cx + 4, cy + 22, w * scale, h * scale), new Rectangle(0, 0, w, h), GraphicsUnit.Pixel);
                g.DrawString("frame " + i, new Font("Arial", 11, FontStyle.Bold), Brushes.White, cx + 4, cy + 2);
            }
        }
        sheet.Save(output, ImageFormat.Png);
    }
}
'@

$shrine6 = @(
    @(270,427,61,95,18,31), @(125,918,62,95,17,31), @(213,723,63,95,18,31), @(187,918,61,95,18,31),
    @(64,918,61,103,18,23), @(213,620,61,103,18,23), @(246,525,61,95,18,31), @(150,620,63,126,16,0),
    @(178,315,95,112,0,14), @(150,525,96,95,0,31), @(270,427,61,95,18,31)
)
$empower = @(
    @(714,469,95,175,13,26), @(858,342,95,178,13,23), @(209,1336,113,190,3,11), @(225,955,115,199,0,2),
    @(225,750,115,201,0,0), @(381,355,95,175,13,26), @(480,512,95,175,13,26)
)

$p124 = [QoiSheet]::Decode((Join-Path $BlobDir 'page_124.qoi'))
[QoiSheet]::Sheet($p124, $shrine6, 96, 126, (Join-Path $OutDir 'sShrine6_sheet.png'), 3)
$p66 = [QoiSheet]::Decode((Join-Path $BlobDir 'page_66.qoi'))
[QoiSheet]::Sheet($p66, $empower, 116, 201, (Join-Path $OutDir 'sShrineEmpower_sheet.png'), 2)
Write-Output 'ok'
