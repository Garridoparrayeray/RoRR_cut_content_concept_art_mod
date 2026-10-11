param([string]$BlobDir, [string]$OutDir)
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
public static class Q2
{
    public static string Run(string path, string output)
    {
        byte[] d = File.ReadAllBytes(path);
        int w = BitConverter.ToUInt16(d, 4), h = BitConverter.ToUInt16(d, 6);
        int p = 12;
        int[] idx = new int[64];
        int r = 0, g = 0, b = 0, a = 255;
        int run = 0;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        int opaque = 0;
        for (int i = 0; i < w * h; i++)
        {
            if (run > 0) run--;
            else if (p < d.Length)
            {
                int op = d[p++];
                if (op == 0xFE) { r = d[p++]; g = d[p++]; b = d[p++]; }
                else if (op == 0xFF) { r = d[p++]; g = d[p++]; b = d[p++]; a = d[p++]; }
                else if ((op & 0xC0) == 0x00) { int c = idx[op]; a = (c >> 24) & 255; r = (c >> 16) & 255; g = (c >> 8) & 255; b = c & 255; }
                else if ((op & 0xC0) == 0x40) { r = (r + ((op >> 4) & 3) - 2) & 255; g = (g + ((op >> 2) & 3) - 2) & 255; b = (b + (op & 3) - 2) & 255; }
                else if ((op & 0xC0) == 0x80)
                {
                    int b2 = d[p++]; int vg = (op & 0x3F) - 32;
                    r = (r + vg - 8 + ((b2 >> 4) & 15)) & 255; g = (g + vg) & 255; b = (b + vg - 8 + (b2 & 15)) & 255;
                }
                else run = op & 0x3F;
                idx[(r * 3 + g * 5 + b * 7 + a * 11) & 63] = (a << 24) | (r << 16) | (g << 8) | b;
            }
            if (a > 0) opaque++;
            bmp.SetPixel(i % w, i / w, Color.FromArgb(a, r, g, b));
        }
        bmp.Save(output, ImageFormat.Png);
        return w + "x" + h + " pixeles con alpha>0: " + opaque + " bytes consumidos: " + p + " de " + d.Length;
    }
}
'@
[Q2]::Run((Join-Path $BlobDir 'page_124.qoi'), (Join-Path $OutDir 'page124_full.png'))
