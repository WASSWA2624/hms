import 'package:flutter_test/flutter_test.dart';
import 'package:hosspi_hms/core/realtime/realtime_event_groups.dart';
import 'package:hosspi_hms/core/realtime/realtime_events.dart';

void main() {
  group('RealtimeEventGroups', () {
    test('exposes patient registry invalidation events', () {
      expect(RealtimeEvents.patientCreated, 'patient.created');
      expect(
        RealtimeEventGroups.patientRegistry,
        contains(RealtimeEvents.patientCreated),
      );
      expect(
        RealtimeEventGroups.patientRegistry,
        contains(RealtimeEvents.patientUpdated),
      );
      expect(
        RealtimeEventGroups.patientRegistry,
        contains(RealtimeEvents.patientDeleted),
      );
      expect(
        RealtimeEventGroups.patients,
        contains(RealtimeEvents.patientRestored),
      );
      expect(
        RealtimeEventGroups.patients,
        contains(RealtimeEvents.patientPermanentlyDeleted),
      );
      expect(
        RealtimeEventGroups.patientRegistry,
        contains(RealtimeEvents.patientRestored),
      );
      expect(
        RealtimeEventGroups.patientRegistry,
        contains(RealtimeEvents.patientPermanentlyDeleted),
      );
    });

    test('routes encounter and visit queue events to OPD workspace', () {
      expect(
        RealtimeEventGroups.opdFlow,
        contains(RealtimeEvents.encounterCreated),
      );
      expect(
        RealtimeEventGroups.opdFlow,
        contains(RealtimeEvents.encounterUpdated),
      );
      expect(
        RealtimeEventGroups.opdFlow,
        contains(RealtimeEvents.visitQueueCreated),
      );
      expect(
        RealtimeEventGroups.opdFlow,
        contains(RealtimeEvents.visitQueuePositionChanged),
      );
    });

    test(
      'routes payment, invoice, and balance events to billing workspace',
      () {
        expect(RealtimeEvents.paymentReconciled, 'payment.reconciled');
        expect(
          RealtimeEventGroups.billingWorkspace,
          contains(RealtimeEvents.paymentCreated),
        );
        expect(
          RealtimeEventGroups.billingWorkspace,
          contains(RealtimeEvents.paymentReconciled),
        );
        expect(
          RealtimeEventGroups.billingWorkspace,
          contains(RealtimeEvents.invoiceUpdated),
        );
        expect(
          RealtimeEventGroups.billingWorkspace,
          contains(RealtimeEvents.billingBalanceUpdated),
        );
      },
    );

    test('billing workspace also refreshes on clinical/OPD charge events', () {
      // Invoices/payments are frequently created by these workflows, so the
      // billing workspace must react to them, not only to billing events.
      expect(
        RealtimeEventGroups.billingWorkspace,
        contains(RealtimeEvents.opdFlowUpdated),
      );
      expect(
        RealtimeEventGroups.billingWorkspace,
        contains(RealtimeEvents.labWorkflowUpdated),
      );
      expect(
        RealtimeEventGroups.billingWorkspace,
        contains(RealtimeEvents.radiologyWorkflowUpdated),
      );
      expect(
        RealtimeEventGroups.billingWorkspace,
        contains(RealtimeEvents.pharmacyOrderUpdated),
      );
    });

    test('radiology group includes catalog updates', () {
      expect(
        RealtimeEventGroups.radiology,
        contains(RealtimeEvents.radiologyCatalogUpdated),
      );
    });

    test('every billing-consuming workspace reacts to billing events', () {
      // A payment/refund/adjustment recorded anywhere must update these
      // workspaces in real time.
      for (final Set<String> group in <Set<String>>[
        RealtimeEventGroups.radiology,
        RealtimeEventGroups.icu,
        RealtimeEventGroups.theater,
        RealtimeEventGroups.emergencyWorkspace,
        RealtimeEventGroups.lab,
        RealtimeEventGroups.pharmacyWorkspace,
        RealtimeEventGroups.opd,
        RealtimeEventGroups.ipd,
        RealtimeEventGroups.nursing,
        RealtimeEventGroups.claims,
        RealtimeEventGroups.discharge,
        RealtimeEventGroups.mortuary,
      ]) {
        expect(group, contains(RealtimeEvents.billingPaymentReceived));
        expect(group, contains(RealtimeEvents.billingBalanceUpdated));
        expect(group, contains(RealtimeEvents.invoiceUpdated));
      }
    });

    test('routes platform admin events for dashboard sync', () {
      expect(
        RealtimeEventGroups.platformAdmin,
        contains(RealtimeEvents.tenantCreated),
      );
      expect(
        RealtimeEventGroups.platformAdmin,
        contains(RealtimeEvents.facilityCreated),
      );
      expect(
        RealtimeEventGroups.accessAdmin,
        contains(RealtimeEvents.userCreated),
      );
    });
  });
}
