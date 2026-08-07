import 'package:flutter/material.dart';

import '../data/ghana_banks.dart';
import '../theme/app_theme.dart';
import 'app_sheet.dart';

/// Opens a "Select Bank" sheet with radio circles — same pattern as Ghana
/// banking apps (ABSA, Access, GCB, …).
Future<GhanaBank?> showBankPickerSheet({
  required BuildContext context,
  required List<GhanaBank> banks,
  String? selectedId,
}) {
  return showAppSheet<GhanaBank>(
    context: context,
    builder: (ctx) => _BankPickerSheet(
      banks: banks,
      selectedId: selectedId,
    ),
  );
}

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet({required this.banks, this.selectedId});

  final List<GhanaBank> banks;
  final String? selectedId;

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  late String? _selected = widget.selectedId;
  String _query = '';

  List<GhanaBank> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.banks;
    return widget.banks.where((b) => b.label.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;

    return SheetShell(
      maxHeightFactor: 0.92,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Select Bank',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: const InputDecoration(
            hintText: 'Search bank',
            prefixIcon: Icon(Icons.search_rounded),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No bank matches that search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          for (final bank in rows) ...[
            _BankRadioRow(
              label: bank.label,
              selected: _selected == bank.id,
              onTap: () {
                setState(() => _selected = bank.id);
                Navigator.pop(context, bank);
              },
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
          ],
      ],
    );
  }
}

class _BankRadioRow extends StatelessWidget {
  const _BankRadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            // Radio circle — the control Robert circled in the banking app.
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : const Color(0xFF9CA3AF),
                  width: selected ? 2 : 1.6,
                ),
              ),
              alignment: Alignment.center,
              child: selected
                  ? Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 15,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact field that opens [showBankPickerSheet].
class BankSelectField extends StatelessWidget {
  const BankSelectField({
    super.key,
    required this.banks,
    required this.selectedId,
    required this.onSelected,
  });

  final List<GhanaBank> banks;
  final String selectedId;
  final ValueChanged<GhanaBank> onSelected;

  @override
  Widget build(BuildContext context) {
    GhanaBank? selected;
    for (final bank in banks) {
      if (bank.id == selectedId) {
        selected = bank;
        break;
      }
    }
    selected ??= banks.isNotEmpty ? banks.first : null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showBankPickerSheet(
            context: context,
            banks: banks,
            selectedId: selected?.id ?? selectedId,
          );
          if (picked != null) onSelected(picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Bank',
            border: OutlineInputBorder(),
            suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
          ),
          child: Text(
            selected?.label ?? 'Select Bank',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
