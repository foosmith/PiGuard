using System.Windows;

namespace PiGuard.Windows.Services;

public static class ThemeManager
{
    public static void Apply(bool darkMode)
    {
        var mergedDicts = System.Windows.Application.Current.Resources.MergedDictionaries;

        var existing = mergedDicts
            .Where(d => d.Source?.OriginalString.Contains("/Themes/") == true)
            .ToList();
        foreach (var d in existing)
            mergedDicts.Remove(d);

        var uri = darkMode
            ? new Uri("/PiGuard.Windows;component/Resources/Themes/Dark.xaml", UriKind.Relative)
            : new Uri("/PiGuard.Windows;component/Resources/Themes/Light.xaml", UriKind.Relative);

        mergedDicts.Add(new ResourceDictionary { Source = uri });
    }
}
