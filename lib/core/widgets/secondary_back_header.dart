import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SecondaryBackHeader extends ConsumerWidget {
  const SecondaryBackHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('mobile-secondary-back-button'),
          tooltip: 'Volver',
          onPressed: ref.read(appDestinationProvider.notifier).back,
          icon: const Icon(Icons.arrow_back),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
