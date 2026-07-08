import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/prescription.dart';

class PrescriptionPdfService {
  static Future<Uint8List> generatePdf(Prescription rx,
      {bool includePatientDetails = true}) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(rx),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 1.5, color: PdfColors.blueGrey800),
              pw.SizedBox(height: 20),

              if (includePatientDetails) ...[
                _buildPatientInfo(rx),
                pw.SizedBox(height: 20),
              ],

              _buildSection('Diagnosis', rx.diagnosis, withBorder: false),
              pw.SizedBox(height: 16),

              _buildBorderedSection('Clinical Notes', rx.notes),
              pw.SizedBox(height: 16),

              if (rx.panchakarmaNotes.isNotEmpty) ...[
                _buildBorderedSection('Panchakarma Notes',
                    rx.panchakarmaNotes),
                pw.SizedBox(height: 16),
              ],

              _buildMedicinesTable(rx),
              pw.SizedBox(height: 20),

              if (includePatientDetails) ...[
                _buildNextVisit(rx),
                pw.SizedBox(height: 20),
              ],

              _buildFooter(),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildHeader(Prescription rx) {
    pw.Widget logoWidget;
    if (rx.clinicLogoPath.isNotEmpty) {
      try {
        final file = File(rx.clinicLogoPath);
        if (file.existsSync()) {
          logoWidget = pw.Container(
            width: 56,
            height: 56,
            child: pw.Image(pw.MemoryImage(file.readAsBytesSync())),
          );
        } else {
          logoWidget = _defaultLogo();
        }
      } catch (_) {
        logoWidget = _defaultLogo();
      }
    } else {
      logoWidget = _defaultLogo();
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        logoWidget,
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                rx.clinicName,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey800,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${rx.doctorName}${rx.doctorQualification.isNotEmpty ? ', ${rx.doctorQualification}' : ''}',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _defaultLogo() {
    return pw.Container(
      width: 54,
      height: 54,
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey800,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
      ),
      child: pw.Center(
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Container(
              width: 24,
              height: 6,
              color: PdfColors.white,
            ),
            pw.Container(
              width: 6,
              height: 24,
              color: PdfColors.white,
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildPatientInfo(Prescription rx) {
    final infoStyle = pw.TextStyle(fontSize: 11, color: PdfColors.grey800);
    final valueStyle =
        pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold);

    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Row(
                children: [
                  pw.Text('Patient Name: ', style: infoStyle),
                  pw.Expanded(
                    child: pw.Text(rx.patientName, style: valueStyle),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Row(
                children: [
                  pw.Text('Date: ', style: infoStyle),
                  pw.Expanded(
                    child: pw.Text(rx.date, style: valueStyle),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Row(
                children: [
                  pw.Text('Patient ID: ', style: infoStyle),
                  pw.Expanded(
                    child: pw.Text(rx.patientId, style: valueStyle),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Row(
                children: [
                  pw.Text('Age / Gender: ', style: infoStyle),
                  pw.Expanded(
                    child: pw.Text('${rx.age} / ${rx.gender}', style: valueStyle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSection(String title, String content,
      {bool withBorder = false}) {
    final children = <pw.Widget>[
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey800,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        content.isNotEmpty ? content : '-',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
      ),
    ];

    if (withBorder) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  static pw.Widget _buildBorderedSection(String title, String content) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            content.isNotEmpty ? content : '-',
            style: pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMedicinesTable(Prescription rx) {
    final cellStyle = pw.TextStyle(
      fontSize: 11,
      color: PdfColors.grey800,
    );
    final numStyle = pw.TextStyle(
      fontSize: 11,
      color: PdfColors.grey600,
    );
    final headerLabelStyle = pw.TextStyle(
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.grey800,
    );

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: PdfColors.blueGrey800,
            child: pw.Text(
              'Medicinal Prescription',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey300),
              ),
              color: PdfColors.grey100,
            ),
            child: pw.Row(
              children: [
                pw.SizedBox(width: 24),
                pw.Expanded(flex: 1, child: pw.Text('#', style: headerLabelStyle)),
                pw.Expanded(
                  flex: 5,
                  child: pw.Text('Medicine', style: headerLabelStyle),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Text('Dosage', style: headerLabelStyle),
                ),
              ],
            ),
          ),
          if (rx.medicines.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                'No medicines prescribed',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey500,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            )
          else
            ...rx.medicines.asMap().entries.map((entry) {
              final idx = entry.key;
              final med = entry.value;
              final isEven = idx.isOdd;
              return pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: isEven
                    ? pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey200),
                        ),
                        color: PdfColors.grey50,
                      )
                    : pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.grey200),
                        ),
                      ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(
                      width: 24,
                      child: pw.Text('${idx + 1}.', style: numStyle),
                    ),
                    pw.Expanded(
                      flex: 5,
                      child: pw.Text(med.name, style: cellStyle),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(med.dosage, style: cellStyle),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  static pw.Widget _buildNextVisit(Prescription rx) {
    return pw.Row(
      children: [
        pw.Text(
          'Next Visit Date: ',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
          ),
        ),
        pw.Text(
          rx.nextVisit.isNotEmpty ? rx.nextVisit : 'As required',
          style: pw.TextStyle(
            fontSize: 12,
            color: PdfColors.grey800,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Column(
      children: [
        pw.Divider(thickness: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
        pw.Text(
          'This prescription is valid for 30 days from the date of issue.',
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
            fontStyle: pw.FontStyle.italic,
          ),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Please keep this prescription safe for future reference.',
          style: pw.TextStyle(
            fontSize: 10,
            color: PdfColors.grey600,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ],
    );
  }
}
