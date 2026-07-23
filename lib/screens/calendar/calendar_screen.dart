import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/appointment_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/section_card.dart';
import '../../widgets/standard_header.dart';
import '../../utils/constants.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apt = context.watch<AppointmentProvider>();
    context.watch<SettingsProvider>();

    final daysInMonth = DateTime(
      apt.currentDate.year,
      apt.currentDate.month + 1,
      0,
    ).day;
    final firstDay =
        DateTime(apt.currentDate.year, apt.currentDate.month, 1).weekday % 7;

    final now = DateTime.now();
    final isToday = apt.currentDate.year == now.year &&
        apt.currentDate.month == now.month &&
        apt.selectedDay == now.day;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          const StandardHeader(title: 'Calendar'),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FadeTransition(
                opacity: _fadeController,
                child: Column(
                  children: [
                    SectionCard(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: apt.previousMonth,
                                icon: const Icon(
                                  Icons.chevron_left,
                                  color: AppTheme.primary,
                                  size: 28,
                                ),
                              ),
                              Text(
                                '${AppConstants.monthNames[apt.currentDate.month - 1]} ${apt.currentDate.year}',
                                style: AppTheme.subHeading.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              IconButton(
                                onPressed: apt.nextMonth,
                                icon: const Icon(
                                  Icons.chevron_right,
                                  color: AppTheme.primary,
                                  size: 28,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: AppConstants.dayAbbreviations.map((d) {
                              return Expanded(
                                child: Center(
                                  child: Text(
                                    d.toUpperCase(),
                                    style: AppTheme.caption.copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 7,
                                  childAspectRatio: 1.0,
                                ),
                            itemCount: firstDay + daysInMonth,
                            itemBuilder: (context, index) {
                              if (index < firstDay) {
                                return const SizedBox.shrink();
                              }
                              final day = index - firstDay + 1;

                              final now = DateTime.now();
                              final cellDate = DateTime(
                                apt.currentDate.year,
                                apt.currentDate.month,
                                day,
                              );
                              final today = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              final isPastDate = cellDate.isBefore(today);
                              final isToday = cellDate.isAtSameMomentAs(today);

                              final isSelected = day == apt.selectedDay;
                              final hasFollowUp = apt.appointments.any(
                                (a) =>
                                    a.dateTime.day == day &&
                                    a.dateTime.month == apt.currentDate.month &&
                                    a.dateTime.year == apt.currentDate.year &&
                                    a.type == 'Follow-up',
                              );
                              final hasNotes = apt.hasNotesForDay(day);
                              final cell = Container(
                                margin: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : isToday
                                      ? AppTheme.primary.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: isToday
                                      ? Border.all(
                                          color: AppTheme.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                  boxShadow: isSelected
                                      ? AppTheme.cardShadow
                                      : null,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Positioned(
                                      top: 8,
                                      child: Text(
                                        '$day',
                                        style: AppTheme.body.copyWith(
                                          fontSize: 14,
                                          fontWeight: isSelected || isToday
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : isToday
                                              ? AppTheme.primary
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (hasFollowUp || hasNotes)
                                      Positioned(
                                        bottom: 4,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (hasFollowUp)
                                              Container(
                                                width: 5,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : AppTheme.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            if (hasFollowUp && hasNotes)
                                              const SizedBox(width: 3),
                                            if (hasNotes)
                                              Container(
                                                width: 5,
                                                height: 5,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? Colors.white
                                                      : Colors.amber,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              );

                              if (isPastDate) {
                                return IgnorePointer(
                                  ignoring: true,
                                  child: Opacity(opacity: 0.25, child: cell),
                                );
                              }

                              return GestureDetector(
                                onTap: () => apt.setSelectedDay(day),
                                child: cell,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _DayNoteSection(
                      key: ValueKey('notes-${apt.currentDate.year}-${apt.currentDate.month}-${apt.selectedDay}'),
                      notes: apt.dayNotes,
                      onAddNote: (v) => apt.addNote(v),
                      onRemoveNote: (i) => apt.removeNoteAt(i),
                    ),
                    const SizedBox(height: 16),

                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          final followUps = apt.selectedDayFollowUps;
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: AppTheme.background,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20),
                              ),
                            ),
                            builder: (context) => Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isToday
                                        ? "Today's Follow-ups"
                                        : 'Upcoming Follow-ups',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (followUps.isEmpty)
                                    Text(
                                      isToday
                                          ? 'No follow-ups today.'
                                          : 'No follow-ups on this date.',
                                    )
                                  else
                                    ...followUps.map(
                                      (f) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundColor: AppTheme.primary
                                              .withValues(alpha: 0.1),
                                          child: const Icon(
                                            Icons.person,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                        title: Text(
                                          f.patient,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'ID: ${f.id} • ${f.dateTime.day}/${f.dateTime.month}/${f.dateTime.year}',
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppTheme.heavyShadow,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isToday
                                    ? "Today's Follow-ups"
                                    : 'Upcoming Follow-ups',
                                style: AppTheme.caption.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${apt.selectedDayFollowUps.length} Scheduled',
                                    style: AppTheme.display.copyWith(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _DayNoteSection extends StatefulWidget {
  final List<String> notes;
  final ValueChanged<String> onAddNote;
  final ValueChanged<int> onRemoveNote;
  const _DayNoteSection({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onRemoveNote,
  });

  @override
  State<_DayNoteSection> createState() => _DayNoteSectionState();
}

class _DayNoteSectionState extends State<_DayNoteSection> {
  late TextEditingController _controller;
  List<String> _notes = [];

  @override
  void initState() {
    super.initState();
    _notes = List.from(widget.notes);
    _controller = TextEditingController();
  }

  @override
  void didUpdateWidget(_DayNoteSection old) {
    super.didUpdateWidget(old);
    if (widget.notes != old.notes) {
      _notes = List.from(widget.notes);
    }
  }

  void _handleAdd() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAddNote(text);
    _controller.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Note added'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _notes = List.from(widget.notes);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Clinical Notes',
                style: AppTheme.subHeading.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              Icon(Icons.edit_note, color: AppTheme.primary, size: 24),
            ],
          ),
          if (_notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...List.generate(_notes.length, (i) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(
                    left: BorderSide(color: AppTheme.success, width: 3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.sticky_note_2_outlined,
                      size: 18, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _notes[i],
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        widget.onRemoveNote(i);
                        setState(() {});
                      },
                      child: Icon(Icons.close, size: 16, color: AppTheme.textHint),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 2,
                  style: AppTheme.body,
                  decoration: InputDecoration(
                    hintText: 'Add clinical reminders, doctor schedule notes...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.border),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              if (_controller.text.trim().isNotEmpty)
                GestureDetector(
                  onTap: _handleAdd,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
