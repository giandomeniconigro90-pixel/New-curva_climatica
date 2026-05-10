// lib/features/home/widgets/rooms_manager_sheet.dart

import 'package:flutter/material.dart';
import '../../../core/constants/room_constants.dart';
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

  /// Le zone fisiche obbligatorie non possono essere eliminate.
  static const List<String> _fixedZones = RoomConstants.defaultRooms;

  bool _isFixed(String room) => _fixedZones.contains(room);

  @override
  void initState() {
    super.initState();
    _rooms = List.from(widget.initialRooms);
    // Assicura che le zone fisse siano sempre presenti in cima
    for (final zone in _fixedZones.reversed) {
      if (!_rooms.contains(zone)) {
        _rooms.insert(0, zone);
      }
    }
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
    final room = _rooms[index];
    if (_isFixed(room)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$room" è una zona fisica obbligatoria e non può essere eliminata.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
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
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
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
                  style: TextButton.styleFrom(foregroundColor: cs.primary),
                ),
              ],
            ),
          ),
          // Sottotitolo informativo
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Le zone fisiche (🔒) sono obbligatorie e non eliminabili. Puoi aggiungere stanze extra opzionali.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          // Lista stanze
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _rooms.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  // Impedisce di spostare una zona fissa sotto una non-fissa
                  // o di spostare una stanza extra sopra le zone fisse
                  final movingFixed = _isFixed(_rooms[oldIndex]);
                  final targetFixed = newIndex < _fixedZones.length;
                  if (!movingFixed && targetFixed) return; // non puoi salire sopra le fisse
                  if (movingFixed) {
                    // Le zone fisse possono riordinarsi solo tra loro
                    if (newIndex >= _fixedZones.length) return;
                  }
                  final item = _rooms.removeAt(oldIndex);
                  _rooms.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final room = _rooms[index];
                final fixed = _isFixed(room);
                return ListTile(
                  key: ValueKey(room),
                  leading: Icon(
                    fixed ? Icons.lock_outline : Icons.drag_handle,
                    color: fixed ? cs.primary : cs.onSurfaceVariant,
                    size: 20,
                  ),
                  title: Text(
                    room,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: fixed ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: fixed
                      ? Text(
                          'Zona fisica obbligatoria',
                          style: TextStyle(fontSize: 11, color: cs.primary.withValues(alpha: 0.8)),
                        )
                      : null,
                  trailing: fixed
                      ? Icon(Icons.lock_outline, color: cs.primary.withValues(alpha: 0.4), size: 18)
                      : IconButton(
                          icon: Icon(Icons.delete_outline, color: cs.error),
                          onPressed: () => _deleteRoom(index),
                          tooltip: 'Elimina stanza',
                        ),
                );
              },
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          // Input aggiungi stanza
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
                      hintText: 'Nome stanza extra (es. Studio)...',
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
