import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../services/database_service.dart';
import '../l10n/app_localizations.dart';

class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});
  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;
  bool _cumulative = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _data = await DatabaseService.getTokenUsage(days: 30);
    setState(() => _loading = false);
  }

  List<_DayTotal> _aggregate() {
    final map = <String, int>{};
    for (final row in _data) {
      final ts = DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int);
      final key = DateFormat('MM-dd').format(ts);
      map[key] = (map[key] ?? 0) +
          (row['prompt_tokens'] as int) +
          (row['completion_tokens'] as int);
    }
    final entries = map.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => _DayTotal(e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.get('tokenUsageTitle')),
        actions: [
          IconButton(
              icon: Icon(
                  _cumulative ? Icons.show_chart : Icons.bar_chart),
              tooltip: _cumulative
                  ? l10n.get('cumulativeMode')
                  : l10n.get('dailyMode'),
              onPressed: () => setState(() => _cumulative = !_cumulative)),
          IconButton(
              icon: const Icon(Icons.file_download),
              tooltip: l10n.get('exportCSV'),
              onPressed: _export),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data.isEmpty
              ? Center(child: Text(l10n.get('noData')))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    SizedBox(height: 220, child: _buildChart()),
                    const SizedBox(height: 16),
                    _buildStats(),
                  ]),
                ),
    );
  }

  Widget _buildChart() {
    final days = _aggregate();
    if (days.isEmpty) {
      return const Center(child: Text('—'));
    }
    final spots = <FlSpot>[];
    int maxY = 0;
    for (int i = 0; i < days.length; i++) {
      spots.add(FlSpot(i.toDouble(), days[i].total.toDouble()));
      if (days[i].total > maxY) maxY = days[i].total;
    }
    final scheme = Theme.of(context).colorScheme;
    return LineChart(
      LineChartData(
        gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1)),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (v, _) =>
                      Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)))),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= days.length) return const SizedBox.shrink();
                    return Text(days[i].date,
                        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant));
                  })),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: scheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final days = _aggregate();
    final total = days.fold<int>(0, (s, d) => s + d.total);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('30d', '$total', Icons.token),
              _stat('avg', '${days.isEmpty ? 0 : total ~/ days.length}', Icons.trending_up),
              _stat('max', '${days.isEmpty ? 0 : days.map((d) => d.total).reduce((a, b) => a > b ? a : b)}', Icons.arrow_upward),
            ]),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Icon(icon, size: 20, color: scheme.primary),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
    ]);
  }

  Future<void> _export() async {
    try {
      final l10n = AppLocalizations.of(context);
      final rows = await DatabaseService.getTokenUsage(days: 365);
      final buf = StringBuffer('date,prompt_tokens,completion_tokens\n');
      for (final r in rows) {
        final ts = DateTime.fromMillisecondsSinceEpoch(r['timestamp'] as int);
        buf.writeln(
            '${DateFormat('yyyy-MM-dd HH:mm').format(ts)},${r['prompt_tokens']},${r['completion_tokens']}');
      }
      final dir = await path_provider.getApplicationDocumentsDirectory();
      final file = File('${dir.path}/token_usage_export.csv');
      await file.writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.get('logsExported')} ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.get('exportFailed')}: $e')));
      }
    }
  }
}

class _DayTotal {
  final String date;
  final int total;
  const _DayTotal(this.date, this.total);
}
