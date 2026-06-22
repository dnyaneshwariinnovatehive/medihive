import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/settings_group_tile.dart';
import '../../widgets/standard_header.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/notification_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _appVersion = 'v1.0.3';

  @override
  void initState() {
    super.initState();
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AppTheme.danger : AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String getInitials(String name) {
    final cleanName = name.replaceAll(
      RegExp(r'^Dr\.\s+', caseSensitive: false),
      '',
    );
    final parts = cleanName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'RG';
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.primary, width: 2),
            ),
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }

  void _showSettingsEditDialog({
    required IconData icon,
    required String title,
    required List<Widget> fields,
    required String? Function() validate,
    required Future<void> Function() onSave,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: AppTheme.primary, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: isSaving ? null : () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),
                    ...fields,
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isSaving ? null : () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: isSaving
                                ? null
                                : () async {
                                    final error = validate();
                                    if (error != null) {
                                      _showToast(error, isError: true);
                                      return;
                                    }
                                    setDialogState(() => isSaving = true);
                                    try {
                                      await onSave();
                                      if (context.mounted) {
                                        Navigator.pop(ctx);
                                        _showToast('$title updated successfully!');
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        _showToast('Failed to save: $e', isError: true);
                                      }
                                    } finally {
                                      if (context.mounted) {
                                        setDialogState(() => isSaving = false);
                                      }
                                    }
                                  },
                            child: isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                     child: CircularProgressIndicator(
                                       strokeWidth: 2,
                                       color: AppTheme.textOnPrimary,
                                     ),
                                   )
                                 : Text(
                                     'Save Changes',
                                     style: TextStyle(color: AppTheme.textOnPrimary),
                                   ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDoctorProfileDialog(SettingsProvider settings) {
    final nameController = TextEditingController(text: settings.doctorName);
    final specialtyController = TextEditingController(
      text: settings.doctorSpecialty,
    );
    final licenseController = TextEditingController(
      text: settings.doctorLicense,
    );
    final emailController = TextEditingController(text: settings.doctorEmail);
    final phoneController = TextEditingController(text: settings.doctorPhone);

    _showSettingsEditDialog(
      icon: Icons.person,
      title: 'Doctor Profile',
      fields: [
        _buildTextField('Full Name', nameController),
        const SizedBox(height: 12),
        _buildTextField('Specialty / Designation', specialtyController),
        const SizedBox(height: 12),
        _buildTextField('Medical License Number', licenseController),
        const SizedBox(height: 12),
        _buildTextField(
          'Email Address',
          emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          'Phone Number',
          phoneController,
          keyboardType: TextInputType.phone,
        ),
      ],
      validate: () {
        if (nameController.text.trim().isEmpty ||
            licenseController.text.trim().isEmpty) {
          return 'Name and License are required!';
        }
        final email = emailController.text.trim();
        if (email.isNotEmpty &&
            !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          return 'Please enter a valid email address.';
        }
        final phone = phoneController.text.trim();
        if (phone.isNotEmpty &&
            !RegExp(r'^\+?[\d\s\-()]{7,20}$').hasMatch(phone)) {
          return 'Please enter a valid phone number.';
        }
        return null;
      },
      onSave: () async {
        await settings.updateDoctorProfile(
          name: nameController.text.trim(),
          specialty: specialtyController.text.trim(),
          license: licenseController.text.trim(),
          email: emailController.text.trim(),
          phone: phoneController.text.trim(),
        );
      },
    );
  }

  void _showClinicInfoDialog(SettingsProvider settings) {
    final nameController = TextEditingController(text: settings.clinicName);
    final phoneController = TextEditingController(text: settings.clinicPhone);
    final addressController = TextEditingController(
      text: settings.clinicAddress,
    );
    final hoursController = TextEditingController(text: settings.clinicHours);
    final websiteController = TextEditingController(
      text: settings.clinicWebsite,
    );

    _showSettingsEditDialog(
      icon: Icons.business,
      title: 'Clinic Information',
      fields: [
        _buildTextField('Clinic Name', nameController),
        const SizedBox(height: 12),
        _buildTextField(
          'Clinic Phone / Contact',
          phoneController,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _buildTextField('Full Address', addressController, maxLines: 2),
        const SizedBox(height: 12),
        _buildTextField('Working Hours', hoursController),
        const SizedBox(height: 12),
        _buildTextField(
          'Website (optional)',
          websiteController,
          keyboardType: TextInputType.url,
        ),
      ],
      validate: () {
        if (nameController.text.trim().isEmpty ||
            addressController.text.trim().isEmpty) {
          return 'Clinic Name and Address are required!';
        }
        return null;
      },
      onSave: () async {
        await settings.updateClinicInfo(
          name: nameController.text.trim(),
          phone: phoneController.text.trim(),
          address: addressController.text.trim(),
          hours: hoursController.text.trim(),
          website: websiteController.text.trim(),
        );
      },
    );
  }

  void _showEmailConfigDialog(SettingsProvider settings) {
    final senderController = TextEditingController(text: settings.emailSender);
    final smtpController = TextEditingController(text: settings.emailSmtp);
    final portController = TextEditingController(text: settings.emailPort);
    final userController = TextEditingController(text: settings.emailUser);
    final passController = TextEditingController(text: settings.emailPass);

    bool showPass = false;
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.mail,
                                color: AppTheme.primary,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Email Configuration',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      Divider(),
                      SizedBox(height: 12),
                      _buildTextField(
                        'Sender Name / Display Name',
                        senderController,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              'SMTP Server',
                              smtpController,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: _buildTextField(
                              'Port',
                              portController,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _buildTextField(
                        'SMTP Username / Email',
                        userController,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      SizedBox(height: 12),
                      _buildTextField(
                        'SMTP Password / App Password',
                        passController,
                        obscureText: !showPass,
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPass ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                          ),
                          onPressed: () {
                            setStateDialog(() {
                              showPass = !showPass;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: AppTheme.primary),
                            padding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: isTesting
                              ? null
                              : () async {
                                  if (smtpController.text.trim().isEmpty ||
                                      userController.text.trim().isEmpty ||
                                      passController.text.trim().isEmpty) {
                                    _showToast(
                                      'Please fill SMTP Server, Username, and Password to test connection.',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final port = portController.text.trim();
                                  if (port.isNotEmpty) {
                                    final portNum = int.tryParse(port);
                                    if (portNum == null || portNum < 1 || portNum > 65535) {
                                      _showToast(
                                        'Port must be a number between 1 and 65535.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                  }
                                  setStateDialog(() {
                                    isTesting = true;
                                  });
                                  try {
                                    await settings.updateEmailConfig(
                                      sender: senderController.text.trim(),
                                      smtp: smtpController.text.trim(),
                                      port: portController.text.trim(),
                                      user: userController.text.trim(),
                                      pass: passController.text.trim(),
                                    );
                                    await Future.delayed(
                                      const Duration(milliseconds: 800),
                                    );
                                  } finally {
                                    setStateDialog(() {
                                      isTesting = false;
                                    });
                                  }
                                  _showToast(
                                    'SMTP settings saved. Test connection from server.',
                                  );
                                },
                          icon: isTesting
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : Icon(Icons.network_ping, size: 16),
                          label: Text(
                            isTesting
                                ? 'Verifying Mail Server Connection...'
                                : 'Test SMTP Connection',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel'),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () async {
                                if (senderController.text.trim().isEmpty ||
                                    smtpController.text.trim().isEmpty ||
                                    userController.text.trim().isEmpty) {
                                  _showToast(
                                    'Sender, SMTP Server, and Username are required!',
                                    isError: true,
                                  );
                                  return;
                                }
                                final port = portController.text.trim();
                                if (port.isNotEmpty) {
                                  final portNum = int.tryParse(port);
                                  if (portNum == null || portNum < 1 || portNum > 65535) {
                                    _showToast(
                                      'Port must be a number between 1 and 65535.',
                                      isError: true,
                                    );
                                    return;
                                  }
                                }
                                await settings.updateEmailConfig(
                                  sender: senderController.text.trim(),
                                  smtp: smtpController.text.trim(),
                                  port: portController.text.trim(),
                                  user: userController.text.trim(),
                                  pass: passController.text.trim(),
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  _showToast(
                                    'Email Settings updated successfully!',
                                  );
                                }
                              },
                              child: Text(
                                'Save Changes',
                                style: TextStyle(color: AppTheme.textOnPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final unreadCount = context.watch<NotificationProvider>().unreadCount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const StandardHeader(title: 'Settings'),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppTheme.surfaceVariant,
                          backgroundImage:
                              settings.doctorProfileImage.isNotEmpty
                              ? MemoryImage(
                                  base64Decode(
                                    settings.doctorProfileImage,
                                  ),
                                )
                              : null,
                          child: settings.doctorProfileImage.isEmpty
                              ? Text(
                                  getInitials(settings.doctorName),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            settings.doctorName,
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${settings.clinicName} • ${settings.doctorSpecialty}',
                            style: TextStyle(
                                color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'License: ${settings.doctorLicense}',
                            style: TextStyle(
                                color: AppTheme.textHint,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Account'),
                  _group([
                    SettingsGroupTile(
                      icon: Icons.person_outline,
                      label: 'Doctor Profile',
                      onTap: () => _showDoctorProfileDialog(settings),
                    ),
                    SettingsGroupTile(
                      icon: Icons.business,
                      label: 'Clinic Information',
                      onTap: () => _showClinicInfoDialog(settings),
                    ),
                    SettingsGroupTile(
                      icon: Icons.mail_outline,
                      label: 'Email Configuration',
                      onTap: () => _showEmailConfigDialog(settings),
                      showDivider: false,
                    ),
                  ]),
                  SizedBox(height: 20),
                  _sectionLabel('Data & Security'),
                  _group([
                    SettingsGroupTile(
                      icon: Icons.cloud_outlined,
                      label: 'Backup & Cloud Sync',
                      iconBgColor: AppTheme.success.withValues(alpha: 0.1),
                      iconColor: AppTheme.success,
                      onTap: () => context.go('/app/backup'),
                    ),
                    SettingsGroupTile(
                      icon: Icons.shield_outlined,
                      label: 'Authentication',
                      onTap: () => context.go('/app/authentication'),
                      showDivider: false,
                    ),
                    SettingsGroupTile(
                      icon: Icons.upload_file_outlined,
                      label: 'Import from Desktop',
                      onTap: () => context.go('/app/settings/import'),
                      iconBgColor: AppTheme.primarySurface,
                      iconColor: AppTheme.primary,
                      showDivider: false,
                    ),
                  ]),
                  SizedBox(height: 20),
                  _sectionLabel('Google Cloud Backup'),
                  _buildGoogleDriveSection(settings),
                  SizedBox(height: 20),
                  _sectionLabel('Preferences'),
                  _group([
                    SettingsGroupTile(
                      icon: Icons.notifications_outlined,
                      label: 'Notifications',
                      badge: unreadCount > 0 ? (unreadCount > 9 ? '9+' : unreadCount.toString()) : null,
                      onTap: () => context.push('/app/settings/notifications'),
                    ),
                    SettingsGroupTile(
                      icon: Icons.dark_mode_outlined,
                      label: 'Dark Mode',
                      isToggle: true,
                      toggleValue: settings.darkMode,
                      onToggleChanged: (value) {
                        settings.toggleDarkMode();
                      },
                      showDivider: false,
                    ),
                  ]),
                  SizedBox(height: 20),
                  _sectionLabel('Support'),
                  _group([
                    SettingsGroupTile(
                      icon: Icons.help_outline,
                      label: 'Help Center',
                      onTap: () => context.go('/app/help'),
                      showDivider: false,
                    ),
                  ]),
                  SizedBox(height: 20),
                  // Logout
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Logout'),
                          content: Text('Are you sure you want to logout?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  await context.read<AuthProvider>().logout();
                                } catch (_) {
                                  // continue to login screen regardless
                                }
                                if (context.mounted) {
                                  context.go('/login');
                                }
                              },
                              child: Text(
                                'Logout',
                                style: TextStyle(color: AppTheme.danger),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: AppTheme.danger, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'MediHive $_appVersion',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Healthcare Management System',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: EdgeInsets.only(left: 4, bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _group(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppTheme.cardShadow,
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _buildGoogleDriveSection(SettingsProvider settings) {
    if (settings.isGoogleSigningIn) {
      return Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 12),
              Text(
                settings.isSyncing
                    ? 'Syncing data...'
                    : 'Connecting to Google Drive...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = settings.googleUser;
    final hasError = settings.googleAuthError != null;

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
        border: hasError
            ? Border.all(
                color: AppTheme.danger.withValues(alpha: 0.5),
                width: 1.5,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.cloud_sync,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Drive Sync',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      user != null
                          ? 'Cloud Backup Active'
                          : 'Keep your clinic data secure',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (user != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: AppTheme.success, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Connected',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (hasError) ...[
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.danger,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      settings.googleAuthError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 16),
          if (user == null) ...[
            Text(
              'Connect your Google Drive to enable automated cloud backups. This ensures your patient records and OPD records are backed up securely and can be restored at any time.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await settings.signInGoogle();
                    if (!context.mounted) return;
                    if (settings.googleAuthError != null) {
                      _showToast(
                        'Google Sign-In failed: ${settings.googleAuthError}',
                        isError: true,
                      );
                    } else {
                      _showToast('Google Drive connected successfully!');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      _showToast('Google Sign-In failed: $e', isError: true);
                    }
                  }
                },
                icon: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    'https://ssl.gstatic.com/images/branding/googleg/2x/googleg_standard_color_48dp.png',
                    height: 20,
                    width: 20,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) =>
                        loadingProgress == null
                            ? child
                            : const SizedBox(width: 20, height: 20),
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.login, size: 20),
                  ),
                ),
                label: Text(
                  'Connect Google Drive for Backup',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.textOnPrimary,
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  backgroundColor: AppTheme.surfaceVariant,
                  onBackgroundImageError: (_, __) {},
                  child: user.photoUrl == null
                      ? Text(
                          user.displayName?.isNotEmpty == true
                              ? user.displayName![0].toUpperCase()
                              : 'G',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        )
                      : null,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'Google User',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        user.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Last Sync Time',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    settings.lastSyncTime,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await settings.triggerSync();
                        if (!context.mounted) return;
                        if (settings.googleAuthError != null) {
                          _showToast(settings.googleAuthError!, isError: true);
                        } else {
                          _showToast('Backup synchronised successfully!');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _showToast('Sync failed: $e', isError: true);
                        }
                      }
                    },
                    icon: Icon(Icons.sync, size: 18),
                    label: Text(
                      'Sync Now',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(color: AppTheme.primary, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await settings.signOutGoogle();
                        if (context.mounted) {
                          _showToast('Google Drive disconnected.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          _showToast('Failed to disconnect: $e', isError: true);
                        }
                      }
                    },
                    icon: Icon(Icons.power_settings_new, size: 18),
                    label: Text(
                      'Disconnect',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: BorderSide(color: AppTheme.danger, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
