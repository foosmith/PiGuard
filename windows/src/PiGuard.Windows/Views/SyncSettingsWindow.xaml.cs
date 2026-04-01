using System.Windows;
using System.Windows.Controls;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Windows.Views;

public partial class SyncSettingsWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private AppPreferences _preferences = new();
    private List<ConnectionOption> _v6Connections = [];

    public SyncSettingsWindow(ISettingsStore settingsStore)
    {
        _settingsStore = settingsStore;
        InitializeComponent();
        Loaded += SyncSettingsWindow_Loaded;
    }

    private async void SyncSettingsWindow_Loaded(object sender, RoutedEventArgs e)
    {
        Loaded -= SyncSettingsWindow_Loaded;
        await LoadAsync();
    }

    private async Task LoadAsync()
    {
        _preferences = await _settingsStore.LoadAsync();
        _v6Connections = _preferences.Connections
            .Where(connection => connection.Version == ConnectionVersion.V6)
            .Select(connection => new ConnectionOption(connection.Id, BuildDisplayName(connection)))
            .OrderBy(connection => connection.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();

        PrimaryComboBox.ItemsSource = _v6Connections;
        SecondaryComboBox.ItemsSource = _v6Connections.ToList();

        SyncEnabledCheckBox.IsChecked = _preferences.Sync.Enabled;
        SyncGroupsCheckBox.IsChecked = !_preferences.Sync.SkipGroups;
        SyncAdlistsCheckBox.IsChecked = !_preferences.Sync.SkipAdlists;
        SyncDomainsCheckBox.IsChecked = !_preferences.Sync.SkipDomains;
        DryRunCheckBox.IsChecked = _preferences.Sync.DryRunEnabled;
        WipeSecondaryCheckBox.IsChecked = _preferences.Sync.WipeSecondaryBeforeSync;

        SelectConnection(PrimaryComboBox, _preferences.Sync.PrimaryConnectionId);
        SelectConnection(SecondaryComboBox, _preferences.Sync.SecondaryConnectionId);
        SelectInterval(_preferences.Sync.IntervalMinutes);

        UpdateStatusPanel();
        StatusTextBlock.Text = "Sync settings loaded.";
    }

    private async void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryBuildSyncPreferences(out var syncPreferences, out var validationMessage))
        {
            StatusTextBlock.Text = validationMessage;
            return;
        }

        _preferences = _preferences with { Sync = syncPreferences };
        await _settingsStore.SaveAsync(_preferences);
        UpdateStatusPanel();
        StatusTextBlock.Text = "Sync settings saved.";
    }

    private async void SyncNowButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryBuildSyncPreferences(out var syncPreferences, out var validationMessage))
        {
            StatusTextBlock.Text = validationMessage;
            return;
        }

        _preferences = _preferences with
        {
            Sync = syncPreferences,
            LaunchAtStartup = _preferences.LaunchAtStartup,
        };

        await _settingsStore.SaveAsync(_preferences);
        UpdateStatusPanel("Sync requested. Execution wiring is the next implementation step.");
        StatusTextBlock.Text = "Sync request recorded in settings. Live sync execution is not wired yet.";
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private bool TryBuildSyncPreferences(out SyncPreferences syncPreferences, out string message)
    {
        var primaryId = PrimaryComboBox.SelectedValue as string ?? string.Empty;
        var secondaryId = SecondaryComboBox.SelectedValue as string ?? string.Empty;
        var enabled = SyncEnabledCheckBox.IsChecked == true;

        if (enabled)
        {
            if (_v6Connections.Count < 2)
            {
                syncPreferences = _preferences.Sync;
                message = "At least two Pi-hole v6 connections are required for sync.";
                return false;
            }

            if (string.IsNullOrWhiteSpace(primaryId) || string.IsNullOrWhiteSpace(secondaryId))
            {
                syncPreferences = _preferences.Sync;
                message = "Choose both a primary and a secondary Pi-hole.";
                return false;
            }

            if (string.Equals(primaryId, secondaryId, StringComparison.Ordinal))
            {
                syncPreferences = _preferences.Sync;
                message = "Primary and secondary must be different Pi-holes.";
                return false;
            }
        }

        if (IntervalComboBox.SelectedItem is not ComboBoxItem intervalItem ||
            !int.TryParse(intervalItem.Content?.ToString(), out var intervalMinutes))
        {
            syncPreferences = _preferences.Sync;
            message = "Choose a valid sync interval.";
            return false;
        }

        syncPreferences = new SyncPreferences
        {
            Enabled = enabled,
            PrimaryConnectionId = primaryId,
            SecondaryConnectionId = secondaryId,
            IntervalMinutes = intervalMinutes,
            SkipGroups = SyncGroupsCheckBox.IsChecked != true,
            SkipAdlists = SyncAdlistsCheckBox.IsChecked != true,
            SkipDomains = SyncDomainsCheckBox.IsChecked != true,
            DryRunEnabled = DryRunCheckBox.IsChecked == true,
            WipeSecondaryBeforeSync = WipeSecondaryCheckBox.IsChecked == true,
        };

        message = string.Empty;
        return true;
    }

    private void UpdateStatusPanel(string? overrideReadiness = null)
    {
        ReadinessTextBlock.Text = overrideReadiness ?? BuildReadinessText();
        LastRunTextBlock.Text = BuildLastRunText();
        ActivityTextBox.Text = BuildActivityText();
    }

    private string BuildReadinessText()
    {
        if (_v6Connections.Count < 2)
        {
            return _v6Connections.Count == 0
                ? "Add two Pi-hole v6 connections in Preferences to enable sync."
                : "Add one more Pi-hole v6 connection in Preferences to enable sync.";
        }

        if (SyncEnabledCheckBox.IsChecked != true)
        {
            return "Sync is currently disabled.";
        }

        var primaryId = PrimaryComboBox.SelectedValue as string ?? string.Empty;
        var secondaryId = SecondaryComboBox.SelectedValue as string ?? string.Empty;
        if (string.IsNullOrWhiteSpace(primaryId) || string.IsNullOrWhiteSpace(secondaryId))
        {
            return "Choose both a primary and a secondary Pi-hole.";
        }

        if (string.Equals(primaryId, secondaryId, StringComparison.Ordinal))
        {
            return "Primary and secondary must point to different Pi-holes.";
        }

        var interval = (IntervalComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "?";
        var dryRunSuffix = DryRunCheckBox.IsChecked == true ? " in dry-run mode" : string.Empty;
        return $"Ready to sync every {interval} minutes{dryRunSuffix}.";
    }

    private string BuildLastRunText()
    {
        if (_preferences.Sync.LastRunAt is null)
        {
            return "No sync has been recorded yet.";
        }

        var timestamp = _preferences.Sync.LastRunAt.Value.ToLocalTime().ToString("g");
        var status = _preferences.Sync.LastStatus?.ToString() ?? "Unknown";
        var summary = string.IsNullOrWhiteSpace(_preferences.Sync.LastSummary) ? string.Empty : $"  {_preferences.Sync.LastSummary}";
        return $"Last sync: {timestamp} ({status}){summary}";
    }

    private string BuildActivityText()
    {
        if (_preferences.Sync.Activity.Count == 0)
        {
            return "No sync activity recorded yet.";
        }

        return string.Join(
            Environment.NewLine,
            _preferences.Sync.Activity
                .OrderByDescending(entry => entry.Timestamp)
                .Select(entry => $"{entry.Timestamp.ToLocalTime():g}  {entry.Message}"));
    }

    private void SelectConnection(System.Windows.Controls.ComboBox comboBox, string id)
    {
        if (string.IsNullOrWhiteSpace(id))
        {
            comboBox.SelectedIndex = -1;
            return;
        }

        comboBox.SelectedValue = id;
    }

    private void SelectInterval(int intervalMinutes)
    {
        foreach (var item in IntervalComboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Content?.ToString(), intervalMinutes.ToString(), StringComparison.Ordinal))
            {
                IntervalComboBox.SelectedItem = item;
                return;
            }
        }

        IntervalComboBox.SelectedIndex = 1;
    }

    private static string BuildDisplayName(ConnectionConfig connection)
    {
        var scheme = connection.UseSsl ? "https" : "http";
        return $"{connection.Hostname} ({scheme}:{connection.Port})";
    }

    private sealed record ConnectionOption(string Id, string DisplayName);
}
