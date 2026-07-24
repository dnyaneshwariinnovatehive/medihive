class Helpers {
  /// Safely convert a dynamic value (String or int) to int.
  /// Handles old SQLite databases where INTEGER columns were stored as TEXT.
  static int toInt(dynamic value, [int defaultValue = 0]) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Calculate age from date of birth string (YYYY-MM-DD)
  static int calculateAge(String dobString) {
    final dob = DateTime.tryParse(dobString);
    if (dob == null) return 0;
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  /// Format currency in Indian Rupee format
  static String formatCurrency(num amount) {
    return '₹${amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{2})+(\d{3})(?!\d))'),
          (m) => '${m[1]},',
        )}';
  }

  /// Normalize phone number to 10 digits (strips non-digits, removes leading 0/91).
  /// Returns the clean 10-digit number or empty string if invalid.
  static String normalizePhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('91') && cleaned.length == 12) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0') && cleaned.length == 11) {
      cleaned = cleaned.substring(1);
    }
    return cleaned.length == 10 ? cleaned : '';
  }
}
