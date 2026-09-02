import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/history_controller.dart';
import '../widgets/message_bubble.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<HistoryController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transmission Log & History'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Input
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search transmissions...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          controller.setSearchQuery('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: (val) => controller.setSearchQuery(val),
            ),
            const SizedBox(height: 12),

            // Logs List
            Expanded(
              child: controller.messages.isEmpty
                  ? Center(
                      child: Text(
                        controller.searchQuery.isEmpty
                            ? 'No transmission logs recorded yet.'
                            : 'No transmissions matching "${controller.searchQuery}".',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: controller.messages.length,
                      itemBuilder: (context, index) {
                        return MessageBubble(message: controller.messages[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
