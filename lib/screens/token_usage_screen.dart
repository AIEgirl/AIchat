import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart' as path_provider;
import '../services/database_service.dart';

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

  List<_DayTotal> _aggrgegate() {
    final map = <String, int>{};
    for (final row in _data) {
      final ts = DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int);
      final key = DateFormat('MM-dd').format(ts);
      map[key] = (map[key] ?? 0) + (row['prompt_tokens'] as int) + (row['completion_tokens'] as int);
    }
    final entries = map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => _DayTotal(e.key, e.value)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Token 用量统计'), actions: [
        IconButton(icon: Icon(_cumulative ? Icons.show_chart : Icons.bar_chart), tooltip: _cumulative ? '累积模式' : '每日模式', onPressed: () => setState(() => _cumulative = !_cumulative)),
        IconButton(icon: const Icon(Icons.file_download), tooltip: '导出 CSV', onPressed: _export),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _data.isEmpty ? const Center(child: Text('暂无数据')) : Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          // 图表
          SizedBox(height: 220, child: _buildChart()),
          const SizedBox(height: 16),
          // 统计
          _buildStats(),
        ]),
      ),
    );
  }

  Widget _buildChart() {
    final days = _aggrgegate();
    if (days.isEmpty) return const Center(child: Text('无数据'));
    int running = 0;

    final spots = <FlSpot>[];
    for (int i = 0; i < days.length; i++) {
      if (_cumulative) {
        running += days[i].total;
        spots.add(FlSpot(i.toDouble(), running.toDouble()));
      } else {
        spots.add(FlSpot(i.toDouble(), days[i].total.toDouble()));
      }
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: _cumulative ? null : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2,
        barGroups: spots.map((s) => BarChartGroupData(x: s.x.toInt(), barRods: [
          BarChartRodData(toY: s.y, color: Colors.indigo, width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ])).toList(),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (v, _) => Text(_formatNum(v.toInt()), style: const TextStyle(fontSize: 10)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
            final idx = v.toInt();
            if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
            return Text(days[idx].date, style: const TextStyle(fontSize: 9));
          })),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }

  Widget _buildStats() {
    int totalTokens = 0;
    for (final row in _data) { totalTokens += (row['prompt_tokens'] as int) + (row['completion_tokens'] as int); }
    final dayCount = _aggrgegate().length;
    final avg = dayCount > 0 ? totalTokens ~/ dayCount : 0;
    final last = _data.isNotEmpty ? (_data.last['prompt_tokens'] as int) + (_data.last['completion_tokens'] as int) : 0;
    final model = _data.isNotEmpty ? _data.last['model'] as String? : '-';

    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        const Text('统计摘要', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _statRow('本月总 Token', _formatNum(totalTokens)),
        _statRow('日均 Token', _formatNum(avg)),
        _statRow('最近调用', _formatNum(last)),
        _statRow('使用模型', model ?? '-'),
      ])),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
      Text('$label: ', style: const TextStyle(color: Colors.grey)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    ]));
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Future<void> _export() async {
    final sb = StringBuffer('date,prompt_tokens,completion_tokens,model\n');
    for (final row in _data) {
      final ts = DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int);
      sb.writeln('${DateFormat('yyyy-MM-dd HH:mm:ss').format(ts)},${row['prompt_tokens']},${row['completion_tokens']},${row['model'] ?? ''}');
    }
    try {
      final dir = await path_provider.getApplicationDocumentsDirectory();
      final file = File('${dir.path}/token_usage_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(sb.toString());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV 导出: ${file.path}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
    }
  }
}

class _DayTotal {
  final String date;
  final int total;
  const _DayTotal(this.date, this.total);
}
