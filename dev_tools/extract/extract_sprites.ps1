param(
    [string]$DataWin,
    [string]$OutDir,
    [string]$Names
)

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Text;

public static class WinSprites
{
    static byte[] d;
    static int I(int o) { return BitConverter.ToInt32(d, o); }
    static int U16(int o) { return BitConverter.ToUInt16(d, o); }

    static string Str(int ptr)
    {
        int e = ptr;
        while (e < d.Length && d[e] != 0) e++;
        return Encoding.UTF8.GetString(d, ptr, e - ptr);
    }

    public static string Run(string path, string outDir, string[] wanted)
    {
        var log = new StringBuilder();
        d = File.ReadAllBytes(path);
        Directory.CreateDirectory(outDir);

        var chunks = new Dictionary<string, int[]>();
        int pos = 8;
        while (pos + 8 <= d.Length)
        {
            string name = Encoding.ASCII.GetString(d, pos, 4);
            int len = I(pos + 4);
            chunks[name] = new int[] { pos + 8, len };
            pos += 8 + len;
        }
        log.AppendLine("chunks: " + string.Join(",", new List<string>(chunks.Keys).ToArray()));

        int tpagStart = chunks["TPAG"][0], tpagEnd = tpagStart + chunks["TPAG"][1];

        // Texturas: localizar el blob de cada pagina
        int txtrStart = chunks["TXTR"][0];
        int texCount = I(txtrStart);
        var textures = new List<Bitmap>();
        for (int t = 0; t < texCount; t++)
        {
            int entry = I(txtrStart + 4 + 4 * t);
            Bitmap bmp = null;
            for (int k = 0; k < 32 && bmp == null; k += 4)
            {
                int p = I(entry + k);
                if (p > 0 && p + 8 < d.Length)
                {
                    bool png = d[p] == 0x89 && d[p + 1] == 0x50 && d[p + 2] == 0x4E && d[p + 3] == 0x47;
                    bool qoi = d[p] == 'f' && d[p + 1] == 'i' && d[p + 2] == 'o' && d[p + 3] == 'q';
                    bool bz = d[p] == '2' && d[p + 1] == 'z' && d[p + 2] == 'o' && d[p + 3] == 'q';
                    if (png)
                    {
                        try
                        {
                            var ms = new MemoryStream(d, p, d.Length - p);
                            bmp = new Bitmap(ms);
                            log.AppendLine("texture " + t + ": PNG " + bmp.Width + "x" + bmp.Height);
                        }
                        catch (Exception ex) { log.AppendLine("texture " + t + ": PNG error " + ex.Message); }
                    }
                    else if (qoi || bz)
                    {
                        log.AppendLine("texture " + t + ": formato " + (qoi ? "QOI" : "BZ2+QOI") + " (no soportado aqui)");
                        break;
                    }
                }
            }
            textures.Add(bmp);
        }

        int sprtStart = chunks["SPRT"][0];
        int sprCount = I(sprtStart);
        log.AppendLine("sprites: " + sprCount);

        for (int s = 0; s < sprCount; s++)
        {
            int p = I(sprtStart + 4 + 4 * s);
            if (p == 0) continue;
            string name = Str(I(p));
            if (Array.IndexOf(wanted, name) < 0) continue;

            int w = I(p + 4), h = I(p + 8), ox = I(p + 52), oy = I(p + 56);
            int start = p + 60;
            int found = -1, cnt = 0;
            for (int k = 0; k < 96 && found < 0; k += 4)
            {
                int c = I(start + k);
                if (c < 1 || c > 64) continue;
                bool ok = true;
                for (int i = 0; i < c; i++)
                {
                    int tp = I(start + k + 4 + 4 * i);
                    if (tp < tpagStart || tp >= tpagEnd || ((tp - tpagStart) % 22) != 0) { ok = false; break; }
                }
                if (ok) { found = start + k; cnt = c; }
            }
            log.AppendLine(name + ": " + w + "x" + h + " origen(" + ox + "," + oy + ") fotogramas=" + cnt);
            if (found < 0) continue;

            int scale = 4;
            var frames = new List<Bitmap>();
            for (int i = 0; i < cnt; i++)
            {
                int tp = I(found + 4 + 4 * i);
                int sx = U16(tp), sy = U16(tp + 2), sw = U16(tp + 4), sh = U16(tp + 6);
                int tx = U16(tp + 8), ty = U16(tp + 10);
                int page = U16(tp + 20);
                log.AppendLine("  frame " + i + ": src(" + sx + "," + sy + "," + sw + "x" + sh + ") target(" + tx + "," + ty + ") page " + page);

                var frame = new Bitmap(w, h, PixelFormat.Format32bppArgb);
                if (page < textures.Count && textures[page] != null)
                {
                    using (var g = Graphics.FromImage(frame))
                    {
                        g.DrawImage(textures[page], new Rectangle(tx, ty, sw, sh), new Rectangle(sx, sy, sw, sh), GraphicsUnit.Pixel);
                    }
                }
                frames.Add(frame);
                frame.Save(Path.Combine(outDir, name + "_f" + i + ".png"), ImageFormat.Png);
            }

            // Hoja de contacto con indice
            int cell = Math.Max(w, h) * scale + 8;
            int cols = Math.Min(cnt, 6);
            int rows = (cnt + cols - 1) / cols;
            var sheet = new Bitmap(cols * cell, rows * (cell + 18));
            using (var g = Graphics.FromImage(sheet))
            {
                g.Clear(Color.FromArgb(70, 70, 80));
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
                for (int i = 0; i < cnt; i++)
                {
                    int cx = (i % cols) * cell, cy = (i / cols) * (cell + 18);
                    g.DrawImage(frames[i], new Rectangle(cx + 4, cy + 18, w * scale, h * scale));
                    g.DrawString("frame " + i, new Font("Arial", 10), Brushes.White, cx + 4, cy + 2);
                }
            }
            sheet.Save(Path.Combine(outDir, name + "_sheet.png"), ImageFormat.Png);
        }
        return log.ToString();
    }
}
'@

[WinSprites]::Run($DataWin, $OutDir, ($Names -split ','))
