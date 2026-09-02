import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/entities/message_entity.dart';

class MessageBubble extends StatelessWidget {
  final MessageEntity message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncoming = message.isIncoming;
    final isAlert = message.type == 'ALERT';
    final timeStr = DateFormat('HH:mm:ss').format(
      DateTime.fromMillisecondsSinceEpoch(message.timestamp),
    );

    return Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isAlert
                ? theme.colorScheme.errorContainer
                : isIncoming
                    ? theme.colorScheme.surfaceContainerHighest
                    : theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isIncoming ? const Radius.circular(4) : const Radius.circular(16),
              bottomRight: isIncoming ? const Radius.circular(16) : const Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
            border: isAlert
                ? Border.all(color: theme.colorScheme.error, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isIncoming ? 'From: ${message.senderId}' : 'You',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isAlert
                          ? theme.colorScheme.onErrorContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    timeStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isAlert
                          ? theme.colorScheme.onErrorContainer.withAlpha(180)
                          : theme.colorScheme.onSurfaceVariant.withAlpha(180),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isAlert ? FontWeight.w600 : FontWeight.normal,
                  color: isAlert
                      ? theme.colorScheme.onErrorContainer
                      : isIncoming
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onPrimaryContainer,
                ),
              ),
              if (isAlert) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'PRIORITY DISTRESS ALERT',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
