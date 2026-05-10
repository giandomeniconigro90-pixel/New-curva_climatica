// lib/features/home/widgets/rooms_manager_sheet.dart

import 'package:flutter/material.dart';
import '../../../services/hive_storage.dart';

class RoomsManagerSheet extends StatefulWidget {
  final List<String> initialRooms;

  const RoomsManagerSheet({super.key, required this.initialRooms});

  @override
  State<RoomsManagerSheet> createState() => _RoomsManagerSheetState();
}

class _RoomsManagerSheetState extends State<RoomsManagerSheet> {
  late List<String> _rooms;
  final TextEditingController _addController = TextEditingController();
  final FocusNode _addFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _rooms = List.from(widget.initialRooms);
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AppStorage.saveRooms(_rooms);
    if (mounted) Navigator.of(context).pop();
  }

  void _addRoom() {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    if (_rooms.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$name" esiste gi\u00e0.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _rooms.add(name);
      _addController.clear();
    });
    _addFocus.unfocus();
  }

  void _deleteRoom(int index) {
    setState(() => _rooms.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final maxHeight = mq.size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.meeting_room_outlined, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Gestisci Stanze',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _rooms.isEmpty ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('SALVA'),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Flexible(
            child: _rooms.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nessuna stanza.\nAggiungine una qui sotto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _rooms.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _rooms.removeAt(oldIndex);
                        _rooms.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      return ListTile(
                        key: ValueKey(room),
                        leading: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
                        title: Text(room, style: TextStyle(color: cs.onSurface)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: cs.error),
                          onPressed: () => _deleteRoom(index),
                          tooltip: 'Elimina stanza',
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + mq.viewInsets.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    focusNode: _addFocus,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Nome nuova stanza...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) => _addRoom(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _addRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('Aggiungi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
