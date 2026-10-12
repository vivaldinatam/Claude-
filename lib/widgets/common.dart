import 'package:flutter/material.dart';

import '../core/format.dart';
import '../services/api.dart';

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(errorMessage(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ya')),
      ],
    ),
  );
  return result ?? false;
}

/// FutureBuilder dengan tampilan loading, error + tombol coba lagi, dan pull-to-refresh.
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Future<void> Function() onRefresh;

  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(errorMessage(snap.error!), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: onRefresh, child: const Text('Coba lagi')),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(onRefresh: onRefresh, child: builder(context, snap.data as T));
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class MonthSelector extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthSelector({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        Text(fmtMonth(month), style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const StatusChip({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' || 'hadir' => Colors.green,
      'rejected' => Colors.red,
      'terlambat' => Colors.orange,
      'libur_masuk' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color.shade700, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
