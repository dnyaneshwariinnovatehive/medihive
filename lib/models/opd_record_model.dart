import 'package:hive/hive.dart';

part 'opd_record_model.g.dart';

@HiveType(typeId: 1)
class OPDRecordModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String patientId;

  @HiveField(2)
  final String type;

  @HiveField(3)
  final String symptoms;

  @HiveField(4)
  final String diagnosis;

  @HiveField(5)
  final String medicines;

  @HiveField(6)
  final DateTime visitDate;

  @HiveField(7)
  final bool isDraft;

  @HiveField(8)
  final bool isSynced;

  @HiveField(9)
  final DateTime createdAt;

  @HiveField(10)
  final DateTime updatedAt;

  @HiveField(11)
  final String clinicalNotes;

  @HiveField(12)
  final String consultationFee;

  @HiveField(13)
  final String medicineFee;

  @HiveField(14)
  final String discount;

  @HiveField(15)
  final String paymentMode;

  @HiveField(16)
  final String chargeType;

  @HiveField(17)
  final String previousVisitDate;

  @HiveField(18)
  final String followUpReason;

  @HiveField(19)
  final String nextVisit;

  @HiveField(20)
  final String bloodGroup;

  @HiveField(21)
  final String panchakarmaNotes;

  OPDRecordModel({
    required this.id,
    required this.patientId,
    required this.type,
    required this.symptoms,
    required this.diagnosis,
    required this.medicines,
    required this.visitDate,
    required this.isDraft,
    required this.isSynced,
    required this.createdAt,
    required this.updatedAt,
    this.clinicalNotes = '',
    this.consultationFee = '',
    this.medicineFee = '',
    this.discount = '',
    this.paymentMode = '',
    this.chargeType = '',
    this.previousVisitDate = '',
    this.followUpReason = '',
    this.nextVisit = '',
    this.bloodGroup = '',
    this.panchakarmaNotes = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'patient_id': patientId,
    'opd_type': type,
    'symptoms': symptoms,
    'diagnosis': diagnosis,
    'medicines': medicines,
    'visit_datetime': visitDate.toIso8601String(),
    'clinical_notes': clinicalNotes,
    'consultation_fee': consultationFee,
    'medicine_fee': medicineFee,
    'discount_value': discount,
    'payment_mode': paymentMode,
    'charge_type': chargeType,
    'previous_visit_date': previousVisitDate,
    'followup_status': followUpReason,
    'next_visit_date': nextVisit,
    'blood_group': bloodGroup,
    'panchakarma_notes': panchakarmaNotes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'is_synced': isSynced ? 1 : 0,
  };

  factory OPDRecordModel.fromJson(Map<String, dynamic> json) => OPDRecordModel(
    id: json['id']?.toString() ?? '',
    patientId: json['patient_id']?.toString() ?? '',
    type: json['opd_type']?.toString() ?? 'consultation',
    symptoms: json['symptoms']?.toString() ?? '',
    diagnosis: json['diagnosis']?.toString() ?? '',
    medicines: json['medicines']?.toString() ?? '',
    visitDate: DateTime.tryParse(json['visit_datetime']?.toString() ?? '') ?? DateTime.now(),
    isDraft: false,
    isSynced: json['is_synced'] == true || json['is_synced'] == 1,
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    clinicalNotes: json['clinical_notes']?.toString() ?? '',
    consultationFee: json['consultation_fee']?.toString() ?? '',
    medicineFee: json['medicine_fee']?.toString() ?? '',
    discount: json['discount_value']?.toString() ?? '',
    paymentMode: json['payment_mode']?.toString() ?? '',
    chargeType: json['charge_type']?.toString() ?? '',
    previousVisitDate: json['previous_visit_date']?.toString() ?? '',
    followUpReason: json['followup_status']?.toString() ?? '',
    nextVisit: json['next_visit_date']?.toString() ?? '',
    bloodGroup: json['blood_group']?.toString() ?? '',
    panchakarmaNotes: json['panchakarma_notes']?.toString() ?? '',
  );

  OPDRecordModel copyWith({
    String? id,
    String? patientId,
    String? type,
    String? symptoms,
    String? diagnosis,
    String? medicines,
    DateTime? visitDate,
    bool? isDraft,
    bool? isSynced,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? clinicalNotes,
    String? consultationFee,
    String? medicineFee,
    String? discount,
    String? paymentMode,
    String? chargeType,
    String? previousVisitDate,
    String? followUpReason,
    String? nextVisit,
    String? bloodGroup,
    String? panchakarmaNotes,
  }) {
    return OPDRecordModel(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      type: type ?? this.type,
      symptoms: symptoms ?? this.symptoms,
      diagnosis: diagnosis ?? this.diagnosis,
      medicines: medicines ?? this.medicines,
      visitDate: visitDate ?? this.visitDate,
      isDraft: isDraft ?? this.isDraft,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      clinicalNotes: clinicalNotes ?? this.clinicalNotes,
      consultationFee: consultationFee ?? this.consultationFee,
      medicineFee: medicineFee ?? this.medicineFee,
      discount: discount ?? this.discount,
      paymentMode: paymentMode ?? this.paymentMode,
      chargeType: chargeType ?? this.chargeType,
      previousVisitDate: previousVisitDate ?? this.previousVisitDate,
      followUpReason: followUpReason ?? this.followUpReason,
      nextVisit: nextVisit ?? this.nextVisit,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      panchakarmaNotes: panchakarmaNotes ?? this.panchakarmaNotes,
    );
  }
}
