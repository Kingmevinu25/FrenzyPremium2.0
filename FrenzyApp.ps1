#Requires -Version 5.1
<#
  FRENZY TWEAKS v2.0.0  (WinForms UI + built-in splash loader)
  - Self-elevates, shows the FRENZY splash, builds the UI behind it, fades the splash.
  - Applies / undoes the tweaks from your list.
  - Creates a restore point first; backs up the REAL original value of every registry
    setting, service and task it touches, so Undo restores your actual previous state.
  Run with Windows PowerShell 5.1 as Administrator (it self-elevates).
  Single-file build: this file IS the loader - no external download required.
#>

# ---------- Elevation ----------
$script:AppVersion = '2.0.0'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) { Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$PSCommandPath`"" }
    else { Write-Host 'FRENZY TWEAKS needs Administrator. Re-run the install command from an elevated PowerShell.' -ForegroundColor Red }
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ======================================================================
#  SPLASH / LOADER (merged from FrenzyTweaks.ps1)
# ======================================================================
if (-not ('FzSplashWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FzSplashWin
{
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    public static void Front(IntPtr h)
    {
        try {
            ShowWindow(h, 9);
            keybd_event(0x12, 0, 0, UIntPtr.Zero);
            keybd_event(0x12, 0, 2, UIntPtr.Zero);
            IntPtr fg = GetForegroundWindow();
            uint pid; uint fgT = GetWindowThreadProcessId(fg, out pid); uint me = GetCurrentThreadId();
            if (fgT != 0 && fgT != me) AttachThreadInput(me, fgT, true);
            SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            BringWindowToTop(h); SetForegroundWindow(h);
            if (fgT != 0 && fgT != me) AttachThreadInput(me, fgT, false);
        } catch { }
    }
}
'@
}

function Fz-GetRoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath; $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure(); return $p
}
function Fz-DrawLogo($g, [single]$x, [single]$y, [single]$s) {
    $path = Fz-GetRoundPath $x $y $s $s ($s * 0.24)
    $rect = New-Object Drawing.RectangleF($x, $y, $s, $s)
    $br = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, [Drawing.Color]::FromArgb(255, 178, 36), [Drawing.Color]::FromArgb(255, 66, 0), 55.0)
    $g.FillPath($br, $path)
    $hl = New-Object Drawing.Drawing2D.LinearGradientBrush($rect, [Drawing.Color]::FromArgb(80, 255, 255, 255), [Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillPath($hl, $path)
    $pts = @(@(0.28, 0.20), @(0.74, 0.20), @(0.74, 0.33), @(0.42, 0.33), @(0.42, 0.44), @(0.66, 0.44), @(0.66, 0.56), @(0.42, 0.56), @(0.42, 0.80), @(0.28, 0.80))
    $poly = @(foreach ($q in $pts) { New-Object Drawing.PointF(($x + $s * ($q[0] + 0.10 * (0.5 - $q[1]))), ($y + $s * $q[1])) })
    $g.FillPolygon([Drawing.Brushes]::White, [Drawing.PointF[]]$poly)
    $br.Dispose(); $hl.Dispose(); $path.Dispose()
}
function Fz-Spaced($g, [string]$txt, $font, [single]$sp) {
    $fmt = [Drawing.StringFormat]::GenericTypographic; $pt = New-Object Drawing.PointF(0, 0)
    $nW = $g.MeasureString('n', $font, $pt, $fmt).Width; $xs = New-Object System.Collections.ArrayList; $x = [double]0
    foreach ($ch in $txt.ToCharArray()) {
        [void]$xs.Add([single]$x)
        if ($ch -eq ' ') { $x += $nW * 0.9 + $sp } else { $x += $g.MeasureString([string]$ch, $font, $pt, $fmt).Width + $sp }
    }
    return @{ Txt = $txt; Xs = $xs.ToArray(); Width = [single]($x - $sp) }
}
function Fz-DrawSpaced($g, $info, $font, $brush, [single]$x, [single]$y) {
    $fmt = [Drawing.StringFormat]::GenericTypographic
    for ($i = 0; $i -lt $info.Txt.Length; $i++) {
        $ch = $info.Txt[$i]
        if ($ch -ne ' ') { $g.DrawString([string]$ch, $font, $brush, [single]($x + $info.Xs[$i]), $y, $fmt) }
    }
}

$script:SplashW = 760; $script:SplashH = 480
$script:Splash = @{
    Clock = [Diagnostics.Stopwatch]::StartNew(); Last = 0.0; P = 0.0; Launch = $false; Closing = $false
    Fail = $null; FailAt = 0.0; Fade = $false; Status = $null; TickErrors = 0; FrontTicks = 0
    Parts = New-Object System.Collections.ArrayList
}
$splashRnd = New-Object Random
for ($i = 0; $i -lt 44; $i++) {
    [void]$script:Splash['Parts'].Add(@{
        X = $splashRnd.NextDouble() * $script:SplashW; Y = $splashRnd.NextDouble() * $script:SplashH
        V = 16 + $splashRnd.NextDouble() * 50; S = 1.2 + $splashRnd.NextDouble() * 3.0
        Ph = $splashRnd.NextDouble() * 6.28; A = 0.35 + $splashRnd.NextDouble() * 0.65
    })
}
$splashHeadName = 'Segoe UI'
try { if ((New-Object Drawing.Text.InstalledFontCollection).Families | Where-Object { $_.Name -eq 'Bahnschrift' }) { $splashHeadName = 'Bahnschrift' } } catch {}
$sfWord  = New-Object Drawing.Font($splashHeadName, 58, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$sfMono  = New-Object Drawing.Font('Consolas', 13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$sfMonoS = New-Object Drawing.Font('Consolas', 11, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$sfPct   = New-Object Drawing.Font('Consolas', 13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$tmpB = New-Object Drawing.Bitmap(1, 1); $tmpG = [Drawing.Graphics]::FromImage($tmpB)
$sInfoA = Fz-Spaced $tmpG 'FRENZY' $sfWord 6
$sInfoB = Fz-Spaced $tmpG 'TWEAKS' $sfWord 6
$sInfoBy = Fz-Spaced $tmpG '// BY FRENZY' $sfMono 5
$sInfoOn = Fz-Spaced $tmpG '// SYSTEM ONLINE' $sfMono 4
$sInfoFt = Fz-Spaced $tmpG ("V $($script:AppVersion)  .  WINDOWS  .  SYSTEM START") $sfMonoS 3
$tmpG.Dispose(); $tmpB.Dispose()

$sTitleH = 150
$sTitleBmp = New-Object Drawing.Bitmap($script:SplashW, $sTitleH, [Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$stg = [Drawing.Graphics]::FromImage($sTitleBmp); $stg.TextRenderingHint = 'AntiAliasGridFit'; $stg.SmoothingMode = 'AntiAlias'
$sGlowB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(11, 255, 96, 0))
$sMainB = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(255, 226, 92))
foreach ($dy in -5, -3, 0, 3, 5) { foreach ($dx in -5, -3, 0, 3, 5) {
        Fz-DrawSpaced $stg $sInfoA $sfWord $sGlowB ([single](($script:SplashW - $sInfoA.Width) / 2 + $dx)) ([single](6 + $dy))
        Fz-DrawSpaced $stg $sInfoB $sfWord $sGlowB ([single](($script:SplashW - $sInfoB.Width) / 2 + $dx)) ([single](70 + $dy)) } }
Fz-DrawSpaced $stg $sInfoA $sfWord $sMainB ([single](($script:SplashW - $sInfoA.Width) / 2)) 6
Fz-DrawSpaced $stg $sInfoB $sfWord $sMainB ([single](($script:SplashW - $sInfoB.Width) / 2)) 70
$stg.Dispose(); $sGlowB.Dispose(); $sMainB.Dispose()

$script:SplashForm = New-Object Windows.Forms.Form
$sf = $script:SplashForm
$sf.FormBorderStyle = 'None'; $sf.StartPosition = 'CenterScreen'
$sf.ClientSize = New-Object Drawing.Size($script:SplashW, $script:SplashH)
$sf.BackColor = [Drawing.Color]::FromArgb(7, 9, 16); $sf.ShowInTaskbar = $true; $sf.TopMost = $true; $sf.Text = 'FRENZY TWEAKS'
$sf.KeyPreview = $true
$sf.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($sf, $true, $null)
try {
    $rg = Fz-GetRoundPath 0 0 $script:SplashW $script:SplashH 16
    $sf.Region = New-Object Drawing.Region($rg)
    $ib = New-Object Drawing.Bitmap(64, 64); $ig = [Drawing.Graphics]::FromImage($ib); $ig.SmoothingMode = 'AntiAlias'
    Fz-DrawLogo $ig 2 2 60; $sf.Icon = [Drawing.Icon]::FromHandle($ib.GetHicon()); $ig.Dispose()
} catch {}
$sf.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape' -and -not $script:Splash['Launch']) { $s.Close() } })

$sf.Add_Paint({
        param($s, $e)
        $g = $e.Graphics; $sp = $script:Splash; $SW = $script:SplashW; $SH = $script:SplashH
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $t = $sp['Clock'].Elapsed.TotalSeconds; $cx = $SW / 2; $cy = 122
        $ember = [Drawing.Color]::FromArgb(255, 106, 0)
        $gp = New-Object Drawing.Pen([Drawing.Color]::FromArgb(16, 255, 120, 30), 1)
        for ($x = 0; $x -lt $SW; $x += 38) { $g.DrawLine($gp, $x, 0, $x, $SH) }
        for ($y = 0; $y -lt $SH; $y += 38) { $g.DrawLine($gp, 0, $y, $SW, $y) }
        $gp.Dispose()
        foreach ($p in $sp['Parts']) {
            $a = [int](255 * $p.A * [math]::Max(0, [math]::Min(1, $p.Y / $SH)) * 0.8)
            if ($a -le 4) { continue }
            $br = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb($a, 255, [int](90 + 90 * $p.A), 20))
            $g.FillEllipse($br, [single]$p.X, [single]$p.Y, [single]$p.S, [single]$p.S); $br.Dispose()
        }
        $pulse = 0.5 + 0.5 * [math]::Sin($t * 2.2)
        $gpth = New-Object Drawing.Drawing2D.GraphicsPath; $gpth.AddEllipse([single]($cx - 300), [single]($cy - 150), [single]600, [single]420)
        $pg = New-Object Drawing.Drawing2D.PathGradientBrush($gpth)
        $pg.CenterColor = [Drawing.Color]::FromArgb([int](46 + 36 * $pulse), 255, 90, 0)
        $pg.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 255, 90, 0))
        $g.FillPath($pg, $gpth); $pg.Dispose(); $gpth.Dispose()
        $bp = New-Object Drawing.Pen($ember, 2.6); $m = 22; $L = 46
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF($m, ($m + $L))), (New-Object Drawing.PointF($m, $m)), (New-Object Drawing.PointF(($m + $L), $m))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF(($SW - $m - $L), $m)), (New-Object Drawing.PointF(($SW - $m), $m)), (New-Object Drawing.PointF(($SW - $m), ($m + 16)))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF($m, ($SH - $m - 16))), (New-Object Drawing.PointF($m, ($SH - $m))), (New-Object Drawing.PointF(($m + $L), ($SH - $m)))))
        $g.DrawLines($bp, [Drawing.PointF[]]@((New-Object Drawing.PointF(($SW - $m), ($SH - $m - $L))), (New-Object Drawing.PointF(($SW - $m), ($SH - $m))), (New-Object Drawing.PointF(($SW - $m - $L), ($SH - $m)))))
        $bp.Dispose()
        $eb = New-Object Drawing.SolidBrush($ember)
        Fz-DrawSpaced $g $sInfoBy $sfMono $eb ([single]($cx - $sInfoBy.Width / 2)) 30
        $ang = ($t * 230) % 360
        $pen0 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(40, 255, 120, 20), 2)
        $g.DrawEllipse($pen0, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128); $pen0.Dispose()
        $pen1 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(255, 255, 122, 20), 3.5); $pen1.StartCap = 'Round'; $pen1.EndCap = 'Round'
        $g.DrawArc($pen1, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128, [single]$ang, [single]110); $pen1.Dispose()
        $pen2 = New-Object Drawing.Pen([Drawing.Color]::FromArgb(130, 255, 190, 70), 2.5); $pen2.StartCap = 'Round'; $pen2.EndCap = 'Round'
        $g.DrawArc($pen2, [single]($cx - 64), [single]($cy - 64), [single]128, [single]128, [single](($ang + 180) % 360), [single]55); $pen2.Dispose()
        Fz-DrawLogo $g ([single]($cx - 44)) ([single]($cy - 44)) ([single]88)
        Fz-DrawSpaced $g $sInfoOn $sfMono $eb ([single]($cx - $sInfoOn.Width / 2)) 204
        $g.DrawImageUnscaled($sTitleBmp, 0, 222)
        $bx = 120; $bwid = $SW - 240; $by = 402
        if ($sp['Fail']) { $col = [Drawing.Color]::FromArgb(255, 84, 72); $msg = $sp['Fail'] }
        else { $col = [Drawing.Color]::FromArgb(246, 243, 240); $msg = if ($sp['Status']) { $sp['Status'] } else { 'loading FRENZY TWEAKS' }; $msg += ('.' * ([int]([math]::Floor($t * 2.5) % 4))) }
        $dimb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(170, 150, 138))
        $g.DrawString('INITIALIZING', $sfPct, $dimb, [single]$bx, [single]($by - 26))
        $ldg = if ($sp['Fail']) { 'ERROR' } else { 'LOADING' }; $lsz = $g.MeasureString($ldg, $sfPct)
        $g.FillEllipse($eb, [single]($bx + $bwid - $lsz.Width - 14), [single]($by - 21), [single]7, [single]7)
        $g.DrawString($ldg, $sfPct, $eb, [single]($bx + $bwid - $lsz.Width), [single]($by - 26))
        $track = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(36, 31, 28))
        $tp = Fz-GetRoundPath $bx $by $bwid 5 2.5; $g.FillPath($track, $tp); $tp.Dispose(); $track.Dispose()
        $fw = [single]($bwid * [math]::Min(1, $sp['P']))
        if ($fw -gt 5) {
            $fr = New-Object Drawing.RectangleF([single]$bx, [single]$by, $fw, [single]5)
            $fb = New-Object Drawing.Drawing2D.LinearGradientBrush($fr, [Drawing.Color]::FromArgb(255, 255, 60, 0), [Drawing.Color]::FromArgb(255, 255, 184, 52), 0.0)
            $fp = Fz-GetRoundPath $bx $by $fw 5 2.5; $g.FillPath($fb, $fp); $fp.Dispose(); $fb.Dispose()
            $hb = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(90, 255, 160, 40))
            $g.FillEllipse($hb, [single]($bx + $fw - 9), [single]($by - 6), [single]18, [single]18); $hb.Dispose()
        }
        $cb = New-Object Drawing.SolidBrush($col)
        $g.DrawString('$ ' + $msg, $sfMono, $cb, [single]$bx, [single]($by + 16)); $cb.Dispose()
        $ptxt = ('{0}%' -f [int]([math]::Floor($sp['P'] * 100))); $psz = $g.MeasureString($ptxt, $sfPct)
        $g.DrawString($ptxt, $sfPct, $eb, [single]($bx + $bwid - $psz.Width), [single]($by + 16))
        Fz-DrawSpaced $g $sInfoFt $sfMonoS $dimb ([single]($cx - $sInfoFt.Width / 2)) ($SH - 44)
        $dimb.Dispose(); $eb.Dispose()
        $bp2 = Fz-GetRoundPath 0.5 0.5 ($SW - 1) ($SH - 1) 16
        $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(150, 255, 106, 0), 1.5); $g.DrawPath($pen, $bp2); $pen.Dispose(); $bp2.Dispose()
    })

$script:SplashTimer = New-Object Windows.Forms.Timer; $script:SplashTimer.Interval = 20
$script:SplashTimer.Add_Tick({
        try {
            $sp = $script:Splash; $t = $sp['Clock'].Elapsed.TotalSeconds; $dt = [math]::Min(0.1, $t - [double]$sp['Last']); $sp['Last'] = [double]$t
            foreach ($p in $sp['Parts']) {
                $p.Y -= $p.V * $dt; $p.X += [math]::Sin($t * 1.3 + $p.Ph) * 14 * $dt
                if ($p.Y -lt -6) { $p.Y = $script:SplashH + 6; $p.X = (Get-Random -Minimum 0 -Maximum $script:SplashW) }
            }
            if ($sp['Fail']) { if (($t - $sp['FailAt']) -gt 3.5) { $script:SplashTimer.Stop(); $script:SplashForm.Close() } }
            else {
                $target = if ($sp['Closing']) { 1.0 } elseif ($sp['Launch']) { 1.0 } else { [math]::Min(0.95, ($t / 6.0) * 0.95) }
                $sp['P'] += ($target - $sp['P']) * 0.16
            }
            if ($sp['Fade']) {
                $script:SplashForm.Opacity = [math]::Max(0, $script:SplashForm.Opacity - 0.09)
                if ($script:SplashForm.Opacity -le 0.02) { $script:SplashTimer.Stop(); $script:SplashForm.Close() }
            }
            $script:SplashForm.Invalidate()
        } catch {
            $script:Splash['TickErrors']++
            if ($script:Splash['TickErrors'] -ge 3) { try { $script:SplashTimer.Stop(); $script:SplashForm.Close() } catch {} }
        }
    })
$script:SplashFront = New-Object Windows.Forms.Timer; $script:SplashFront.Interval = 150
$script:SplashFront.Add_Tick({
        $script:Splash['FrontTicks']++
        try { [FzSplashWin]::Front($script:SplashForm.Handle); $script:SplashForm.Activate() } catch {}
        if ($script:Splash['FrontTicks'] -ge 14) { $script:SplashFront.Stop() }
    })

$script:SplashForm.Show()
[FzSplashWin]::Front($script:SplashForm.Handle); $script:SplashForm.Activate(); $script:SplashForm.BringToFront()
$script:SplashTimer.Start(); $script:SplashFront.Start()
[System.Windows.Forms.Application]::DoEvents()

# ======================================================================
#  UI ENGINE (C# custom-drawn controls)
# ======================================================================
$script:FzSource = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Fz
{
    public static class Theme
    {
        public static string Head = "Segoe UI";
        public static string Mono = "Consolas";
        public static Color Bg = Color.FromArgb(8, 11, 21);
        public static Color Side = Color.FromArgb(11, 15, 28);
        public static Color Card = Color.FromArgb(18, 25, 43);
        public static Color Card2 = Color.FromArgb(29, 39, 64);
        public static Color Border = Color.FromArgb(40, 53, 84);
        public static Color Text = Color.FromArgb(240, 244, 255);
        public static Color Dim = Color.FromArgb(138, 152, 184);
        public static Color Accent = Color.FromArgb(255, 106, 0);
        public static Color Good = Color.FromArgb(74, 222, 128);
        public static Color Warn = Color.FromArgb(255, 200, 70);
        public static Color Bad = Color.FromArgb(255, 82, 82);
        static Dictionary<string, Font> cache = new Dictionary<string, Font>();
        public static Font F(float px, bool bold)
        {
            string k = "H" + px + bold;
            Font f;
            if (!cache.TryGetValue(k, out f)) { f = new Font(Head, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); cache[k] = f; }
            return f;
        }
        public static Font M(float px, bool bold)
        {
            string k = "M" + px + bold;
            Font f;
            if (!cache.TryGetValue(k, out f)) { f = new Font(Mono, px, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel); cache[k] = f; }
            return f;
        }
    }

    public static class Gfx
    {
        public static GraphicsPath Round(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = rad * 2f;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d < 1f) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        public static Color A(Color c, int a) { return Color.FromArgb(Math.Max(0, Math.Min(255, a)), c); }
        public static Color Mix(Color a, Color b, float t)
        {
            if (t < 0f) t = 0f; if (t > 1f) t = 1f;
            return Color.FromArgb(255, (int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
        public static Color BgOf(Control c)
        {
            Control p = c.Parent;
            while (p != null) { if (p.BackColor.A == 255) return p.BackColor; p = p.Parent; }
            return Theme.Bg;
        }
        public static void Quality(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = PixelOffsetMode.Half;
        }
        public static StringFormat Fmt(StringAlignment h, StringAlignment v)
        {
            StringFormat f = new StringFormat(StringFormat.GenericTypographic);
            f.Alignment = h; f.LineAlignment = v;
            f.Trimming = StringTrimming.EllipsisCharacter;
            f.FormatFlags = StringFormatFlags.NoWrap;
            return f;
        }
        public static bool IsLight(Color c) { return (c.R * 299 + c.G * 587 + c.B * 114) / 1000 > 150; }
    }

    public static class Icons
    {
        static PointF P(float x, float y, float s, float ox, float oy) { return new PointF(ox + x * s, oy + y * s); }
        public static void Draw(Graphics g, string kind, RectangleF r, Color c, float w)
        {
            float s = Math.Min(r.Width, r.Height), ox = r.X, oy = r.Y;
            using (Pen p = new Pen(c, w))
            using (SolidBrush b = new SolidBrush(c))
            {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                switch (kind)
                {
                    case "home":
                        g.DrawLines(p, new PointF[] { P(.08f, .52f, s, ox, oy), P(.5f, .12f, s, ox, oy), P(.92f, .52f, s, ox, oy) });
                        g.DrawLines(p, new PointF[] { P(.2f, .44f, s, ox, oy), P(.2f, .9f, s, ox, oy), P(.8f, .9f, s, ox, oy), P(.8f, .44f, s, ox, oy) });
                        break;
                    case "sliders":
                        for (int i = 0; i < 3; i++)
                        {
                            float y = .2f + i * .3f, kx = (i == 0 ? .66f : i == 1 ? .32f : .55f);
                            g.DrawLine(p, P(.08f, y, s, ox, oy), P(.92f, y, s, ox, oy));
                            g.FillEllipse(b, ox + (kx - .11f) * s, oy + (y - .11f) * s, .22f * s, .22f * s);
                        }
                        break;
                    case "trash":
                        g.DrawLine(p, P(.12f, .24f, s, ox, oy), P(.88f, .24f, s, ox, oy));
                        g.DrawLines(p, new PointF[] { P(.34f, .24f, s, ox, oy), P(.38f, .08f, s, ox, oy), P(.62f, .08f, s, ox, oy), P(.66f, .24f, s, ox, oy) });
                        g.DrawLines(p, new PointF[] { P(.2f, .24f, s, ox, oy), P(.26f, .92f, s, ox, oy), P(.74f, .92f, s, ox, oy), P(.8f, .24f, s, ox, oy) });
                        break;
                    case "bolt":
                        g.DrawLines(p, new PointF[] { P(.58f, .06f, s, ox, oy), P(.22f, .55f, s, ox, oy), P(.5f, .55f, s, ox, oy), P(.4f, .94f, s, ox, oy), P(.78f, .4f,
