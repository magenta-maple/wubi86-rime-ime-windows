using System.Windows;
using System.Windows.Media;
using Meifeng.Core.Config;
using Microsoft.Win32;

namespace MeifengWubi.Ui;

// 皮肤数值到 WPF 颜色、字体的转换，以及系统亮暗判断
internal static class SkinMedia
{
    public const string DefaultFontFamily = "Microsoft YaHei UI";

    // 常用中文字体友好显示名；其余用家族 Source 名
    private static readonly Dictionary<string, string> FriendlyFontTitles = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Microsoft YaHei UI"] = "微软雅黑",
        ["Microsoft YaHei"] = "微软雅黑",
        ["DengXian"] = "等线",
        ["SimHei"] = "黑体",
        ["SimSun"] = "宋体",
        ["NSimSun"] = "新宋体",
        ["KaiTi"] = "楷体",
        ["FangSong"] = "仿宋",
        ["Microsoft JhengHei UI"] = "微软正黑体",
        ["Microsoft JhengHei"] = "微软正黑体",
        ["PingFang SC"] = "苹方",
        ["Source Han Sans SC"] = "思源黑体",
        ["Source Han Serif SC"] = "思源宋体",
        ["Noto Sans CJK SC"] = "Noto 黑体",
        ["Noto Serif CJK SC"] = "Noto 宋体",
    };

    private static readonly object FontChoicesGate = new();
    private static (string Name, string Title)[]? _fontChoices;

    // 设置页「候选字体」：系统默认 + 本机全部中文可用字体
    public static (string Name, string Title)[] PreferredFonts
    {
        get
        {
            lock (FontChoicesGate)
            {
                return _fontChoices ??= BuildCandidateFontChoices();
            }
        }
    }

    public static Color ToColor(this RGBAColor c)
    {
        static byte B(double v) => (byte)Math.Round(Math.Clamp(v, 0, 1) * 255);
        return Color.FromArgb(B(c.Alpha), B(c.Red), B(c.Green), B(c.Blue));
    }

    public static RGBAColor ToRgba(this Color c) => new(c.R / 255.0, c.G / 255.0, c.B / 255.0, c.A / 255.0);

    public static SolidColorBrush ToBrush(this RGBAColor c)
    {
        var brush = new SolidColorBrush(c.ToColor());
        brush.Freeze();
        return brush;
    }

    // 皮肤字体名转成带回退的 FontFamily；macOS 皮肤里的苹方在 Windows 上回退到微软雅黑
    public static FontFamily FontFamilyFor(string fontName) =>
        new(string.IsNullOrWhiteSpace(fontName) ? DefaultFontFamily : $"{fontName}, {DefaultFontFamily}");

    public static Typeface TypefaceFor(string fontName, SkinFontWeight weight) =>
        new(FontFamilyFor(fontName), FontStyles.Normal, FontWeight.FromOpenTypeWeight(weight.OpenTypeWeight()), FontStretches.Normal);

    // 字体实际提供的字重；查不到时列出全部档位
    public static List<SkinFontWeight> AvailableWeights(string fontName)
    {
        var all = Enum.GetValues<SkinFontWeight>().ToList();
        try
        {
            var family = new FontFamily(string.IsNullOrWhiteSpace(fontName) ? DefaultFontFamily : fontName);
            var weights = family.FamilyTypefaces.Select(t => t.Weight.ToOpenTypeWeight()).Distinct().ToList();
            if (weights.Count == 0) return all;
            var result = all.Where(w => weights.Contains(w.OpenTypeWeight())).ToList();
            return result.Count == 0 ? all : result;
        }
        catch
        {
            return all;
        }
    }

    private static (string Name, string Title)[] BuildCandidateFontChoices()
    {
        var items = new List<(string Name, string Title)> { ("", "系统默认") };
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "" };

        IEnumerable<FontFamily> families;
        try
        {
            families = Fonts.SystemFontFamilies;
        }
        catch
        {
            return items.ToArray();
        }

        foreach (var family in families.OrderBy(f => DisplayTitle(FamilyKey(f)), StringComparer.CurrentCultureIgnoreCase))
        {
            var name = FamilyKey(family);
            if (string.IsNullOrWhiteSpace(name) || !seen.Add(name)) continue;
            if (!IsChineseCapable(family)) continue;
            items.Add((name, DisplayTitle(name)));
        }

        return items.ToArray();
    }

    private static string FamilyKey(FontFamily family)
    {
        try
        {
            // Source 是 new FontFamily(name) 期望的名字；找不到时退回英文家族名
            if (!string.IsNullOrWhiteSpace(family.Source)) return family.Source;
            var en = family.FamilyNames
                .FirstOrDefault(kv => kv.Key.IetfLanguageTag.StartsWith("en", StringComparison.OrdinalIgnoreCase))
                .Value;
            if (!string.IsNullOrWhiteSpace(en)) return en;
            return family.FamilyNames.Values.FirstOrDefault() ?? "";
        }
        catch
        {
            return family.Source ?? "";
        }
    }

    private static string DisplayTitle(string name) =>
        FriendlyFontTitles.TryGetValue(name, out var title) ? title : name;

    // 能绘制「中」，或家族名像中文字体（覆盖语言标签缺失的用户字体）
    private static bool IsChineseCapable(FontFamily family)
    {
        try
        {
            foreach (var typeface in family.GetTypefaces())
            {
                if (!typeface.TryGetGlyphTypeface(out var glyph) || glyph is null) continue;
                if (glyph.CharacterToGlyphMap.ContainsKey('中')) return true;
            }
        }
        catch
        {
            // 个别字体元数据异常时，退回名字启发
        }

        return FamilyLooksChinese(FamilyKey(family));
    }

    private static bool FamilyLooksChinese(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        if (name.Any(ch => ch is >= '\u4E00' and <= '\u9FFF' or >= '\u3400' and <= '\u4DBF'))
            return true;

        // 简繁后缀与常见中文字体商品名；避免纯拉丁/符号字体误入
        return name.Contains("CJK", StringComparison.OrdinalIgnoreCase)
               || name.Contains("PingFang", StringComparison.OrdinalIgnoreCase)
               || name.Contains("YaHei", StringComparison.OrdinalIgnoreCase)
               || name.Contains("JhengHei", StringComparison.OrdinalIgnoreCase)
               || name.Contains("DengXian", StringComparison.OrdinalIgnoreCase)
               || name.Contains("SimSun", StringComparison.OrdinalIgnoreCase)
               || name.Contains("SimHei", StringComparison.OrdinalIgnoreCase)
               || name.Contains("KaiTi", StringComparison.OrdinalIgnoreCase)
               || name.Contains("FangSong", StringComparison.OrdinalIgnoreCase)
               || name.Contains("Source Han", StringComparison.OrdinalIgnoreCase)
               || name.Contains("Noto Sans CJK", StringComparison.OrdinalIgnoreCase)
               || name.Contains("Noto Serif CJK", StringComparison.OrdinalIgnoreCase)
               || name.Contains("WenQuanYi", StringComparison.OrdinalIgnoreCase)
               || name.EndsWith(" SC", StringComparison.OrdinalIgnoreCase)
               || name.EndsWith(" TC", StringComparison.OrdinalIgnoreCase)
               || name.EndsWith(" HC", StringComparison.OrdinalIgnoreCase)
               || name.EndsWith(" CN", StringComparison.OrdinalIgnoreCase)
               || name.EndsWith(" GB", StringComparison.OrdinalIgnoreCase);
    }

    // 系统是否为深色应用模式
    public static bool SystemIsDark
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                return key?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch
            {
                return false;
            }
        }
    }
}
