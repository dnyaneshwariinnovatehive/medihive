import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});
  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _scrollCtrl = ScrollController();
  final List<Map<String, String?>> _messages = [];
  final _prompts = ['How do I add a new patient?', "Export last month's data", "Show me today's appointments", 'Help with prescription format'];

  void _send(String text) {
    setState(() => _messages.add({'role': 'user', 'content': text}));
    _scrollDown();
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() => _messages.add({
        'role': 'bot',
        'content': _getResponse(text),
        'action': _getAction(text),
      }));
      _scrollDown();
    });
  }

  String _getResponse(String query) {
    final q = query.toLowerCase();
    if (q.contains('add new patient') || q.contains('new patient') || q.contains('register patient')) {
      return 'To add a new patient:\n\n'
          '1. Tap the "OPD Registration" button on the Dashboard.\n'
          '2. Fill in the patient details: name, age, gender, phone number, and address.\n'
          '3. Tap "Save" to register the patient.\n\n'
          'The patient will appear in your patient list immediately.';
    }
    if (q.contains('export') || q.contains('backup') || q.contains('last month')) {
      return 'To export last month\'s data:\n\n'
          '1. Go to Settings → Backup & Restore (gear icon on Dashboard).\n'
          '2. Tap "Export to Excel".\n'
          '3. Select the date range for last month.\n'
          '4. Choose what to include: Patients, OPD Records, Appointments.\n'
          '5. Tap "Export" — the file will be saved to your device.\n\n'
          'You can also back up to Google Drive from the same screen.';
    }
    if (q.contains('today') && (q.contains('appointment') || q.contains('schedule'))) {
      return 'To view today\'s appointments:\n\n'
          '1. Tap the "Calendar" icon on the Dashboard.\n'
          '2. Today\'s date is highlighted — all appointments for today will be listed.\n'
          '3. Tap any appointment to view or edit details.\n\n'
          'You can also add new appointments from the Calendar screen.';
    }
    if (q.contains('prescription') || q.contains('format') || q.contains('prescription format')) {
      return 'A prescription in MediHive includes:\n\n'
          '• Patient name, age, gender\n'
          '• Diagnosis\n'
          '• Medicines with dosage & duration\n'
          '• Clinical notes\n'
          '• Doctor\'s name, clinic info & license number\n'
          '• Consultation & medicine fees\n'
          '• Follow-up date (optional)\n\n'
          'To create a prescription: go to Patient Details → tap "Create Prescription".\n'
          'The PDF is generated automatically and can be shared via WhatsApp.';
    }
    return 'I\'m a demo assistant with predefined answers. Try one of the suggested prompts above, or contact support for more help.';
  }

  String? _getAction(String query) {
    final q = query.toLowerCase();
    if (q.contains('add new patient') || q.contains('new patient') || q.contains('register patient')) return 'opd';
    if (q.contains('export') || q.contains('backup') || q.contains('last month')) return 'backup';
    if (q.contains('today') && (q.contains('appointment') || q.contains('schedule'))) return 'calendar';
    if (q.contains('prescription') || q.contains('format') || q.contains('prescription format')) return 'prescription';
    return null;
  }

  void _navigate(String? action) {
    switch (action) {
      case 'opd': context.go('/app/opd/new');
      case 'backup': context.go('/app/backup');
      case 'calendar': context.go('/app/calendar');
      case 'prescription': context.go('/app/patients');
    }
  }

  void _scrollDown() => Future.delayed(const Duration(milliseconds: 100), () {
    if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  int _totalItems() {
    // welcome + subtitle + (messages) + (prompt sections after each bot + initial)
    final pairs = _messages.length ~/ 2;
    return 2 + _messages.length + pairs + (_messages.isEmpty ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppTheme.background, body: Column(children: [
      Container(
        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x30000000), blurRadius: 12, offset: Offset(0, 4))]),
        child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Row(children: [
            GestureDetector(onTap: () => context.go('/app'), child: Icon(Icons.arrow_back, color: Colors.white, size: 24)),
            SizedBox(width: 12),
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: 24)),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 20)),
              Text('Always here to help', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
            ]),
            Spacer(),
            Image.asset('assets/images/logo.png', height: 80, width: 80, fit: BoxFit.contain),
          ]))),
      ),
      Expanded(child: ListView.builder(
        controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), itemCount: _totalItems(),
        itemBuilder: (context, index) {
          // ── Index 0: Welcome message ──
          if (index == 0) {
            return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 20, backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                  child: Icon(Icons.smart_toy_outlined, color: AppTheme.primary, size: 20)),
                SizedBox(width: 8),
                Flexible(child: Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppTheme.cardShadow),
                  child: Text("Hello, I am your MediHive AI Assistant", style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)))),
              ],
            ));
          }
          // ── Index 1: "How can I help you today?" ──
          if (index == 1) {
            return Padding(padding: const EdgeInsets.only(left: 48, bottom: 8),
              child: Text('How can I help you today?', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)));
          }
          // ── Remaining: messages interleaved with prompts ──
          final remaining = index - 2;
          final msgCount = _messages.length;

          // Prompt section when no messages yet (index 2 with empty messages)
          if (msgCount == 0) {
            return _buildPrompts();
          }

          // Each pair occupies 3 slots: user, bot, prompts
          final pairIndex = remaining ~/ 3;
          final slotInPair = remaining % 3;

          if (pairIndex * 2 >= msgCount) return SizedBox.shrink();

          if (slotInPair == 0) {
            // User message
            return _buildMessageBubble(_messages[pairIndex * 2], false);
          } else if (slotInPair == 1) {
            // Bot message + action
            return _buildMessageBubble(_messages[pairIndex * 2 + 1], true);
          } else {
            // Prompts after bot response
            return _buildPrompts();
          }
        },
      )),
    ]));
  }

  Widget _buildMessageBubble(Map<String, String?> msg, bool isBot) {
    final content = msg['content'] ?? '';
    final action = msg['action'];
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) CircleAvatar(radius: 20, backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            child: Icon(Icons.smart_toy_outlined, color: AppTheme.primary, size: 20)),
          if (isBot) SizedBox(width: 8),
          Flexible(child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isBot ? Colors.white : AppTheme.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isBot ? AppTheme.cardShadow : null,
            ),
            child: Text(content, style: TextStyle(fontSize: 14, color: isBot ? AppTheme.textPrimary : Colors.white)),
          )),
          if (!isBot) SizedBox(width: 8),
          if (!isBot) CircleAvatar(radius: 20, backgroundColor: AppTheme.primary,
            child: Icon(Icons.person, color: Colors.white, size: 20)),
        ],
      ),
      if (action != null) Padding(
        padding: const EdgeInsets.only(left: 48, top: 8),
        child: TextButton.icon(
          onPressed: () => _navigate(action),
          icon: Icon(Icons.open_in_new, size: 16),
          label: Text(_actionLabel(action)),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      ),
    ]));
  }

  Widget _buildPrompts() {
    return Padding(padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(left: 48, bottom: 10),
          child: Text('Choose a question:', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        Padding(padding: EdgeInsets.only(left: 48),
          child: Wrap(spacing: 8, runSpacing: 8, children: _prompts.map((p) => GestureDetector(
            onTap: () => _send(p),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12), boxShadow: AppTheme.cardShadow),
              child: Text(p, style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500))),
          )).toList())),
      ]));
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'opd': return 'Register New Patient →';
      case 'backup': return 'Open Backup & Restore →';
      case 'calendar': return 'Open Calendar →';
      case 'prescription': return 'View Patient List →';
      default: return 'Open →';
    }
  }
}
