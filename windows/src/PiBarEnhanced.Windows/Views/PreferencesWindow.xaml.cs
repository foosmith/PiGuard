using System.Windows;
using PiBarEnhanced.Core.Abstractions;

namespace PiBarEnhanced.Windows.Views;

public partial class PreferencesWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IStartupService _startupService;

    public PreferencesWindow(ISettingsStore settingsStore, ICredentialStore credentialStore, IStartupService startupService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
        InitializeComponent();
    }
}
