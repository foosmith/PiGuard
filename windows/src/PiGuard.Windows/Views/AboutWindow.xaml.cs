using System.Diagnostics;
using System.Reflection;
using System.Windows;

namespace PiGuard.Windows.Views;

public partial class AboutWindow : Window
{
    public AboutWindow()
    {
        InitializeComponent();
        VersionTextBlock.Text = BuildVersionText();
    }

    private void GitHubButton_Click(object sender, RoutedEventArgs e)
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = "https://github.com/foosmith/PiGuard",
            UseShellExecute = true,
        });
    }

    private static string BuildVersionText()
    {
        var assembly = Assembly.GetEntryAssembly() ?? typeof(AboutWindow).Assembly;
        var informationalVersion = assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        if (!string.IsNullOrWhiteSpace(informationalVersion))
        {
            return $"Version {informationalVersion}";
        }

        var version = assembly.GetName().Version;
        return version is null ? "Version unknown" : $"Version {version}";
    }
}
