class Medicine {
  final String name;
  final String dosage;
  final String duration;

  const Medicine({
    required this.name,
    required this.dosage,
    required this.duration,
  });
}

class Prescription {
  final String date;
  final String patientName;
  final String patientId;
  final int age;
  final String gender;
  final String diagnosis;
  final List<Medicine> medicines;
  final String notes;
  final String panchakarmaNotes;
  final String nextVisit;
  final String doctorName;
  final String doctorQualification;
  final String clinicName;
  final String clinicAddress;
  final String clinicPhone;
  final String licenseNo;
  final String patientMobile;
  final String clinicLogoPath;

  const Prescription({
    required this.date,
    required this.patientName,
    required this.patientId,
    required this.age,
    required this.gender,
    required this.diagnosis,
    required this.medicines,
    required this.notes,
    this.panchakarmaNotes = '',
    required this.nextVisit,
    required this.doctorName,
    this.doctorQualification = '',
    required this.clinicName,
    required this.clinicAddress,
    required this.clinicPhone,
    required this.licenseNo,
    this.patientMobile = '',
    this.clinicLogoPath = '',
  });
}
