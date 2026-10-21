import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../tv_focusable.dart';

enum TvQuickPlaybackChoice { audio, subtitles, episodes }

Future<TvQuickPlaybackChoice?> showTvQuickPlaybackSheet(BuildContext context,
    {required bool episodes}) => showModalBottomSheet<TvQuickPlaybackChoice>(
  context: context,
  backgroundColor: AppColors.surface,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (sheetContext) => SafeArea(
    child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final choice in TvQuickPlaybackChoice.values)
            if (choice != TvQuickPlaybackChoice.episodes || episodes)
              TvFocusable(
                autofocus: choice == TvQuickPlaybackChoice.audio,
                focusedScale: 1,
                onPressed: () => Navigator.pop(sheetContext, choice),
                child: ListTile(
                  leading: Icon(switch (choice) {
                    TvQuickPlaybackChoice.audio => Icons.audiotrack_rounded,
                    TvQuickPlaybackChoice.subtitles => Icons.subtitles_rounded,
                    TvQuickPlaybackChoice.episodes => Icons.video_library_rounded,
                  }),
                  title: Text(switch (choice) {
                    TvQuickPlaybackChoice.audio => 'Audio',
                    TvQuickPlaybackChoice.subtitles => 'Sottotitoli',
                    TvQuickPlaybackChoice.episodes => 'Stagioni ed episodi',
                  }),
                ),
              ),
        ]),
      ),
    ),
  ),
);