using System.Windows;
using System.Windows.Controls;
using PiGuard.Core.Abstractions;
using PiGuard.Core.Models;

namespace PiGuard.Windows.Views;

public partial class QueryLogWindow : Window
{
    private readonly ISettingsStore _settingsStore;
    private readonly INetworkInsightsService _networkInsightsService;

    private List<QueryLogEntry> _entries = [];
    private List<QueryLogRow> _filteredRows = [];
    private List<ConnectionOption> _connections = [];
    private bool _isBusy;

    public QueryLogWindow(ISettingsStore settingsStore, INetworkInsightsService networkInsightsService)
    {
        _settingsStore = settingsStore;
        _networkInsightsService = networkInsightsService;
        InitializeComponent();
        Loaded += QueryLogWindow_Loaded;
    }

    private async void QueryLogWindow_Loaded(object sender, RoutedEventArgs e)
    {
        Loaded -= QueryLogWindow_Loaded;
        try
        {
            await LoadFiltersAsync();
            await RefreshAsync();
        }
        catch
        {
            StatusTextBlock.Text = "Failed to load query log.";
        }
    }

    private async Task LoadFiltersAsync()
    {
        var preferences = await _settingsStore.LoadAsync();
        _connections = preferences.Connections
            .Select(connection => new ConnectionOption(connection.Id, $"{connection.Hostname}:{connection.Port}"))
            .OrderBy(connection => connection.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();

        ServerFilterComboBox.ItemsSource = new[] { new ConnectionOption(string.Empty, "All Servers") }
            .Concat(_connections)
            .ToArray();
        ServerFilterComboBox.SelectedIndex = 0;
    }

    private async Task RefreshAsync()
    {
        if (_isBusy)
        {
            return;
        }

        _isBusy = true;
        SetActionState();
        StatusTextBlock.Text = "Loading query log...";

        try
        {
            var serverIdentifier = ServerFilterComboBox.SelectedValue as string;
            _entries = (await _networkInsightsService.FetchQueryLogAsync(
                string.IsNullOrWhiteSpace(serverIdentifier) ? null : serverIdentifier))
                .ToList();
            ApplyFilters();
            StatusTextBlock.Text = $"{_filteredRows.Count} quer{(_filteredRows.Count == 1 ? "y" : "ies")}.";
        }
        catch
        {
            StatusTextBlock.Text = "Failed to load query log.";
        }
        finally
        {
            _isBusy = false;
            SetActionState();
        }
    }

    private void ApplyFilters()
    {
        var selectedServerId = ServerFilterComboBox.SelectedValue as string;
        IEnumerable<QueryLogEntry> filtered = _entries;

        if (!string.IsNullOrWhiteSpace(selectedServerId))
        {
            filtered = filtered.Where(entry => string.Equals(entry.ServerIdentifier, selectedServerId, StringComparison.Ordinal));
        }

        var searchText = SearchTextBox.Text.Trim();
        if (!string.IsNullOrWhiteSpace(searchText))
        {
            filtered = filtered.Where(entry =>
                entry.Domain.Contains(searchText, StringComparison.OrdinalIgnoreCase) ||
                entry.Client.Contains(searchText, StringComparison.OrdinalIgnoreCase) ||
                entry.ServerDisplayName.Contains(searchText, StringComparison.OrdinalIgnoreCase) ||
                entry.Status.ToString().Contains(searchText, StringComparison.OrdinalIgnoreCase));
        }

        _filteredRows = filtered
            .OrderByDescending(entry => entry.Timestamp)
            .Select(entry => new QueryLogRow(entry))
            .ToList();

        QueryLogDataGrid.ItemsSource = _filteredRows;
        ServerColumn.Visibility = string.IsNullOrWhiteSpace(selectedServerId) ? Visibility.Visible : Visibility.Collapsed;
        SetActionState();
    }

    private async Task ApplyDomainRuleAsync(DomainRuleAction action)
    {
        if (_isBusy || QueryLogDataGrid.SelectedItem is not QueryLogRow row)
        {
            return;
        }

        var actionLabel = action == DomainRuleAction.Allow ? "Allow" : "Block";
        var confirmation = System.Windows.MessageBox.Show(
            $"{actionLabel} {row.Domain} across the configured target servers?",
            $"{actionLabel} Domain",
            MessageBoxButton.OKCancel,
            MessageBoxImage.Question);
        if (confirmation != MessageBoxResult.OK)
        {
            return;
        }

        _isBusy = true;
        SetActionState();
        StatusTextBlock.Text = $"{actionLabel}ing {row.Domain}...";

        try
        {
            var results = await _networkInsightsService.ApplyDomainRuleAsync(row.Domain, action);
            var failures = results.Where(result => !result.Succeeded).ToArray();
            StatusTextBlock.Text = failures.Length == 0
                ? $"{actionLabel}ed {row.Domain}."
                : $"{actionLabel} failed: {string.Join("; ", failures.Select(result => $"{result.ServerDisplayName} — {result.Message}"))}.";
        }
        catch
        {
            StatusTextBlock.Text = $"{actionLabel} failed.";
        }
        finally
        {
            _isBusy = false;
            SetActionState();
        }
    }

    private void SetActionState()
    {
        var hasSelection = QueryLogDataGrid.SelectedItem is QueryLogRow;
        AllowButton.IsEnabled = !_isBusy && hasSelection;
        BlockButton.IsEnabled = !_isBusy && hasSelection;
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await RefreshAsync();

    private async void AllowButton_Click(object sender, RoutedEventArgs e) => await ApplyDomainRuleAsync(DomainRuleAction.Allow);

    private async void BlockButton_Click(object sender, RoutedEventArgs e) => await ApplyDomainRuleAsync(DomainRuleAction.Block);

    private void CloseButton_Click(object sender, RoutedEventArgs e) => Close();

    private void SearchTextBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilters();

    private void ServerFilterComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!IsLoaded)
        {
            return;
        }

        ApplyFilters();
    }

    private void QueryLogDataGrid_SelectionChanged(object sender, SelectionChangedEventArgs e) => SetActionState();

    private void QueryLogDataGrid_PreviewMouseRightButtonDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        var row = ItemsControl.ContainerFromElement(QueryLogDataGrid, e.OriginalSource as DependencyObject) as DataGridRow;
        if (row != null)
        {
            row.IsSelected = true;
        }
    }

    private sealed record ConnectionOption(string Id, string DisplayName)
    {
        public override string ToString() => DisplayName;
    }

    private sealed class QueryLogRow
    {
        public QueryLogRow(QueryLogEntry entry)
        {
            Entry = entry;
        }

        public QueryLogEntry Entry { get; }
        public string TimestampLocal => Entry.Timestamp.ToLocalTime().ToString("HH:mm:ss");
        public string Domain => Entry.Domain;
        public string Client => Entry.Client;
        public string StatusLabel => Entry.Status == QueryLogStatus.Blocked ? "Blocked" : "Allowed";
        public string ServerDisplayName => Entry.ServerDisplayName;
    }
}
