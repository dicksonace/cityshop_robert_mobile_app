import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../store/app_store.dart';
import '../theme/app_theme.dart';

const reportContentReasons = <({String value, String label})>[
  (value: 'scam', label: 'Scam or fraud'),
  (value: 'counterfeit', label: 'Counterfeit or fake'),
  (value: 'harassment', label: 'Harassment or abuse'),
  (value: 'poor_service', label: 'Poor service'),
  (value: 'prohibited_items', label: 'Prohibited or illegal'),
  (value: 'fake_listings', label: 'Misleading content'),
  (value: 'other', label: 'Other'),
];

Future<void> showReportContentSheet(
  BuildContext context, {
  required String targetType,
  required int targetId,
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ReportContentSheet(
      targetType: targetType,
      targetId: targetId,
      title: title,
    ),
  );
}

class _ReportContentSheet extends StatefulWidget {
  const _ReportContentSheet({
    required this.targetType,
    required this.targetId,
    required this.title,
  });

  final String targetType;
  final int targetId;
  final String title;

  @override
  State<_ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends State<_ReportContentSheet> {
  String reason = reportContentReasons.first.value;
  final details = TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => submitting = true);
    try {
      await context.read<AppStore>().reportContent(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
            details: details.text,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report sent. We review reports within 24 hours. You can block this person from the chat.'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          const Text(
            'Tell us what is wrong. CityUnlock reviews reports within 24 hours. For urgent help, use Contact support in your profile.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: [
              for (final item in reportContentReasons)
                DropdownMenuItem(value: item.value, child: Text(item.label)),
            ],
            onChanged: submitting
                ? null
                : (value) {
                    if (value != null) setState(() => reason = value);
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: details,
            maxLines: 3,
            maxLength: 2000,
            enabled: !submitting,
            decoration: const InputDecoration(
              labelText: 'Details (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: submitting ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(submitting ? 'Sending…' : 'Submit report'),
          ),
        ],
      ),
    );
  }
}
