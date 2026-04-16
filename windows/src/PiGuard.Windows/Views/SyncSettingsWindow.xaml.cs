using System.Windows;
using System.Windows.Controls;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Windows.Views;

public partial class SyncSettingsWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private readonly ISyncService _syncService;
    private AppPreferences _preferences = new();
    private List<ConnectionOption> _v6Connections = [];
    private SyncStatusSnapshot _runtimeStatus = new(null, null, string.Empty, false, false, []);

    public SyncSettingsWindow(ISettingsStore settingsStore, ISyncService syncService)
    {
        _settingsStore = settingsStore;
        _syncService = syncService;
        InitializeComponent();
        Loaded += SyncSettingsWindow_Loaded;
        Closed += SyncSettingsWindow_Closed;
    }

    private async void SyncSettingsWindow_Loaded(object sender, RoutedEventArgs e)
    {
        Loaded -= SyncSettingsWindow_Loaded;
        try
        {
            await LoadAsync();
        }
        catch
        {
            StatusTextBlock.Text = "Failed to load sync settings. Your settings file may be corrupt.";
            SaveButton.IsEnabled = false;
            SyncNowButton.IsEnabled = false;
        }
    }

    private async Task LoadAsync()
    {
        _syncService.SyncStatusChanged -= SyncService_SyncStatusChanged;
        _syncService.SyncStatusChanged += SyncService_SyncStatusChanged;
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
        SelectInterval(_preferences.Sync.IntervalMinutes, _preferences.Sync.IntervalUsesCustom);

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

        try
        {
            _preferences = _preferences with { Sync = syncPreferences };
            await _settingsStore.SaveAsync(_preferences);
            UpdateStatusPanel();
            StatusTextBlock.Text = "Sync settings saved.";
        }
        catch
        {
            StatusTextBlock.Text = "Save failed. Please try again.";
        }
    }

    private async void SyncNowButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryBuildSyncPreferences(out var syncPreferences, out var validationMessage))
        {
            StatusTextBlock.Text = validationMessage;
            return;
        }

        SyncNowButton.IsEnabled = false;
        try
        {
            _preferences = _preferences with { Sync = syncPreferences };
            await _settingsStore.SaveAsync(_preferences);
            StatusTextBlock.Text = "Sync requested.";
            await _syncService.TriggerSyncNowAsync();
        }
        catch
        {
            StatusTextBlock.Text = "Sync failed. Please try again.";
        }
        finally
        {
            UpdateStatusPanel();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private void IntervalComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        var isCustom = (IntervalComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() == "Custom";
        CustomIntervalTextBox.Visibility = isCustom ? Visibility.Visible : Visibility.Collapsed;
        CustomIntervalLabel.Visibility = isCustom ? Visibility.Visible : Visibility.Collapsed;
    }

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

        var isCustomInterval = (IntervalComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() == "Custom";
        int intervalMinutes;
        if (isCustomInterval)
        {
            if (!int.TryParse(CustomIntervalTextBox.Text, out intervalMinutes) || intervalMinutes < 1)
            {
                syncPreferences = _preferences.Sync;
                message = "Custom interval must be a whole number of minutes (minimum 1).";
                return false;
            }
        }
        else if (IntervalComboBox.SelectedItem is not ComboBoxItem intervalItem ||
                 !int.TryParse(intervalItem.Content?.ToString(), out intervalMinutes))
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
            IntervalUsesCustom = isCustomInterval,
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
        SyncNowButton.IsEnabled = !_runtimeStatus.IsSyncInProgress && !_runtimeStatus.IsGravityUpdateInProgress;
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

        var isCustomInterval = (IntervalComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() == "Custom";
        var interval = isCustomInterval ? CustomIntervalTextBox.Text : (IntervalComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "?";
        var dryRunSuffix = DryRunCheckBox.IsChecked == true ? " in dry-run mode" : string.Empty;
        return $"Ready to sync every {interval} minutes{dryRunSuffix}.";
    }

    private string BuildLastRunText()
    {
        var lastRunAt = _runtimeStatus.LastRunAt ?? _preferences.Sync.LastRunAt;
        var lastStatus = _runtimeStatus.LastStatus ?? _preferences.Sync.LastStatus;
        var lastSummary = string.IsNullOrWhiteSpace(_runtimeStatus.LastSummary)
            ? _preferences.Sync.LastSummary
            : _runtimeStatus.LastSummary;

        if (lastRunAt is null)
        {
            return "No sync has been recorded yet.";
        }

        var timestamp = lastRunAt.Value.ToLocalTime().ToString("g");
        var status = lastStatus?.ToString() ?? "Unknown";
        var summary = string.IsNullOrWhiteSpace(lastSummary) ? string.Empty : $"  {lastSummary}";
        return $"Last sync: {timestamp} ({status}){summary}";
    }

    private string BuildActivityText()
    {
        var activity = _runtimeStatus.Activity.Count > 0
            ? _runtimeStatus.Activity
            : _preferences.Sync.Activity;

        if (activity.Count == 0)
        {
            return "No sync activity recorded yet.";
        }

        return string.Join(
            Environment.NewLine,
            activity
                .OrderByDescending(entry => entry.Timestamp)
                .Select(entry => $"{entry.Timestamp.ToLocalTime():g}  {entry.Message}"));
    }

    private void SyncSettingsWindow_Closed(object? sender, EventArgs e)
    {
        _syncService.SyncStatusChanged -= SyncService_SyncStatusChanged;
    }

    private void SyncService_SyncStatusChanged(object? sender, SyncStatusSnapshot status)
    {
        if (Dispatcher.CheckAccess())
        {
            ApplyRuntimeStatus(status);
            return;
        }

        _ = Dispatcher.InvokeAsync(() => ApplyRuntimeStatus(status));
    }

    private void ApplyRuntimeStatus(SyncStatusSnapshot status)
    {
        _runtimeStatus = status;
        UpdateStatusPanel();
        StatusTextBlock.Text = status.IsSyncInProgress
            ? "Sync is running..."
            : status.IsGravityUpdateInProgress
                ? "Gravity update is running..."
                : string.IsNullOrWhiteSpace(status.LastSummary)
                    ? StatusTextBlock.Text
                    : status.LastSummary;
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

    private void SelectInterval(int intervalMinutes, bool usesCustom = false)
    {
        if (!usesCustom)
        {
            foreach (var item in IntervalComboBox.Items.OfType<ComboBoxItem>())
            {
                if (string.Equals(item.Content?.ToString(), intervalMinutes.ToString(), StringComparison.Ordinal))
                {
                    IntervalComboBox.SelectedItem = item;
                    return;
                }
            }
        }

        // Fall back to Custom (last item) and populate the text box.
        foreach (var item in IntervalComboBox.Items.OfType<ComboBoxItem>())
        {
            if (item.Content?.ToString() == "Custom")
            {
                IntervalComboBox.SelectedItem = item;
                CustomIntervalTextBox.Text = intervalMinutes.ToString();
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
