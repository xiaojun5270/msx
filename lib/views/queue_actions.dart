import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../stores/player_store.dart';
import 'glass_surfaces.dart';

Future<void> confirmClearPlaybackQueue(BuildContext context) async {
  final player = context.read<PlayerStore>();
  if (player.queue.isEmpty) return;
  final count = player.queue.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => MusicGlassDialog(
      title: const Text('清空播放队列？'),
      content: Text('将移除队列中的 $count 首歌曲并停止播放。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('全部删除', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (confirmed == true) await player.clearQueue();
}
