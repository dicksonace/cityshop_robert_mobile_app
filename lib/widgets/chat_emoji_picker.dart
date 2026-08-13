import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/chat_emojis.dart';

Future<String?> showChatEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _ChatEmojiPickerSheet(),
  );
}

class _ChatEmojiPickerSheet extends StatefulWidget {
  const _ChatEmojiPickerSheet();

  @override
  State<_ChatEmojiPickerSheet> createState() => _ChatEmojiPickerSheetState();
}

class _ChatEmojiPickerSheetState extends State<_ChatEmojiPickerSheet> {
  int categoryIndex = 0;

  @override
  Widget build(BuildContext context) {
    final category = emojiCategories[categoryIndex];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Emoji', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: emojiCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final selected = index == categoryIndex;
                  return ChoiceChip(
                    label: Text(emojiCategories[index].label),
                    selected: selected,
                    onSelected: (_) => setState(() => categoryIndex = index),
                    selectedColor: const Color(0xFFFFEDD5),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accent : AppColors.textSecondary,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: category.emojis.length,
                itemBuilder: (context, index) {
                  final emoji = category.emojis[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.pop(context, emoji),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
