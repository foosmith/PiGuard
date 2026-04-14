using System.Windows;
using System.Windows.Controls;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;
using PiGuard.Core.Services;

namespace PiGuard.Windows.Views;

public partial class PreferencesWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private readonly ICredentialStore _credentialStore;
    private readonly IStartupService _startupService;

    private AppPreferences _preferences = new();
    private readonly List<ConnectionEditorItem> _connections = [];
    private readonly HashSet<string> _removedCredentialIds = new(StringComparer.Ordinal);
    private ConnectionEditorItem? _editingConnection;

    public PreferencesWindow(ISettingsStore settingsStore, ICredentialStore credentialStore, IStartupService startupService)
    {
        _settingsStore = settingsStore;
        _credentialStore = credentialStore;
        _startupService = startupService;
        InitializeComponent();
        Loaded += PreferencesWindow_Loaded;
    }

    private async void PreferencesWindow_Loaded(object sender, RoutedEventArgs e)
    {
        Loaded -= PreferencesWindow_Loaded;
        try
        {
            await LoadAsync();
        }
        catch
        {
            StatusTextBlock.Text = "Failed to load preferences. Your settings file may be corrupt.";
            SaveChangesButton.IsEnabled = false;
        }
    }

    private async Task LoadAsync()
    {
        _preferences = await _settingsStore.LoadAsync();
        _connections.Clear();
        _removedCredentialIds.Clear();
        _editingConnection = null;

        foreach (var connection in _preferences.Connections)
        {
            var storedSecret = await _credentialStore.ReadSecretAsync(connection.Id);
            _connections.Add(ConnectionEditorItem.FromConfig(connection, storedSecret));
        }

        ConnectionsListView.ItemsSource = null;
        ConnectionsListView.ItemsSource = _connections;

        LaunchAtStartupCheckBox.IsChecked = await _startupService.IsEnabledAsync();
        ShortcutEnabledCheckBox.IsChecked = _preferences.ShortcutEnabled;
        EnableLoggingCheckBox.IsChecked = _preferences.EnableLogging;
        EnableFloatingStatsPillCheckBox.IsChecked = _preferences.EnableFloatingStatsPill;
        EnableTrayMiniPanelCheckBox.IsChecked = _preferences.EnableTrayMiniPanel;
        EnableRichTrayTooltipCheckBox.IsChecked = _preferences.EnableRichTrayTooltip;
        PollingRateTextBox.Text = _preferences.PollingRateSeconds.ToString();

        if (_connections.Count > 0)
        {
            ConnectionsListView.SelectedIndex = 0;
        }
        else
        {
            PopulateEditor(new ConnectionEditorItem());
        }

        StatusTextBlock.Text = "Preferences loaded.";
    }

    private void ConnectionsListView_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ConnectionsListView.SelectedItem is ConnectionEditorItem connection)
        {
            _editingConnection = connection;
            PopulateEditor(connection);
        }
    }

    private void NewConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        var item = new ConnectionEditorItem();
        _connections.Add(item);
        _editingConnection = item;
        RefreshConnections();
        ConnectionsListView.SelectedItem = item;
        PopulateEditor(item);
        StatusTextBlock.Text = "New connection draft created.";
    }

    private void DeleteConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        if (ConnectionsListView.SelectedItem is not ConnectionEditorItem connection)
        {
            StatusTextBlock.Text = "Select a connection to delete.";
            return;
        }

        _connections.Remove(connection);
        _removedCredentialIds.Add(connection.Id);
        RefreshConnections();
        ConnectionsListView.SelectedItem = _connections.FirstOrDefault();
        if (_connections.Count == 0)
        {
            PopulateEditor(new ConnectionEditorItem());
        }

        StatusTextBlock.Text = "Connection removed. Save changes to persist.";
    }

    private async void SaveChangesButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            await SaveChangesAsync();
        }
        catch
        {
            StatusTextBlock.Text = "Save failed. Check your connection settings and try again.";
        }
    }

    private async Task SaveChangesAsync()
    {
        var selected = ConnectionsListView.SelectedItem as ConnectionEditorItem ?? _editingConnection;
        if (selected is null && _connections.Count > 0)
        {
            selected = _connections[0];
        }

        if (selected is not null && !TryApplyEditorToConnection(selected, out var validationMessage))
        {
            StatusTextBlock.Text = validationMessage;
            return;
        }

        var normalizedConnections = new List<ConnectionConfig>(_connections.Count);
        foreach (var connection in _connections)
        {
            if (string.IsNullOrWhiteSpace(connection.Hostname))
            {
                continue;
            }

            normalizedConnections.Add(connection.ToConfig());
        }

        if (!int.TryParse(PollingRateTextBox.Text, out var pollingRate) || pollingRate < 3)
        {
            StatusTextBlock.Text = "Polling rate must be 3 seconds or more.";
            return;
        }

        _preferences = _preferences with
        {
            Connections = normalizedConnections,
            ShortcutEnabled = ShortcutEnabledCheckBox.IsChecked == true,
            EnableLogging = EnableLoggingCheckBox.IsChecked == true,
            EnableFloatingStatsPill = EnableFloatingStatsPillCheckBox.IsChecked == true,
            EnableTrayMiniPanel = EnableTrayMiniPanelCheckBox.IsChecked == true,
            EnableRichTrayTooltip = EnableRichTrayTooltipCheckBox.IsChecked == true,
            LaunchAtStartup = LaunchAtStartupCheckBox.IsChecked == true,
            PollingRateSeconds = pollingRate,
        };

        await _settingsStore.SaveAsync(_preferences);
        await _startupService.SetEnabledAsync(LaunchAtStartupCheckBox.IsChecked == true);

        var activeIds = normalizedConnections.Select(connection => connection.Id).ToHashSet(StringComparer.Ordinal);
        foreach (var removedId in _removedCredentialIds)
        {
            await _credentialStore.DeleteSecretAsync(removedId);
        }

        foreach (var connection in _connections)
        {
            if (!activeIds.Contains(connection.Id))
            {
                await _credentialStore.DeleteSecretAsync(connection.Id);
                continue;
            }

            if (connection.PasswordProtected)
            {
                if (!string.IsNullOrWhiteSpace(connection.PendingSecret))
                {
                    await _credentialStore.WriteSecretAsync(connection.Id, connection.PendingSecret);
                    connection.StoredSecret = connection.PendingSecret;
                    connection.PendingSecret = string.Empty;
                }
            }
            else
            {
                await _credentialStore.DeleteSecretAsync(connection.Id);
                connection.StoredSecret = string.Empty;
                connection.PendingSecret = string.Empty;
            }
        }

        _removedCredentialIds.Clear();
        SecretPasswordBox.Password = string.Empty;
        RefreshConnections();
        if (selected is not null)
        {
            _editingConnection = selected;
            ConnectionsListView.SelectedItem = selected;
            PopulateEditor(selected);
        }

        StatusTextBlock.Text = $"Preferences saved. {normalizedConnections.Count} connection(s) stored.";
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private async void TestConnectionButton_Click(object sender, RoutedEventArgs e)
    {
        var hostname = HostnameTextBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(hostname))
        {
            StatusTextBlock.Text = "Enter a hostname before testing.";
            return;
        }

        if (!int.TryParse(PortTextBox.Text, out var port) || port is < 1 or > 65535)
        {
            StatusTextBlock.Text = "Port must be between 1 and 65535.";
            return;
        }

        var version = VersionComboBox.SelectedIndex switch
        {
            1 => ConnectionVersion.V6,
            2 => ConnectionVersion.AdGuardHome,
            _ => ConnectionVersion.LegacyV5,
        };
        var useSsl = UseSslCheckBox.IsChecked == true;
        var passwordProtected = PasswordProtectedCheckBox.IsChecked == true;
        var adminUrl = string.IsNullOrWhiteSpace(AdminUrlTextBox.Text)
            ? (version == ConnectionVersion.AdGuardHome
                ? $"{(useSsl ? "https" : "http")}://{hostname}:{port}"
                : BuildAdminUrl(hostname, port, useSsl))
            : AdminUrlTextBox.Text.Trim();

        var pendingSecret = SecretPasswordBox.Password.Trim();
        var secret = !string.IsNullOrWhiteSpace(pendingSecret)
            ? pendingSecret
            : _editingConnection?.StoredSecret;

        var username = UsernameTextBox.Text.Trim();
        var connectionId = BuildConnectionId(hostname, port, useSsl, version);
        var config = new ConnectionConfig(connectionId, hostname, port, useSsl, version, adminUrl, passwordProtected, username);

        TestConnectionButton.IsEnabled = false;
        StatusTextBlock.Text = "Testing connection...";

        try
        {
            IDnsFilterClient client = version switch
            {
                ConnectionVersion.V6 => new PiholeClientV6(config, passwordProtected ? secret : null),
                ConnectionVersion.AdGuardHome => new AdGuardHomeClient(config, passwordProtected ? secret : null),
                _ => new PiholeClientV5(config, passwordProtected ? secret : null),
            };

            var status = await client.FetchStatusAsync();
            var statusText = status.Enabled == true ? "Enabled" : status.Enabled == false ? "Disabled" : "Unknown";
            StatusTextBlock.Text = $"Connection successful — {statusText}";
        }
        catch (Exception ex)
        {
            StatusTextBlock.Text = $"Connection failed: {ex.Message}";
        }
        finally
        {
            TestConnectionButton.IsEnabled = true;
        }
    }

    private void PopulateEditor(ConnectionEditorItem connection)
    {
        _editingConnection = connection;
        HostnameTextBox.Text = connection.Hostname;
        PortTextBox.Text = connection.Port.ToString();
        VersionComboBox.SelectedIndex = connection.Version switch
        {
            ConnectionVersion.V6 => 1,
            ConnectionVersion.AdGuardHome => 2,
            _ => 0,
        };
        UsernameTextBox.Text = connection.Username;
        var isAgh = connection.Version == ConnectionVersion.AdGuardHome;
        UsernameLabel.Visibility = isAgh ? Visibility.Visible : Visibility.Collapsed;
        UsernameTextBox.Visibility = isAgh ? Visibility.Visible : Visibility.Collapsed;
        SecretLabel.Text = isAgh ? "Password" : "Secret";
        UseSslCheckBox.IsChecked = connection.UseSsl;
        AdminUrlTextBox.Text = connection.AdminUrl;
        SecretPasswordBox.Password = string.Empty;
        PasswordProtectedCheckBox.IsChecked = connection.PasswordProtected;
    }

    private void VersionComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (UsernameLabel is null || UsernameTextBox is null || SecretLabel is null) return; // fires during InitializeComponent before named elements exist
        var isAgh = VersionComboBox.SelectedIndex == 2;
        UsernameLabel.Visibility = isAgh ? Visibility.Visible : Visibility.Collapsed;
        UsernameTextBox.Visibility = isAgh ? Visibility.Visible : Visibility.Collapsed;
        SecretLabel.Text = isAgh ? "Password" : "Secret";
    }

    private bool TryApplyEditorToConnection(ConnectionEditorItem connection, out string message)
    {
        var hostname = HostnameTextBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(hostname))
        {
            message = "Hostname is required.";
            return false;
        }

        if (!int.TryParse(PortTextBox.Text, out var port) || port is < 1 or > 65535)
        {
            message = "Port must be between 1 and 65535.";
            return false;
        }

        var version = VersionComboBox.SelectedIndex switch
        {
            1 => ConnectionVersion.V6,
            2 => ConnectionVersion.AdGuardHome,
            _ => ConnectionVersion.LegacyV5,
        };
        var useSsl = UseSslCheckBox.IsChecked == true;
        var passwordProtected = PasswordProtectedCheckBox.IsChecked == true;
        var adminUrl = string.IsNullOrWhiteSpace(AdminUrlTextBox.Text)
            ? (version == ConnectionVersion.AdGuardHome
                ? $"{(useSsl ? "https" : "http")}://{hostname}:{port}"
                : BuildAdminUrl(hostname, port, useSsl))
            : AdminUrlTextBox.Text.Trim();
        var pendingSecret = SecretPasswordBox.Password.Trim();

        var previousId = connection.Id;
        connection.Hostname = hostname;
        connection.Port = port;
        connection.Version = version;
        connection.UseSsl = useSsl;
        connection.AdminUrl = adminUrl;
        connection.PasswordProtected = passwordProtected;
        connection.Username = UsernameTextBox.Text.Trim();
        connection.Id = BuildConnectionId(hostname, port, useSsl, version);

        if (!string.IsNullOrWhiteSpace(pendingSecret))
        {
            connection.PendingSecret = pendingSecret;
        }

        if (!string.Equals(previousId, connection.Id, StringComparison.Ordinal))
        {
            _removedCredentialIds.Add(previousId);
            if (!string.IsNullOrWhiteSpace(connection.StoredSecret) && string.IsNullOrWhiteSpace(connection.PendingSecret))
            {
                connection.PendingSecret = connection.StoredSecret;
            }
        }

        RefreshConnections();
        message = string.Empty;
        return true;
    }

    private void RefreshConnections()
    {
        ConnectionsListView.Items.Refresh();
    }

    private static string BuildAdminUrl(string hostname, int port, bool useSsl)
    {
        var scheme = useSsl ? "https" : "http";
        return $"{scheme}://{hostname}:{port}/admin/";
    }

    private static string BuildConnectionId(string hostname, int port, bool useSsl, ConnectionVersion version)
    {
        var scheme = useSsl ? "https" : "http";
        var versionToken = version switch
        {
            ConnectionVersion.V6 => "v6",
            ConnectionVersion.AdGuardHome => "agh",
            _ => "v5",
        };
        return $"{scheme}://{hostname}:{port}::{versionToken}";
    }

    private sealed class ConnectionEditorItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString("N");

        public string Hostname { get; set; } = string.Empty;

        public int Port { get; set; } = 80;

        public bool UseSsl { get; set; }

        public ConnectionVersion Version { get; set; } = ConnectionVersion.V6;

        public string AdminUrl { get; set; } = string.Empty;

        public bool PasswordProtected { get; set; } = true;

        public string StoredSecret { get; set; } = string.Empty;

        public string PendingSecret { get; set; } = string.Empty;

        public string Username { get; set; } = string.Empty;

        public string DisplayName => string.IsNullOrWhiteSpace(Hostname) ? "(new connection)" : $"{Hostname}:{Port}";

        public string VersionLabel => Version switch
        {
            ConnectionVersion.V6 => "v6",
            ConnectionVersion.AdGuardHome => "AGH",
            _ => "v5",
        };

        public string AuthenticationLabel => Version == ConnectionVersion.AdGuardHome
            ? PasswordProtected
                ? (string.IsNullOrWhiteSpace(StoredSecret) && string.IsNullOrWhiteSpace(PendingSecret) ? "Missing credentials" : "Stored credentials")
                : "No secret"
            : PasswordProtected
                ? (string.IsNullOrWhiteSpace(StoredSecret) && string.IsNullOrWhiteSpace(PendingSecret) ? "Missing secret" : "Stored secret")
                : "No secret";

        public ConnectionConfig ToConfig()
        {
            var scheme = UseSsl ? "https" : "http";
            var defaultAdminUrl = Version == ConnectionVersion.AdGuardHome
                ? $"{scheme}://{Hostname}:{Port}"
                : BuildAdminUrl(Hostname, Port, UseSsl);

            return new(
                Id,
                Hostname,
                Port,
                UseSsl,
                Version,
                string.IsNullOrWhiteSpace(AdminUrl) ? defaultAdminUrl : AdminUrl,
                PasswordProtected,
                Username);
        }

        public static ConnectionEditorItem FromConfig(ConnectionConfig config, string? storedSecret) =>
            new()
            {
                Id = config.Id,
                Hostname = config.Hostname,
                Port = config.Port,
                UseSsl = config.UseSsl,
                Version = config.Version,
                AdminUrl = config.AdminUrl,
                PasswordProtected = config.PasswordProtected,
                StoredSecret = storedSecret ?? string.Empty,
                Username = config.Username,
            };
    }
}
