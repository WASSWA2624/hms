import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/app/printing/print_form_template_context.dart';
import 'package:hosspi_hms/core/realtime/realtime_events.dart';
import 'package:hosspi_hms/core/realtime/realtime_message.dart';
import 'package:hosspi_hms/core/security/auth_session.dart';
import 'package:hosspi_hms/core/security/session_tokens.dart';
import 'package:hosspi_hms/features/tenant_facility/domain/entities/tenant_facility_setup.dart';
import 'package:hosspi_hms/shared/printing/printing.dart';
import 'package:hosspi_hms/shared/reporting/report_section_selection.dart';

void main() {
  test('builds facility header details with profile fallbacks', () {
    final PrintFormBranding? branding = buildFacilityPrintBranding(
      setup: const FacilitySetupSnapshot(
        facility: FacilityProfile(
          id: 'facility-1',
          tenantId: 'tenant-1',
          name: 'DemoCare General Hospital',
          type: FacilitySetupType.hospital,
          phone: '+2567001000',
          email: 'info@democare.ug',
          addressLine1: '1 Demo Hospital Avenue',
          city: 'Kampala',
          country: 'Uganda',
          displayId: 'FAC0001',
        ),
      ),
      session: null,
      apiBaseUrl: Uri.parse('https://api.example.com'),
    );

    expect(branding, isNotNull);
    expect(branding!.contacts, <String>[
      'Phone: +2567001000',
      'Email: info@democare.ug',
    ]);
    expect(branding.addressLines, <String>[
      '1 Demo Hospital Avenue, Kampala, Uganda',
    ]);
    expect(branding.details, <String>[
      'Type: Hospital',
      'Facility ID: FAC0001',
    ]);
  });

  test('prefers configured contact address over profile values', () {
    final PrintFormBranding? branding = buildFacilityPrintBranding(
      setup: const FacilitySetupSnapshot(
        facility: FacilityProfile(
          id: 'facility-1',
          tenantId: 'tenant-1',
          name: 'DemoCare General Hospital',
          type: FacilitySetupType.hospital,
          phone: 'profile-phone',
          city: 'Profile City',
        ),
        contactAddress: FacilityContactAddress(
          phone: 'configured-phone',
          city: 'Configured City',
        ),
      ),
      session: null,
      apiBaseUrl: Uri.parse('https://api.example.com'),
    );

    expect(branding!.contacts, <String>['Phone: configured-phone']);
    expect(branding.addressLines, <String>['Configured City']);
  });

  test('prints tenant contacts for a facility without its own', () {
    final PrintFormBranding? branding = buildFacilityPrintBranding(
      setup: const FacilitySetupSnapshot(
        tenant: TenantProfile(
          id: 'TEN0001',
          name: 'DemoCare',
          contactPhone: '+256700000100',
          contactEmail: 'desk@democare.ug',
        ),
        facility: FacilityProfile(
          id: 'facility-1',
          tenantId: 'tenant-1',
          name: 'DemoCare General Hospital',
          type: FacilitySetupType.hospital,
        ),
        effectiveContact: FacilityEffectiveContact(
          phone: '+256700000100',
          email: 'desk@democare.ug',
          phoneSource: FacilityContactSource.tenant,
          emailSource: FacilityContactSource.tenant,
        ),
      ),
      session: null,
      apiBaseUrl: Uri.parse('https://api.example.com'),
    );

    expect(branding!.contacts, <String>[
      'Phone: +256700000100',
      'Email: desk@democare.ug',
    ]);
  });

  test('prints the facility own phone and inherits only the missing email', () {
    final PrintFormBranding? branding = buildFacilityPrintBranding(
      setup: const FacilitySetupSnapshot(
        tenant: TenantProfile(
          id: 'TEN0001',
          name: 'DemoCare',
          contactPhone: '+256700000100',
          contactEmail: 'desk@democare.ug',
        ),
        facility: FacilityProfile(
          id: 'facility-1',
          tenantId: 'tenant-1',
          name: 'DemoCare General Hospital',
          type: FacilitySetupType.hospital,
        ),
        contactAddress: FacilityContactAddress(phone: '+256700000200'),
      ),
      session: null,
      apiBaseUrl: Uri.parse('https://api.example.com'),
    );

    expect(branding!.contacts, <String>[
      'Phone: +256700000200',
      'Email: desk@democare.ug',
    ]);
  });

  test('reloads print setup only for tenant/facility updates that match', () {
    const FacilitySetupSnapshot setup = FacilitySetupSnapshot(
      tenant: TenantProfile(
        id: 'TEN0001',
        name: 'DemoCare',
        resourceUuid: 'tenant-uuid',
      ),
      facility: FacilityProfile(
        id: 'FAC0001',
        tenantId: 'TEN0001',
        name: 'DemoCare General Hospital',
        type: FacilitySetupType.hospital,
        resourceUuid: 'facility-uuid',
      ),
    );
    bool matches(String event, Map<String, Object?> payload) =>
        printSetupMatchesRealtimeEvent(
          RealtimeMessage(event: event, payload: payload),
          setup: setup,
        );

    expect(
      matches(RealtimeEvents.tenantUpdated, <String, Object?>{
        'tenant_id': 'tenant-uuid',
      }),
      isTrue,
    );
    expect(
      matches(RealtimeEvents.tenantUpdated, <String, Object?>{
        'tenant_id': 'other-tenant',
      }),
      isFalse,
    );
    // Platform-scoped tenant events carry no tenant id.
    expect(
      matches(RealtimeEvents.tenantUpdated, <String, Object?>{
        'tenant_id': null,
      }),
      isTrue,
    );
    expect(
      matches(RealtimeEvents.facilityUpdated, <String, Object?>{
        'facility_id': 'facility-uuid',
      }),
      isTrue,
    );
    expect(
      matches(RealtimeEvents.facilityUpdated, <String, Object?>{
        'facility_id': 'other-facility',
      }),
      isFalse,
    );
  });

  test('falls back to session facility type when setup facility is missing', () {
    final PrintFormBranding? branding = buildFacilityPrintBranding(
      setup: null,
      session: AuthSession(
        tokens: SessionTokens(accessToken: 'token'),
        user: const AuthUserProfile(
          facilityName: 'DemoCare General Hospital',
          facilityType: 'HOSPITAL',
        ),
      ),
      apiBaseUrl: Uri.parse('https://api.example.com'),
    );

    expect(branding, isNotNull);
    expect(branding!.name, 'DemoCare General Hospital');
    expect(branding.details, <String>['Type: Hospital']);
  });

  testWidgets('falls back to app branding when facility is unavailable', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Patient statement',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
                logoUrl: 'assets/logos/logo.png',
                contacts: <String>['Email: admin@example.com'],
              ),
              facilityBranding: const PrintFormBranding(
                name: 'Inactive Facility',
                kind: PrintFormBrandingKind.facility,
                isSubscribed: false,
              ),
              bodyHtml: '<p>Body</p>',
              printedAt: DateTime.utc(2026, 1, 2, 3, 4),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('HOSSPI'));
    expect(html, contains('Email: admin@example.com'));
    expect(html, isNot(contains('Inactive Facility')));
    expect(html, contains('Patient statement'));
    expect(
      html,
      isNot(
        contains(
          '<main class="print-template-document print-template-document--paged">',
        ),
      ),
    );
    expect(html, isNot(contains('counter(pages)')));
  });

  testWidgets('renders explicit multi-page numbering', (tester) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Patient report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              facilityBranding: const PrintFormBranding(
                name: 'Subscribed Facility',
                kind: PrintFormBrandingKind.facility,
              ),
              patientContext: const PrintFormPatientContext(
                patientNameLabel: 'Patient name',
                patientName: 'Jane Doe',
                patientIdLabel: 'Patient ID',
                patientId: 'PAT0000001',
              ),
              pages: const <PrintFormPage>[
                PrintFormPage(bodyHtml: '<p>First</p>'),
                PrintFormPage(bodyHtml: '<p>Second</p>'),
              ],
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('Subscribed Facility'));
    expect(_occurrences(html, '<strong>Subscribed Facility</strong>'), 1);
    expect(html, contains('Jane Doe'));
    expect(html, contains('PAT0000001'));
    expect(html, contains('print-template-compact-header'));
    expect(html, contains('Page 1 of 2'));
    expect(html, contains('Page 2 of 2'));
  });

  testWidgets('renders signatures only on the last page', (tester) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Laboratory result report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              patientContext: const PrintFormPatientContext(
                patientNameLabel: 'Patient name',
                patientName: 'Joshua Evans',
                patientIdLabel: 'Patient ID',
                patientId: 'PAT0000002',
                encounterIdLabel: 'Encounter ID',
                encounterId: 'ENC0000002',
              ),
              contextReference: const PrintFormContextReference(
                label: 'Lab order',
                value: 'LAB0000006',
              ),
              signatures: const PrintFormSignatures(
                printedByLabel: 'Printed by',
                verifiedByLabel: 'Verified by',
                printedByName: 'Lab Tech',
                signatureStampLabel: 'Signature / stamp',
              ),
              printedAt: DateTime(2026, 7, 4, 16, 1),
              pages: const <PrintFormPage>[
                PrintFormPage(bodyHtml: '<p>First page</p>'),
                PrintFormPage(bodyHtml: '<p>Second page</p>'),
              ],
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('print-template-patient-inline'));
    expect(html, contains('Patient name: Joshua Evans'));
    expect(html, contains('print-template-title-meta'));
    expect(html, contains('Lab order: LAB0000006'));
    expect(html, contains('Printed on:'));
    expect(html, contains('Printed at:'));
    expect(html, isNot(contains('<div class="print-template-kv-item">')));
    expect(html, contains('Printed by'));
    expect(html, contains('Lab Tech'));
    expect(_occurrences(html, '<div class="print-template-signatures">'), 1);
  });

  testWidgets('renders facility header with address before contacts', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Laboratory result report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              facilityBranding: const PrintFormBranding(
                name: 'DemoCare General Hospital',
                kind: PrintFormBrandingKind.facility,
                contacts: <String>[
                  'Phone: +2567001000',
                  'Email: info@democare.ug',
                ],
                addressLines: <String>[
                  '1 Demo Hospital Avenue, Kampala, Uganda',
                ],
              ),
              patientContext: const PrintFormPatientContext(
                patientNameLabel: 'Patient name',
                patientName: 'Joshua Suuna',
              ),
              bodyHtml: '<p>Results</p>',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('DemoCare General Hospital'));
    expect(html, contains('1 Demo Hospital Avenue, Kampala, Uganda'));
    expect(html, contains('Phone: +2567001000, Email: info@democare.ug'));
    expect(html, isNot(contains('Type:')));
    expect(html, isNot(contains('Tenant:')));
  });

  testWidgets('filters facility header fields by branding options', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Laboratory result report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              facilityBranding: const PrintFormBranding(
                name: 'DemoCare General Hospital',
                kind: PrintFormBrandingKind.facility,
                contacts: <String>[
                  'Phone: +2567001000',
                  'Email: info@democare.ug',
                ],
                addressLines: <String>[
                  '1 Demo Hospital Avenue, Kampala, Uganda',
                ],
                details: <String>[
                  'Type: Hospital',
                  'Facility ID: FAC0001',
                ],
              ),
              brandingOptions: const PrintFormBrandingOptions(
                includeBrand: true,
                includeAddress: true,
                includePhone: true,
                includeEmail: false,
                includeFacilityType: false,
                includeFacilityId: true,
              ),
              bodyHtml: '<p>Results</p>',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('DemoCare General Hospital'));
    expect(html, contains('1 Demo Hospital Avenue, Kampala, Uganda'));
    expect(html, contains('Phone: +2567001000'));
    expect(html, isNot(contains('Email: info@democare.ug')));
    expect(html, contains('Facility ID: FAC0001'));
    expect(html, isNot(contains('Type: Hospital')));
  });

  test('builds facility section availabilities from branding fields', () {
    final List<ReportSectionAvailability> sections =
        buildFacilityPrintSectionAvailabilities(
      const PrintFormBranding(
        name: 'DemoCare General Hospital',
        kind: PrintFormBrandingKind.facility,
        contacts: <String>[
          'Phone: +2567001000',
          'Email: info@democare.ug',
        ],
        addressLines: <String>['Kampala, Uganda'],
        details: <String>['Type: Hospital', 'Facility ID: FAC0001'],
      ),
    );

    expect(
      sections.map((ReportSectionAvailability s) => s.id).toList(),
      <Object>[
        PrintFacilitySection.brand,
        PrintFacilitySection.address,
        PrintFacilitySection.phone,
        PrintFacilitySection.email,
        PrintFacilitySection.facilityType,
        PrintFacilitySection.facilityId,
      ],
    );
    expect(sections.every((ReportSectionAvailability s) => s.enabled), isTrue);
    expect(
      brandingOptionsFromFacilitySections(<Object>{
        PrintFacilitySection.brand,
        PrintFacilitySection.phone,
      }).includeEmail,
      isFalse,
    );
  });

  testWidgets('anchors signature footer and reserves name space', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Laboratory result report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              patientContext: const PrintFormPatientContext(
                patientNameLabel: 'Patient name',
                patientName: 'Joshua Suuna',
              ),
              signatures: const PrintFormSignatures(
                printedByLabel: 'Printed by',
                verifiedByLabel: 'Verified by',
                printedByName: 'Platform Demo',
                signatureStampLabel: 'Signature / stamp',
              ),
              footerNote: 'Generated from laboratory workflow data.',
              bodyHtml: '<p>Short results</p>',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('print-template-page--anchored-footer'));
    expect(html, contains('print-template-page-bottom'));
    expect(
      _occurrences(html, '<div class="print-template-signature-name">'),
      2,
    );
    expect(
      html,
      contains(
        '<div class="print-template-signature-name">Platform Demo</div>',
      ),
    );
    expect(html, contains('<div class="print-template-signature-name"></div>'));
    expect(html, contains('Generated from laboratory workflow data.'));
  });

  testWidgets('renders signature name slots when both names are empty', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Laboratory result report',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              signatures: const PrintFormSignatures(
                printedByLabel: 'Printed by',
                verifiedByLabel: 'Verified by',
                signatureStampLabel: 'Signature / stamp',
              ),
              bodyHtml: '<p>Short results</p>',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      _occurrences(html, '<div class="print-template-signature-name"></div>'),
      2,
    );
  });

  testWidgets('drops empty explicit pages instead of printing blanks', (
    tester,
  ) async {
    late String html;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            html = PrintFormTemplate.build(
              context: context,
              title: 'Consultation summary',
              appBranding: const PrintFormBranding(
                name: 'HOSSPI',
                kind: PrintFormBrandingKind.app,
              ),
              pages: const <PrintFormPage>[
                PrintFormPage(bodyHtml: '<p>Clinical notes</p>'),
                PrintFormPage(bodyHtml: '<style>.x{color:red;}</style>'),
              ],
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(html, contains('Clinical notes'));
    expect(html, isNot(contains('Page 1 of 2')));
    expect(html, isNot(contains('Page 2 of 2')));
  });
}

int _occurrences(String source, String pattern) {
  return pattern.allMatches(source).length;
}
