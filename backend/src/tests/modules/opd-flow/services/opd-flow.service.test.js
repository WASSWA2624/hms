const { HttpError } = require('@lib/errors');

jest.mock('@repositories/opd-flow/opd-flow.repository');
jest.mock('@lib/audit');
jest.mock('@services/ipd-flow/ipd-flow.service', () => ({
  emitAdmissionRefreshEvent: jest.fn().mockResolvedValue(null)
}));
jest.mock(
  '@services/clinical-alert-threshold/clinical-alert-threshold.service',
  () => ({
    evaluateVitalAndCreateAlerts: jest.fn().mockResolvedValue(null)
  })
);
jest.mock('@lib/websocket', () => ({
  emitToUser: jest.fn(),
  emitToUsers: jest.fn(),
  publishDomainEvent: jest.fn(),
  OPD_EVENTS: {
    OPD_FLOW_UPDATED: 'opd.flow.updated'
  },
  NOTIFICATION_EVENTS: {
    NOTIFICATION_CREATED: 'notification.created'
  },
  BILLING_EVENTS: {
    BILLING_INVOICE_ISSUED: 'billing.invoice_issued',
    INVOICE_UPDATED: 'invoice.updated',
    BILLING_BALANCE_UPDATED: 'billing.balance_updated'
  }
}));
jest.mock('@lib/billing/realtime', () => ({
  publishIssuedInvoiceBillingEvents: jest.fn(async () => {}),
  publishUpdatedInvoiceBillingEvents: jest.fn(async () => {}),
  publishBillingRealtimeUpdate: jest.fn(async () => {})
}));
jest.mock('@prisma/client', () => ({
  $transaction: jest.fn(),
  assignFriendlyIdIfMissing: jest.fn(async () => {}),
  tenant: {
    findFirst: jest.fn()
  },
  facility: {
    findFirst: jest.fn()
  },
  patient: {
    findFirst: jest.fn()
  },
  user: {
    findFirst: jest.fn()
  },
  invoice: {
    findMany: jest.fn(),
    findFirst: jest.fn()
  },
  payment: {
    findMany: jest.fn()
  },
  user_role: {
    findMany: jest.fn()
  },
  notification: {
    create: jest.fn()
  },
  notification_delivery: {
    createMany: jest.fn()
  }
}));

const opdFlowRepository = require('@repositories/opd-flow/opd-flow.repository');
const prisma = require('@prisma/client');
const { createAuditLog } = require('@lib/audit');
const ipdFlowService = require('@services/ipd-flow/ipd-flow.service');
const { emitToUser, emitToUsers } = require('@lib/websocket');
const opdFlowService = require('@services/opd-flow/opd-flow.service');

describe('opd-flow.service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValue(null);
    prisma.tenant.findFirst.mockResolvedValue(null);
    prisma.facility.findFirst.mockResolvedValue(null);
    prisma.patient.findFirst.mockResolvedValue(null);
    prisma.user.findFirst.mockResolvedValue(null);
    prisma.invoice.findMany.mockResolvedValue([]);
    prisma.payment.findMany.mockResolvedValue([]);
    createAuditLog.mockResolvedValue({});
    ipdFlowService.emitAdmissionRefreshEvent.mockResolvedValue(null);
    prisma.user_role.findMany.mockResolvedValue([]);
    prisma.notification.create.mockImplementation(async ({ data }) => ({
      id: `notif-${data.user_id}`,
      tenant_id: data.tenant_id,
      user_id: data.user_id,
      notification_type: data.notification_type,
      priority: data.priority,
      title: data.title,
      message: data.message,
      read_at: null,
      created_at: new Date(),
      updated_at: new Date()
    }));
    prisma.notification_delivery.createMany.mockResolvedValue({ count: 0 });
  });

  it('lists OPD flows with pagination', async () => {
    prisma.tenant.findFirst.mockResolvedValue({ id: 'TENANT-1' });
    opdFlowRepository.findMany.mockResolvedValue([
      {
        id: 'enc-1',
        extension_json: {
          opd_flow: {
            stage: 'WAITING_VITALS'
          }
        }
      }
    ]);
    opdFlowRepository.count.mockResolvedValue(1);

    const result = await opdFlowService.listOpdFlows(
      { tenant_id: 'tenant-1' },
      1,
      20,
      'started_at',
      'desc'
    );

    expect(opdFlowRepository.findMany).toHaveBeenCalled();
    expect(result.items).toHaveLength(1);
    expect(result.items[0].flow.stage).toBe('WAITING_VITALS');
    expect(result.pagination.total).toBe(1);
  });

  it('lists OPD flows with canonical paid consultation amounts from invoice payments', async () => {
    opdFlowRepository.findMany.mockResolvedValue([
      {
        id: 'enc-1',
        extension_json: {
          opd_flow: {
            stage: 'WAITING_VITALS',
            consultation: {
              require_payment: true,
              is_paid: true,
              invoice_id: 'inv-1',
              payment_id: null,
              consultation_fee: '20000',
              currency: 'UGX'
            }
          }
        }
      }
    ]);
    opdFlowRepository.count.mockResolvedValue(1);
    prisma.invoice.findMany.mockResolvedValue([
      {
        id: 'inv-1',
        human_friendly_id: 'INV000001',
        total_amount: '20000',
        currency: 'UGX',
        billing_status: 'PAID',
        status: 'PAID',
        payments: [
          {
            id: 'pay-1',
            status: 'COMPLETED',
            amount: '20000',
            deleted_at: null
          }
        ]
      }
    ]);

    const result = await opdFlowService.listOpdFlows(
      {},
      1,
      20,
      'started_at',
      'desc'
    );

    expect(result.items[0].flow.consultation).toEqual(
      expect.objectContaining({
        consultation_fee: '20000',
        paid_amount: '20000.00',
        currency: 'UGX',
        invoice_id: 'INV000001',
        payment_status: 'PAID'
      })
    );
  });

  it('maps human-friendly patient filters when listing OPD flows', async () => {
    prisma.tenant.findFirst.mockResolvedValue({ id: 'TENANT-1' });
    prisma.patient.findFirst.mockResolvedValue({ id: 'PAT0000003' });
    opdFlowRepository.findMany.mockResolvedValue([]);
    opdFlowRepository.count.mockResolvedValue(0);

    await opdFlowService.listOpdFlows(
      {
        tenant_id: 'tenant-1',
        patient_id: 'pat0000003'
      },
      1,
      20,
      'started_at',
      'desc'
    );

    expect(opdFlowRepository.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        tenant_id: 'TENANT-1',
        patient_id: 'PAT0000003'
      }),
      0,
      20,
      { started_at: 'desc' }
    );
  });

  it('starts a walk-in flow and creates patient when patient_id is missing', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'pat-1' })
      },
      invoice: {
        create: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '40.00',
          currency: 'USD'
        }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '40.00',
          currency: 'USD'
        }),
        update: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '40.00',
          currency: 'USD',
          status: 'ISSUED'
        })
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        create: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' }),
        findFirst: jest.fn().mockResolvedValueOnce({
          id: 'enc-1',
          encounter_type: 'OPD',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_CONSULTATION_PAYMENT',
              visit_queue_id: null,
              appointment_id: null,
              consultation: {
                invoice_id: null,
                payment_id: null
              }
            }
          }
        }),
        update: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        tenant_id: 'tenant-1',
        patient_registration: {
          first_name: 'Jane',
          last_name: 'Doe'
        },
        consultation_fee: '40.00'
      },
      { user_id: 'usr-1', tenant_id: 'tenant-1' }
    );

    expect(tx.patient.create).toHaveBeenCalled();
    expect(tx.encounter.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          active_opd_lock_key: 'opd:TENANT-1:GLOBAL:pat-1'
        })
      })
    );
    expect(result.flow.stage).toBe('WAITING_CONSULTATION_PAYMENT');
  });

  it('starts an emergency flow in care-first mode', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' }),
        create: jest.fn()
      },
      invoice: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      emergency_case: {
        create: jest.fn().mockResolvedValue({ id: 'ec-1', severity: 'HIGH' }),
        findFirst: jest.fn().mockResolvedValue({ id: 'ec-1' }),
        update: jest.fn()
      },
      triage_assessment: {
        create: jest.fn().mockResolvedValue({ id: 'tri-1' }),
        findFirst: jest.fn().mockResolvedValue({ id: 'tri-1' })
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      encounter: {
        create: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' }),
        findFirst: jest.fn().mockResolvedValueOnce({
          id: 'enc-1',
          encounter_type: 'EMERGENCY',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_VITALS',
              visit_queue_id: null,
              appointment_id: null,
              emergency_case_id: 'ec-1',
              triage_assessment_id: 'tri-1',
              consultation: {
                invoice_id: null,
                payment_id: null
              }
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        tenant_id: 'tenant-1',
        patient_id: 'pat0000003',
        arrival_mode: 'EMERGENCY',
        emergency: {
          severity: 'HIGH',
          triage_level: 'IMMEDIATE'
        }
      },
      { user_id: 'usr-1', tenant_id: 'tenant-1' }
    );

    expect(tx.patient.findFirst).toHaveBeenCalledWith({
      where: {
        deleted_at: null,
        tenant_id: 'TENANT-1',
        human_friendly_id: 'PAT0000003'
      }
    });
    expect(tx.emergency_case.create).toHaveBeenCalled();
    expect(result.flow.stage).toBe('WAITING_VITALS');
  });

  it('starts an OPD-visible emergency flow for an existing emergency case', async () => {
    const existingEmergencyCase = {
      id: 'ec-existing',
      human_friendly_id: 'EME0000004',
      severity: 'CRITICAL'
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' }),
        create: jest.fn()
      },
      invoice: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(existingEmergencyCase),
        update: jest.fn()
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      encounter: {
        create: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          encounter_type: 'EMERGENCY',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_VITALS',
              visit_queue_id: 'vq-1',
              appointment_id: null,
              emergency_case_id: 'ec-existing',
              triage_assessment_id: null,
              consultation: {
                invoice_id: null,
                payment_id: null
              }
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        tenant_id: 'tenant-1',
        patient_id: 'pat0000004',
        arrival_mode: 'EMERGENCY',
        emergency_case_id: 'EME0000004',
        require_consultation_payment: false,
        create_consultation_invoice: false
      },
      { user_id: 'usr-1', tenant_id: 'tenant-1' }
    );

    expect(tx.emergency_case.findFirst).toHaveBeenCalledWith({
      where: {
        deleted_at: null,
        tenant_id: 'TENANT-1',
        patient_id: 'pat-1',
        human_friendly_id: 'EME0000004'
      }
    });
    expect(tx.emergency_case.create).not.toHaveBeenCalled();
    expect(tx.triage_assessment.create).not.toHaveBeenCalled();
    expect(tx.encounter.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          encounter_type: 'EMERGENCY',
          extension_json: {
            opd_flow: expect.objectContaining({
              emergency_case_id: 'ec-existing',
              stage: 'WAITING_VITALS'
            })
          }
        })
      })
    );
    expect(result.flow.emergency_case_id).toBe('EME0000004');
  });

  it('starts an online appointment flow and moves appointment to IN_PROGRESS', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'apt-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            status: 'CONFIRMED',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1'
          })
          .mockResolvedValueOnce({
            id: 'apt-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            status: 'IN_PROGRESS',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1'
          }),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' }),
        create: jest.fn()
      },
      invoice: {
        create: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '30.00',
          currency: 'USD'
        }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '30.00',
          currency: 'USD'
        })
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        update: jest.fn()
      },
      encounter: {
        create: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' }),
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce({
            id: 'enc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_CONSULTATION_PAYMENT',
                visit_queue_id: 'vq-1',
                appointment_id: 'apt-1',
                consultation: {
                  invoice_id: 'inv-1',
                  payment_id: null
                }
              }
            }
          }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        appointment_id: 'apt-1'
      },
      {
        tenant_id: 'tenant-1',
        user_id: 'usr-1'
      }
    );

    expect(tx.appointment.update).toHaveBeenCalledWith({
      where: { id: 'apt-1' },
      data: { status: 'IN_PROGRESS' }
    });
    expect(tx.visit_queue.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          appointment_id: 'apt-1',
          status: 'IN_PROGRESS'
        })
      })
    );
    expect(result.flow.appointment_id).toBe('apt-1');
  });

  it('returns the existing OPD flow when an appointment is checked in twice', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'apt-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            status: 'CONFIRMED',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1'
          })
          .mockResolvedValueOnce({
            id: 'apt-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            status: 'IN_PROGRESS',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1'
          }),
        update: jest.fn()
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: 'enc-existing-1' })
          .mockResolvedValueOnce({
            id: 'enc-existing-1',
            encounter_type: 'OPD',
            status: 'OPEN',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                appointment_id: 'apt-1'
              }
            }
          })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      { appointment_id: 'apt-1' },
      { tenant_id: 'tenant-1', user_id: 'usr-1' }
    );

    expect(result.encounter.id).toBe('enc-existing-1');
    expect(result.flow.appointment_id).toBe('apt-1');
    expect(tx.appointment.update).not.toHaveBeenCalled();
    expect(tx.encounter.findFirst).toHaveBeenCalledTimes(2);
  });

  it('reconciles queue status when reusing an existing queue-linked OPD flow', async () => {
    const queue = {
      id: 'vq-1',
      human_friendly_id: 'QUE000001',
      patient_id: 'pat-1',
      provider_user_id: 'doc-1',
      status: 'CONFIRMED',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1'
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
visit_queue: {
        findFirst: jest.fn().mockResolvedValue(queue),
        update: jest.fn().mockResolvedValue({
          ...queue,
          status: 'IN_PROGRESS'
        })
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({ id: 'enc-existing-queue-1' })
          .mockResolvedValueOnce({
            id: 'enc-existing-queue-1',
            encounter_type: 'OPD',
            status: 'OPEN',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                visit_queue_id: 'vq-1'
              }
            }
          })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        visit_queue_id: 'QUE000001',
        reuse_open_encounter: true
      },
      { tenant_id: 'tenant-1', user_id: 'usr-1' }
    );

    expect(tx.visit_queue.update).toHaveBeenCalledWith({
      where: { id: 'vq-1' },
      data: { status: 'IN_PROGRESS' }
    });
    expect(result.encounter.id).toBe('enc-existing-queue-1');
    expect(result.flow.visit_queue_id).toBe('QUE000001');
  });

  it('hydrates opd_flow onto an incomplete open encounter when reuse is requested', async () => {
    const incompleteOpenEncounter = {
      id: 'enc-seed-1',
      human_friendly_id: 'ENC-SEED-1',
      encounter_type: 'OPD',
      status: 'OPEN',
      tenant_id: 'TENANT-1',
      facility_id: null,
      patient_id: 'pat-1',
      provider_user_id: null,
      active_opd_lock_key: 'opd:TENANT-1:GLOBAL:pat-1',
      extension_json: {
        seed_pack: 'demo',
        tenant_code: 'DMO'
      }
    };
    const hydratedEncounter = {
      id: 'enc-seed-1',
      human_friendly_id: 'ENC-SEED-1',
      tenant_id: 'TENANT-1',
      encounter_type: 'OPD',
      status: 'OPEN',
      extension_json: {
        seed_pack: 'demo',
        tenant_code: 'DMO',
        opd_flow: {
          stage: 'WAITING_CONSULTATION_PAYMENT',
          visit_queue_id: 'vq-1',
          appointment_id: null,
          consultation: {
            invoice_id: null,
            payment_id: null,
            require_payment: true,
            consultation_fee: '35.00',
            currency: 'USD'
          }
        }
      }
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' }),
        create: jest.fn()
      },
      invoice: {
        create: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '35.00',
          currency: 'USD'
        }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '35.00',
          currency: 'USD',
          payments: []
        }),
        update: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '35.00',
          currency: 'USD',
          status: 'ISSUED'
        })
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      encounter: {
        create: jest.fn(),
        update: jest.fn().mockResolvedValue(hydratedEncounter),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        findFirst: jest.fn().mockResolvedValue(hydratedEncounter)
      }
    };

    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValueOnce(
      incompleteOpenEncounter
    );
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.startOpdFlow(
      {
        tenant_id: 'tenant-1',
        patient_id: 'PAT0000003',
        reuse_open_encounter: true,
        consultation_fee: '35.00',
        require_consultation_payment: true
      },
      { tenant_id: 'tenant-1', user_id: 'usr-1' }
    );

    expect(tx.encounter.create).not.toHaveBeenCalled();
    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'enc-seed-1' },
        data: expect.objectContaining({
          extension_json: expect.objectContaining({
            seed_pack: 'demo',
            opd_flow: expect.objectContaining({
              stage: 'WAITING_CONSULTATION_PAYMENT',
              visit_queue_id: 'vq-1'
            })
          })
        })
      })
    );
    expect(result.encounter.id).toBe('enc-seed-1');
    expect(result.flow.stage).toBe('WAITING_CONSULTATION_PAYMENT');
  });

  it('rejects a new OPD flow when the patient already has an open OPD or emergency encounter', async () => {
    const tx = {
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' })
      }
    };
    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValueOnce({
      id: 'enc-open-1',
      human_friendly_id: 'ENC000009',
      encounter_type: 'EMERGENCY',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_DOCTOR_REVIEW'
        }
      }
    });

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          tenant_id: 'tenant-1',
          patient_id: 'PAT0000003'
        },
        { tenant_id: 'tenant-1', user_id: 'usr-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.active_encounter_exists',
      statusCode: 409
    });
    expect(
      opdFlowRepository.findOpenActiveEncounterForPatient
    ).toHaveBeenCalledWith(
      {
        tenantId: 'TENANT-1',
        facilityId: null,
        patientId: 'pat-1',
        encounterTypes: ['OPD', 'EMERGENCY']
      },
      tx
    );
  });


  it('rejects a new OPD flow when the patient already has an open IPD admission', async () => {
    const tx = {
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' })
      },
      admission: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'adm-1',
          human_friendly_id: 'ADM0000001',
          status: 'ADMITTED'
        })
      }
    };
    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValueOnce(null);
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          tenant_id: 'tenant-1',
          patient_id: 'PAT0000003',
          require_consultation_payment: false
        },
        { tenant_id: 'tenant-1', user_id: 'usr-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.open_admission_exists',
      statusCode: 409
    });
    expect(tx.admission.findFirst).toHaveBeenCalled();
  });

  it('rejects Payment due start when consultation fee cannot produce an invoice', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' })
      },
      invoice: {
        create: jest.fn(),
        findFirst: jest.fn(),
        update: jest.fn()
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      encounter: {
        create: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'TENANT-1',
          facility_id: null,
          patient_id: 'pat-1',
          human_friendly_id: 'ENC000001'
        }),
        findFirst: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn()
      }
    };
    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValue(null);
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          tenant_id: 'tenant-1',
          patient_id: 'PAT0000003',
          consultation_fee: '0',
          require_consultation_payment: false,
          create_consultation_invoice: false,
          initial_stage: 'WAITING_CONSULTATION_PAYMENT'
        },
        { tenant_id: 'tenant-1', user_id: 'usr-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.consultation_invoice_required'
    });
  });

  it('cancels reversible unpaid consultation invoice when the encounter is cancelled', async () => {
    const initialEncounter = {
      id: 'enc-1',
      human_friendly_id: 'ENC000001',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'patient-1',
      status: 'OPEN',
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_CONSULTATION_PAYMENT',
          visit_queue_id: 'queue-1',
          consultation: {
            invoice_id: 'inv-1',
            require_payment: true,
            payment_status: 'PENDING'
          },
          timeline: []
        }
      }
    };
    const finalizedEncounter = {
      ...initialEncounter,
      status: 'CANCELLED',
      tenant: null,
      facility: null,
      patient: null,
      provider: null,
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      admissions: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(initialEncounter)
          .mockResolvedValueOnce(finalizedEncounter),
        update: jest.fn().mockResolvedValue(finalizedEncounter)
      },
      visit_queue: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'queue-1',
          human_friendly_id: 'QUE000001',
          status: 'CANCELLED'
        }),
        update: jest.fn().mockResolvedValue({ id: 'queue-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'inv-1',
          status: 'SENT',
          billing_status: 'ISSUED',
          payments: []
        }),
        update: jest.fn().mockResolvedValue({
          id: 'inv-1',
          status: 'CANCELLED',
          billing_status: 'CANCELLED'
        })
      },
      invoice_item: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 })
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn().mockResolvedValue({ count: 0 })
      },
      billable_charge_event: {
        findMany: jest.fn().mockResolvedValue([]),
        updateMany: jest.fn().mockResolvedValue({ count: 0 })
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.cancelEncounter(
      'ENC000001',
      { reason_code: 'ENTERED_IN_ERROR' },
      { tenant_id: 'tenant-1', user_id: 'usr-1' }
    );

    expect(tx.invoice.update).toHaveBeenCalledWith({
      where: { id: 'inv-1' },
      data: { status: 'CANCELLED', billing_status: 'CANCELLED' }
    });
  });

  it('rejects a stale supersede request when the active encounter changed', async () => {
    const tx = {
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' })
      }
    };
    opdFlowRepository.findOpenActiveEncounterForPatient.mockResolvedValueOnce({
      id: 'enc-open-1',
      human_friendly_id: 'ENC0000009',
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_DOCTOR_REVIEW',
          timeline: []
        }
      }
    });
    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          tenant_id: 'tenant-1',
          patient_id: 'PAT0000003',
          force_new_encounter: true,
          supersede_encounter_id: 'ENC0000010'
        },
        { tenant_id: 'tenant-1', user_id: 'usr-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.supersede_encounter_mismatch',
      statusCode: 409
    });
  });

  it('maps database active OPD lock conflicts to duplicate encounter errors', async () => {
    const duplicateError = new Error('unique conflict');
    duplicateError.code = 'P2002';
    duplicateError.meta = { target: ['active_opd_lock_key'] };

    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ id: 'TENANT-1' })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      patient: {
        findFirst: jest.fn().mockResolvedValue({ id: 'pat-1' })
      },
      invoice: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      payment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      emergency_case: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      triage_assessment: {
        create: jest.fn(),
        findFirst: jest.fn()
      },
      visit_queue: {
        create: jest.fn().mockResolvedValue({ id: 'vq-1' }),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        create: jest.fn().mockRejectedValue(duplicateError),
        findFirst: jest.fn(),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          tenant_id: 'tenant-1',
          patient_id: 'PAT0000003',
          require_consultation_payment: false
        },
        { tenant_id: 'tenant-1', user_id: 'usr-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.active_encounter_exists',
      statusCode: 409
    });
  });

  it('rejects OPD flow start for cancelled appointment', async () => {
    const tx = {
      appointment: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'apt-1',
          patient_id: 'pat-1',
          status: 'CANCELLED',
          tenant_id: 'tenant-1'
        })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.startOpdFlow(
        {
          appointment_id: 'apt-1'
        },
        { tenant_id: 'tenant-1' }
      )
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('records vitals while the consultation payment is still outstanding', async () => {
    const encounterRecord = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_CONSULTATION_PAYMENT',
          consultation: {
            require_payment: true,
            is_paid: false
          }
        }
      }
    };

    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest.fn().mockResolvedValue(encounterRecord),
        update: jest.fn().mockResolvedValue(encounterRecord)
      },
      vital_sign: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn(),
        create: jest.fn().mockResolvedValue({
          id: 'vital-1',
          encounter_id: 'enc-1',
          vital_type: 'TEMPERATURE',
          value: '37.1'
        })
      },
      triage_assessment: {
        update: jest.fn(),
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.recordVitals(
      'enc-1',
      {
        vitals: [{ vital_type: 'TEMPERATURE', value: '37.1' }]
      },
      { user_id: 'usr-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(tx.vital_sign.create).toHaveBeenCalled();
    const persistedFlow =
      tx.encounter.update.mock.calls[0][0].data.extension_json.opd_flow;
    // Triage moves the visit on; the unpaid consultation stays flagged for
    // Reception/Billing instead of blocking care.
    expect(persistedFlow.stage).toBe('WAITING_DOCTOR_ASSIGNMENT');
    expect(persistedFlow.consultation.is_paid).toBe(false);
  });

  it('allows audit-safe consultation billing correction after payment', async () => {
    const snapshotEncounter = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      provider_user_id: null,
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_VITALS',
          consultation: {
            require_payment: true,
            is_paid: true,
            invoice_id: 'inv-1',
            payment_id: 'pay-old',
            paid_amount: '20000',
            currency: 'UGX'
          }
        }
      },
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      referrals: [],
      follow_ups: [],
      admissions: [],
      lab_orders: [],
      radiology_orders: [],
      pharmacy_orders: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                consultation: {
                  require_payment: true,
                  is_paid: true,
                  invoice_id: 'inv-1',
                  payment_id: 'pay-old',
                  paid_amount: '20000',
                  consultation_fee: '20000',
                  currency: 'UGX'
                }
              }
            }
          })
          .mockResolvedValue(snapshotEncounter),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      invoice: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'inv-1',
            human_friendly_id: 'INV000001',
            total_amount: '20000',
            currency: 'UGX',
            payments: []
          })
          .mockResolvedValue({
            id: 'inv-1',
            human_friendly_id: 'INV000001',
            status: 'SENT',
            billing_status: 'ISSUED',
            total_amount: '30000',
            currency: 'UGX',
            payments: [{ id: 'pay-new', status: 'COMPLETED', amount: '30000', refunds: [] }],
            billing_adjustments: []
          }),
        create: jest.fn(),
        update: jest.fn().mockResolvedValue({
          id: 'inv-1',
          human_friendly_id: 'INV000001',
          status: 'PAID',
          billing_status: 'PAID',
          total_amount: '30000',
          currency: 'UGX'
        })
      },
      payment: {
        create: jest.fn().mockResolvedValue({
          id: 'pay-new',
          human_friendly_id: 'PAY000002',
          status: 'COMPLETED',
          amount: '30000',
          paid_at: new Date('2026-05-21T09:00:00.000Z')
        }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'pay-new',
          human_friendly_id: 'PAY000002',
          status: 'COMPLETED',
          amount: '30000'
        })
      },
      facility: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.payConsultation(
      'enc-1',
      {
        amount: '30000',
        currency: 'UGX',
        method: 'CASH',
        status: 'COMPLETED',
        notes: 'Corrected consultation fee'
      },
      {
        user_id: 'billing-1',
        tenant_id: 'tenant-1',
        facility_id: 'facility-1'
      }
    );

    expect(tx.payment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        invoice_id: 'inv-1',
        amount: '30000',
        status: 'COMPLETED'
      })
    });
    expect(tx.invoice.update).toHaveBeenNthCalledWith(1, {
      where: { id: 'inv-1' },
      data: expect.objectContaining({
        total_amount: '30000',
        currency: 'UGX'
      })
    });
    expect(tx.invoice.update).toHaveBeenNthCalledWith(2, {
      where: { id: 'inv-1' },
      data: expect.objectContaining({
        status: 'PAID',
        billing_status: 'PAID'
      })
    });
    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          extension_json: expect.objectContaining({
            opd_flow: expect.objectContaining({
              consultation: expect.objectContaining({
                payment_id: 'pay-new',
                paid_amount: '30000.00'
              })
            })
          })
        })
      })
    );
  });

  it('updates active encounter context instead of creating a duplicate OPD flow', async () => {
    const initialEncounter = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      provider_user_id: null,
      encounter_type: 'OPD',
      status: 'OPEN',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_CONSULTATION_PAYMENT',
          consultation: {
            require_payment: true,
            is_paid: false,
            invoice_id: 'inv-1',
            payment_id: null,
            consultation_fee: '20000',
            currency: 'UGX'
          },
          timeline: []
        }
      }
    };
    const snapshotEncounter = {
      ...initialEncounter,
      provider_user_id: 'doc-1',
      extension_json: {
        opd_flow: {
          ...initialEncounter.extension_json.opd_flow,
          stage: 'WAITING_VITALS',
          next_step: 'RECORD_VITALS',
          consultation: {
            require_payment: true,
            is_paid: true,
            invoice_id: 'inv-1',
            payment_id: 'pay-1',
            consultation_fee: '50000',
            currency: 'UGX',
            payment_status: 'COMPLETED',
            paid_amount: '50000'
          },
          timeline: []
        }
      },
      tenant: {},
      facility: {},
      patient: {},
      provider: { human_friendly_id: 'DOC000001', profile: {} },
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      referrals: [],
      follow_ups: [],
      admissions: [],
      lab_orders: [],
      radiology_orders: [],
      pharmacy_orders: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(initialEncounter)
          .mockResolvedValueOnce(snapshotEncounter),
        update: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1'
        }),
        create: jest.fn()
      },
      user: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'doc-1',
          staff_profile: {
            practitioner_type: 'SPECIALIST',
            consultation_fee: '50000',
            consultation_currency: 'UGX'
          }
        })
      },
      facility: {
        findFirst: jest.fn().mockResolvedValue({ extension_json: {} })
      },
      tenant: {
        findFirst: jest.fn().mockResolvedValue({ extension_json: {} })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn()
      },
      invoice: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'inv-1',
            human_friendly_id: 'INV000001',
            total_amount: '50000',
            currency: 'UGX',
            status: 'SENT',
            billing_status: 'ISSUED',
            payments: []
          })
          .mockResolvedValue({
            id: 'inv-1',
            human_friendly_id: 'INV000001',
            total_amount: '50000',
            currency: 'UGX',
            status: 'SENT',
            billing_status: 'ISSUED',
            payments: [{ id: 'pay-1', status: 'COMPLETED', amount: '50000', refunds: [] }],
            billing_adjustments: []
          }),
        update: jest.fn().mockResolvedValue({
          id: 'inv-1',
          total_amount: '50000',
          currency: 'UGX',
          status: 'PAID',
          billing_status: 'PAID'
        }),
        create: jest.fn()
      },
      payment: {
        create: jest.fn().mockResolvedValue({
          id: 'pay-1',
          human_friendly_id: 'PAY000001',
          amount: '50000',
          status: 'COMPLETED',
          paid_at: new Date()
        }),
        findFirst: jest.fn().mockResolvedValue({
          id: 'pay-1',
          human_friendly_id: 'PAY000001',
          amount: '50000',
          status: 'COMPLETED'
        })
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.updateActiveEncounterContext(
      'enc-1',
      {
        provider_user_id: 'doc-1',
        consultation_fee: '50000',
        currency: 'UGX',
        require_consultation_payment: true,
        pay_now: {
          method: 'CASH',
          amount: '50000',
          status: 'COMPLETED'
        },
        notes: 'Updated active encounter'
      },
      {
        user_id: 'reception-1',
        tenant_id: 'tenant-1',
        facility_id: 'facility-1'
      }
    );

    expect(tx.encounter.create).not.toHaveBeenCalled();
    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'enc-1' },
        data: expect.objectContaining({
          provider_user_id: 'doc-1',
          extension_json: expect.objectContaining({
            opd_flow: expect.objectContaining({
              stage: 'WAITING_VITALS',
              consultation: expect.objectContaining({
                consultation_fee: '50000',
                payment_id: 'pay-1',
                is_paid: true
              })
            })
          })
        })
      })
    );
    expect(result.flow.consultation.paid_amount).toBe('50000');
    expect(createAuditLog).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'UPDATE',
        entity: 'opd_flow',
        entity_id: 'enc-1'
      })
    );
  });

  it('updates existing OPD vitals instead of creating duplicate encounter measurements', async () => {
    const snapshotEncounter = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      provider_user_id: null,
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_DOCTOR_ASSIGNMENT',
          consultation: {
            require_payment: false,
            is_paid: false,
            invoice_id: null,
            payment_id: null
          }
        }
      },
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      referrals: [],
      follow_ups: [],
      admissions: [],
      lab_orders: [],
      radiology_orders: [],
      pharmacy_orders: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                consultation: {
                  require_payment: false,
                  is_paid: false,
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValue(snapshotEncounter),
        update: jest.fn().mockResolvedValue(snapshotEncounter)
      },
      vital_sign: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'vital-1',
          encounter_id: 'enc-1',
          vital_type: 'TEMPERATURE',
          value: '37.1'
        }),
        update: jest.fn().mockResolvedValue({
          id: 'vital-1',
          encounter_id: 'enc-1',
          vital_type: 'TEMPERATURE',
          value: '37.5'
        }),
        create: jest.fn()
      },
      triage_assessment: {
        update: jest.fn(),
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.recordVitals(
      'enc-1',
      { vitals: [{ vital_type: 'TEMPERATURE', value: '37.5', unit: 'C' }] },
      { user_id: 'actor-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(tx.vital_sign.findFirst).toHaveBeenCalledWith({
      where: {
        encounter_id: 'enc-1',
        vital_type: 'TEMPERATURE',
        deleted_at: null
      },
      orderBy: { recorded_at: 'desc' }
    });
    expect(tx.vital_sign.update).toHaveBeenCalledWith({
      where: { id: 'vital-1' },
      data: expect.objectContaining({
        encounter_id: 'enc-1',
        vital_type: 'TEMPERATURE',
        value: '37.5',
        unit: 'C'
      })
    });
    expect(tx.vital_sign.create).not.toHaveBeenCalled();
  });

  it('advances directly to doctor review after vitals when a provider is already assigned', async () => {
    const snapshotEncounter = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      provider_user_id: 'doc-1',
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_DOCTOR_REVIEW',
          next_step: 'DOCTOR_REVIEW',
          consultation: {
            require_payment: false,
            is_paid: false,
            invoice_id: null,
            payment_id: null
          }
        }
      },
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      referrals: [],
      follow_ups: [],
      admissions: [],
      lab_orders: [],
      radiology_orders: [],
      pharmacy_orders: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                consultation: {
                  require_payment: false,
                  is_paid: false,
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValue(snapshotEncounter),
        update: jest.fn().mockResolvedValue(snapshotEncounter)
      },
      vital_sign: {
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn(),
        create: jest.fn().mockResolvedValue({
          id: 'vital-1',
          encounter_id: 'enc-1',
          vital_type: 'TEMPERATURE',
          value: '37.5'
        })
      },
      triage_assessment: {
        update: jest.fn(),
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.recordVitals(
      'enc-1',
      { vitals: [{ vital_type: 'TEMPERATURE', value: '37.5', unit: 'C' }] },
      { user_id: 'actor-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'enc-1' },
        data: expect.objectContaining({
          extension_json: expect.objectContaining({
            opd_flow: expect.objectContaining({
              stage: 'WAITING_DOCTOR_REVIEW',
              next_step: 'DOCTOR_REVIEW'
            })
          })
        })
      })
    );
    expect(result.flow.stage).toBe('WAITING_DOCTOR_REVIEW');
    expect(result.flow.next_step).toBe('DOCTOR_REVIEW');
  });

  it('allows doctor review from doctor-assignment stage when the encounter already has a provider', async () => {
    const snapshotEncounter = {
      id: 'enc-1',
      tenant_id: 'tenant-1',
      facility_id: 'facility-1',
      patient_id: 'pat-1',
      provider_user_id: 'doc-1',
      encounter_type: 'OPD',
      extension_json: {
        opd_flow: {
          stage: 'WAITING_DISPOSITION',
          next_step: 'DISPOSITION',
          review_completed: true,
          visit_queue_id: null,
          appointment_id: null,
          consultation: {
            invoice_id: null,
            payment_id: null
          }
        }
      },
      vital_signs: [],
      clinical_notes: [],
      diagnoses: [],
      procedures: [],
      care_plans: [],
      alerts: [],
      referrals: [],
      follow_ups: [],
      admissions: [],
      lab_orders: [],
      radiology_orders: [],
      pharmacy_orders: []
    };
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_ASSIGNMENT',
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValue(snapshotEncounter),
        update: jest.fn().mockResolvedValue(snapshotEncounter)
      },
      clinical_note: {
        create: jest.fn().mockResolvedValue({ id: 'cn-1' })
      },
      visit_queue: { findFirst: jest.fn() },
      appointment: { findFirst: jest.fn() },
      invoice: { findFirst: jest.fn() },
      payment: { findFirst: jest.fn() },
      emergency_case: { findFirst: jest.fn() },
      triage_assessment: { findFirst: jest.fn() }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.doctorReview(
      'enc-1',
      { note: 'Doctor assessment completed' },
      { user_id: 'doc-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(tx.clinical_note.create).toHaveBeenCalled();
    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          extension_json: expect.objectContaining({
            opd_flow: expect.objectContaining({
              stage: 'WAITING_DISPOSITION',
              next_step: 'DISPOSITION',
              review_completed: true
            })
          })
        })
      })
    );
    expect(result.flow.stage).toBe('WAITING_DISPOSITION');
  });

  it('creates lab, radiology, and pharmacy requests on doctor review', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_REVIEW',
                review_completed: false,
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'LAB_AND_RADIOLOGY_REQUESTED',
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      clinical_note: {
        create: jest.fn().mockResolvedValue({ id: 'cn-1' })
      },
      diagnosis: {
        createMany: jest.fn()
      },
      procedure: {
        createMany: jest.fn()
      },
      lab_order: {
        create: jest.fn().mockResolvedValue({ id: 'lab-1' })
      },
      lab_order_item: {
        createMany: jest.fn()
      },
      lab_test: {
        findFirst: jest.fn().mockResolvedValue({ id: 'lab-test-1' })
      },
      lab_panel: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'lab-panel-1',
          panel_items: [
            { lab_test_id: 'lab-test-1' },
            { lab_test_id: 'lab-test-2' }
          ]
        })
      },
      radiology_order: {
        create: jest.fn().mockResolvedValue({ id: 'rad-1' })
      },
      radiology_procedure: {
        findFirst: jest.fn().mockResolvedValue({ id: 'rad-test-1' })
      },
      pharmacy_order: {
        create: jest.fn().mockResolvedValue({ id: 'ph-1' })
      },
      pharmacy_order_item: {
        createMany: jest.fn()
      },
      drug: {
        findFirst: jest.fn().mockResolvedValue({ id: 'drug-1' })
      },
      visit_queue: { findFirst: jest.fn() },
      appointment: { findFirst: jest.fn() },
      invoice: { findFirst: jest.fn() },
      payment: { findFirst: jest.fn() },
      emergency_case: { findFirst: jest.fn() },
      triage_assessment: { findFirst: jest.fn() }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.doctorReview(
      'enc-1',
      {
        note: 'Doctor assessment completed',
        lab_requests: [
          { lab_test_id: 'lab-test-1' },
          { lab_panel_id: 'lab-panel-1' }
        ],
        radiology_requests: [{ radiology_test_id: 'rad-test-1' }],
        medications: [{ drug_id: 'drug-1', quantity: 1 }]
      },
      { user_id: 'doc-1' }
    );

    expect(tx.lab_order.create).toHaveBeenCalled();
    expect(tx.lab_order_item.createMany).toHaveBeenCalledWith({
      data: [
        {
          lab_order_id: 'lab-1',
          lab_test_id: 'lab-test-1',
          status: 'ORDERED'
        },
        {
          lab_order_id: 'lab-1',
          lab_test_id: 'lab-test-2',
          status: 'ORDERED'
        }
      ]
    });
    expect(tx.radiology_order.create).toHaveBeenCalled();
    expect(tx.pharmacy_order.create).toHaveBeenCalled();
    expect(result.flow.stage).toBe('LAB_AND_RADIOLOGY_REQUESTED');
  });

  it('attends an unassigned patient from the vitals stage and claims the encounter', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                review_completed: false,
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  require_payment: true,
                  is_paid: false,
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValue({
            id: 'enc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DISPOSITION',
                visit_queue_id: null,
                appointment_id: null,
                consultation: { invoice_id: null, payment_id: null }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      clinical_note: { create: jest.fn().mockResolvedValue({ id: 'cn-1' }) },
      diagnosis: { createMany: jest.fn() },
      procedure: { createMany: jest.fn() },
      lab_order: { create: jest.fn() },
      lab_order_item: { createMany: jest.fn() },
      lab_test: { findFirst: jest.fn() },
      lab_panel: { findFirst: jest.fn() },
      radiology_order: { create: jest.fn() },
      radiology_procedure: { findFirst: jest.fn() },
      pharmacy_order: { create: jest.fn() },
      pharmacy_order_item: { createMany: jest.fn() },
      drug: { findFirst: jest.fn() },
      visit_queue: { findFirst: jest.fn(), update: jest.fn() },
      appointment: { findFirst: jest.fn() },
      invoice: { findFirst: jest.fn() },
      payment: { findFirst: jest.fn() },
      emergency_case: { findFirst: jest.fn() },
      triage_assessment: { findFirst: jest.fn() }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.doctorReview(
      'enc-1',
      { note: 'Seen on arrival, no doctor had been assigned.' },
      { user_id: 'doc-9' }
    );

    const updateArgs = tx.encounter.update.mock.calls[0][0].data;
    expect(updateArgs.provider_user_id).toBe('doc-9');
    expect(updateArgs.extension_json.opd_flow.review_completed).toBe(true);
    expect(updateArgs.extension_json.opd_flow.stage).toBe('WAITING_DISPOSITION');
  });

  it('closes a visit that never had a doctor review and records why', async () => {
    const tx = {
      admission: { findFirst: jest.fn().mockResolvedValue(null) },
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_VITALS',
              review_completed: false,
              visit_queue_id: null,
              appointment_id: null
            }
          }
        }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      admission_create: undefined,
      visit_queue: { findFirst: jest.fn(), update: jest.fn() },
      appointment: { findFirst: jest.fn() },
      invoice: { findFirst: jest.fn() },
      payment: { findFirst: jest.fn() },
      emergency_case: { findFirst: jest.fn() },
      triage_assessment: { findFirst: jest.fn() }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.disposition(
      'enc-1',
      { decision: 'DISCHARGE', reason: 'Patient left before consultation' },
      { user_id: 'doc-1' }
    );

    const persistedFlow =
      tx.encounter.update.mock.calls[0][0].data.extension_json.opd_flow;
    expect(persistedFlow.closed_without_review).toBe(true);
    expect(persistedFlow.stage).toBe('DISCHARGED');
    expect(
      persistedFlow.timeline.some(
        (event) => event.event === 'DISPOSITION_WITHOUT_REVIEW'
      )
    ).toBe(true);
  });

  it('resolves standard lab catalog requests during doctor review', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-1',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_REVIEW',
                review_completed: false,
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'LAB_REQUESTED',
                visit_queue_id: null,
                appointment_id: null,
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      clinical_note: {
        create: jest.fn().mockResolvedValue({ id: 'cn-1' })
      },
      diagnosis: {
        createMany: jest.fn()
      },
      procedure: {
        createMany: jest.fn()
      },
      lab_order: {
        create: jest.fn().mockResolvedValue({ id: 'lab-1' })
      },
      lab_order_item: {
        createMany: jest.fn()
      },
      lab_test: {
        findFirst: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue({ id: 'lab-test-standard-1' })
      },
      lab_panel: {
        findFirst: jest.fn()
      },
      radiology_order: {
        create: jest.fn()
      },
      radiology_procedure: {
        findFirst: jest.fn()
      },
      pharmacy_order: {
        create: jest.fn()
      },
      pharmacy_order_item: {
        createMany: jest.fn()
      },
      drug: {
        findFirst: jest.fn()
      },
      visit_queue: { findFirst: jest.fn() },
      appointment: { findFirst: jest.fn() },
      invoice: { findFirst: jest.fn() },
      payment: { findFirst: jest.fn() },
      emergency_case: { findFirst: jest.fn() },
      triage_assessment: { findFirst: jest.fn() }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.doctorReview(
      'enc-1',
      {
        note: 'Request lab',
        lab_requests: [{ lab_test_id: 'STD_LAB_TEST:LOINC_6742_1' }]
      },
      { user_id: 'doc-1' }
    );

    expect(tx.lab_test.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          tenant_id: 'tenant-1',
          code: '6742-1'
        }),
        select: { id: true }
      })
    );
    expect(tx.lab_order_item.createMany).toHaveBeenCalledWith({
      data: [
        {
          lab_order_id: 'lab-1',
          lab_test_id: 'lab-test-standard-1',
          status: 'ORDERED'
        }
      ]
    });
    expect(result.flow.stage).toBe('LAB_REQUESTED');
  });

  it('prevents send-to-pharmacy disposition without pharmacy order', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_DISPOSITION',
              review_completed: true,
              pharmacy_order_id: null
            }
          }
        })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.disposition(
        'enc-1',
        {
          decision: 'SEND_TO_PHARMACY'
        },
        { user_id: 'doc-1' }
      )
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('admits patient on disposition, keeps OPD open for IPD handoff', async () => {
    const tx = {
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DISPOSITION',
                review_completed: true,
                visit_queue_id: 'vq-1',
                appointment_id: 'apt-1',
                emergency_case_id: 'ec-1',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            encounter_type: 'EMERGENCY',
            status: 'OPEN',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DISPOSITION',
                review_completed: true,
                admission_pending: true,
                admission_id: 'adm-1',
                visit_queue_id: 'vq-1',
                appointment_id: 'apt-1',
                emergency_case_id: 'ec-1',
                disposition_decision: 'ADMIT',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      admission: {
        create: jest.fn().mockResolvedValue({ id: 'adm-1' })
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue({ id: 'vq-1' })
      },
      appointment: {
        findFirst: jest
          .fn()
          .mockResolvedValue({ id: 'apt-1', status: 'IN_PROGRESS' }),
        update: jest.fn()
      },
      emergency_case: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue({ id: 'ec-1' })
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.disposition(
      'enc-1',
      {
        decision: 'ADMIT'
      },
      {
        user_id: 'doc-1'
      }
    );

    expect(tx.admission.create).toHaveBeenCalled();
    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'enc-1' },
        data: expect.objectContaining({
          status: 'OPEN',
          extension_json: expect.objectContaining({
            opd_flow: expect.objectContaining({
              admission_pending: true,
              admission_id: 'adm-1',
              disposition_decision: 'ADMIT',
              stage: 'WAITING_DISPOSITION'
            })
          })
        })
      })
    );
    // OPD stays linked until inpatient care continues — do not close queue/visit yet.
    expect(tx.visit_queue.update).not.toHaveBeenCalled();
    expect(tx.appointment.update).not.toHaveBeenCalled();
    expect(tx.emergency_case.update).not.toHaveBeenCalled();
    expect(ipdFlowService.emitAdmissionRefreshEvent).toHaveBeenCalledWith(
      'adm-1',
      expect.objectContaining({ user_id: 'doc-1' })
    );
    expect(result.flow.stage).toBe('WAITING_DISPOSITION');
    expect(result.flow.admission_pending).toBe(true);
  });

  it('rejects disposition when flow is already terminal', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          extension_json: {
            opd_flow: {
              stage: 'DISCHARGED',
              review_completed: true
            }
          }
        })
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.disposition(
        'enc-1',
        {
          decision: 'DISCHARGE'
        },
        { user_id: 'doc-1' }
      )
    ).rejects.toBeInstanceOf(HttpError);
  });

  it('reopens a completed flow when correcting to a non-terminal stage', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            encounter_type: 'OPD',
            status: 'CLOSED',
            ended_at: new Date('2026-05-16T08:00:00.000Z'),
            extension_json: {
              opd_flow: {
                stage: 'DISCHARGED',
                visit_queue_id: 'vq-1',
                appointment_id: 'apt-1'
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            encounter_type: 'OPD',
            status: 'OPEN',
            ended_at: null,
            provider_user_id: 'doc-1',
            provider: {
              id: 'doc-1',
              human_friendly_id: 'DOC000001',
              email: 'doctor@example.com',
              profile: { first_name: 'Pat', last_name: 'Doctor' },
              roles: [{ role: { name: 'DOCTOR' } }]
            },
            vital_signs: [{ id: 'vital-1', deleted_at: null }],
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_REVIEW',
                next_step: 'DOCTOR_REVIEW',
                visit_queue_id: 'vq-1',
                appointment_id: 'apt-1',
                consultation: {
                  is_paid: true,
                  payment_status: 'COMPLETED',
                  require_payment: true
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue({ id: 'vq-1' })
      },
      appointment: {
        findFirst: jest
          .fn()
          .mockResolvedValue({ id: 'apt-1', status: 'COMPLETED' }),
        update: jest.fn()
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.correctStage(
      'enc-1',
      {
        stage_to: 'WAITING_DOCTOR_REVIEW',
        reason: 'Patient needs another doctor review'
      },
      { user_id: 'doc-1' }
    );

    expect(tx.encounter.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'enc-1' },
        data: expect.objectContaining({
          status: 'OPEN',
          active_opd_lock_key: 'opd:tenant-1:facility-1:pat-1',
          ended_at: null
        })
      })
    );
    expect(tx.visit_queue.update).toHaveBeenCalledWith({
      where: { id: 'vq-1' },
      data: { status: 'IN_PROGRESS' }
    });
    expect(tx.appointment.update).toHaveBeenCalledWith({
      where: { id: 'apt-1' },
      data: { status: 'IN_PROGRESS' }
    });
    expect(result.flow.stage).toBe('WAITING_DOCTOR_REVIEW');
  });

  it('requires a reason for backward stage corrections', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          status: 'OPEN',
          extension_json: {
            opd_flow: {
              stage: 'WAITING_DOCTOR_REVIEW',
              visit_queue_id: null,
              appointment_id: null
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.correctStage(
        'enc-1',
        {
          stage_to: 'WAITING_VITALS'
        },
        { user_id: 'doctor-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.validation.required',
      errors: expect.arrayContaining([
        expect.objectContaining({ field: 'reason' })
      ])
    });
    expect(tx.encounter.update).not.toHaveBeenCalled();
  });

  it('rejects correcting to payment due after consultation payment is recorded', async () => {
    const tx = {
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          status: 'OPEN',
          provider_user_id: 'doc-1',
          vital_signs: [{ id: 'vital-1', deleted_at: null }],
          lab_orders: [],
          radiology_orders: [],
          pharmacy_orders: [],
          admissions: [],
          extension_json: {
            opd_flow: {
              stage: 'WAITING_DOCTOR_REVIEW',
              consultation: {
                require_payment: true,
                is_paid: true,
                payment_status: 'COMPLETED'
              }
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.correctStage(
        'enc-1',
        {
          stage_to: 'WAITING_CONSULTATION_PAYMENT',
          reason: 'Should not undo payment'
        },
        { user_id: 'reception-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.invalid_stage_transition',
      errors: expect.arrayContaining([
        expect.objectContaining({ field: 'stage_to' })
      ])
    });
    expect(tx.encounter.update).not.toHaveBeenCalled();
  });

  it('rejects correcting to vitals needed after vitals are recorded', async () => {
    const tx = {
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          status: 'OPEN',
          provider_user_id: null,
          vital_signs: [{ id: 'vital-1', deleted_at: null }],
          lab_orders: [],
          radiology_orders: [],
          pharmacy_orders: [],
          admissions: [],
          extension_json: {
            opd_flow: {
              stage: 'WAITING_DOCTOR_ASSIGNMENT',
              consultation: {
                require_payment: true,
                is_paid: true,
                payment_status: 'COMPLETED'
              }
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.correctStage(
        'enc-1',
        {
          stage_to: 'WAITING_VITALS',
          reason: 'Should not undo vitals'
        },
        { user_id: 'reception-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.invalid_stage_transition',
      errors: expect.arrayContaining([
        expect.objectContaining({ field: 'stage_to' })
      ])
    });
    expect(tx.encounter.update).not.toHaveBeenCalled();
  });

  it('rejects correcting to doctor review after review is completed', async () => {
    const tx = {
      encounter: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'enc-1',
          tenant_id: 'tenant-1',
          patient_id: 'pat-1',
          status: 'OPEN',
          provider_user_id: 'doc-1',
          vital_signs: [{ id: 'vital-1', deleted_at: null }],
          lab_orders: [],
          radiology_orders: [],
          pharmacy_orders: [],
          admissions: [],
          extension_json: {
            opd_flow: {
              stage: 'WAITING_DISPOSITION',
              review_completed: true,
              consultation: {
                require_payment: true,
                is_paid: true,
                payment_status: 'COMPLETED'
              }
            }
          }
        }),
        update: jest.fn()
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await expect(
      opdFlowService.correctStage(
        'enc-1',
        {
          stage_to: 'WAITING_DOCTOR_REVIEW',
          reason: 'Should not undo review'
        },
        { user_id: 'reception-1' }
      )
    ).rejects.toMatchObject({
      messageKey: 'errors.opd_flow.invalid_stage_transition',
      errors: expect.arrayContaining([
        expect.objectContaining({ field: 'stage_to' })
      ])
    });
    expect(tx.encounter.update).not.toHaveBeenCalled();
  });

  it('emits OPD realtime updates, excluding actor and adding assigned provider', async () => {
    prisma.user_role.findMany.mockResolvedValue([
      { user_id: 'doctor-team-1' },
      { user_id: 'actor-1' }
    ]);
    prisma.notification_delivery.createMany.mockResolvedValue({ count: 2 });

    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_ASSIGNMENT',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-assigned-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_REVIEW',
                next_step: 'DOCTOR_REVIEW',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValueOnce({ id: 'enc-1' })
          .mockResolvedValueOnce({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      user: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'doc-assigned-1',
          staff_profile: { practitioner_type: 'DOCTOR' }
        })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.assignDoctor(
      'enc-1',
      { provider_user_id: 'doc-assigned-1' },
      { user_id: 'actor-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(emitToUsers).toHaveBeenCalledWith(
      expect.arrayContaining(['doctor-team-1', 'doc-assigned-1']),
      'opd.flow.updated',
      expect.objectContaining({
        encounter_id: 'enc-1',
        stage_to: 'WAITING_DOCTOR_REVIEW',
        actor_user_id: 'actor-1',
        action: 'ASSIGN_DOCTOR',
        operation: 'upsert'
      })
    );
    const sentRecipients = emitToUsers.mock.calls[0][0];
    expect(sentRecipients).not.toContain('actor-1');
    expect(prisma.notification.create).toHaveBeenCalledTimes(2);
    expect(prisma.notification_delivery.createMany).toHaveBeenCalledWith({
      data: expect.arrayContaining([
        expect.objectContaining({
          channel: 'IN_APP',
          status: 'SENT',
          sent_at: expect.any(Date)
        })
      ])
    });
    expect(emitToUser).toHaveBeenCalledTimes(2);
  });

  it('assigns a doctor using tenant-wide fallback when facility-scoped lookup misses', async () => {
    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_ASSIGNMENT',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: 'doc-global-1',
            encounter_type: 'OPD',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_REVIEW',
                next_step: 'DOCTOR_REVIEW',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValueOnce({ id: 'enc-1' })
          .mockResolvedValueOnce({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      user: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce({
            id: 'doc-global-1',
            staff_profile: { practitioner_type: 'DOCTOR' }
          })
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      triage_assessment: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    const result = await opdFlowService.assignDoctor(
      'enc-1',
      { provider_user_id: 'doc-global-1' },
      { user_id: 'actor-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(tx.user.findFirst).toHaveBeenCalledTimes(2);
    expect(tx.encounter.update).toHaveBeenCalledWith({
      where: { id: 'enc-1' },
      data: { provider_user_id: 'doc-global-1' }
    });
    // Display resolution prioritizes missing vitals over doctor-review stage.
    expect(result.flow.display_code).toBe('VITALS_NEEDED');
    expect(result.encounter.provider_user_id).toBe('doc-global-1');
    expect(result.flow.assigned_staff_label).toBeTruthy();
  });

  it('sets HIGH notification priority for emergency-driven OPD transitions', async () => {
    prisma.user_role.findMany.mockResolvedValue([{ user_id: 'nurse-1' }]);

    const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'EMERGENCY',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_VITALS',
                consultation: {
                  require_payment: false,
                  is_paid: false,
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          })
          .mockResolvedValueOnce({
            id: 'enc-1',
            tenant_id: 'tenant-1',
            facility_id: 'facility-1',
            patient_id: 'pat-1',
            provider_user_id: null,
            encounter_type: 'EMERGENCY',
            extension_json: {
              opd_flow: {
                stage: 'WAITING_DOCTOR_ASSIGNMENT',
                next_step: 'ASSIGN_DOCTOR',
                consultation: {
                  invoice_id: null,
                  payment_id: null
                }
              }
            }
          }),
        update: jest
          .fn()
          .mockResolvedValue({ id: 'enc-1', tenant_id: 'tenant-1' })
      },
      vital_sign: {
        createMany: jest.fn()
      },
      triage_assessment: {
        update: jest.fn(),
        create: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      visit_queue: {
        update: jest.fn(),
        findFirst: jest.fn().mockResolvedValue(null)
      },
      appointment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      invoice: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      payment: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      emergency_case: {
        findFirst: jest.fn().mockResolvedValue(null)
      }
    };

    prisma.$transaction.mockImplementation(async (callback) => callback(tx));

    await opdFlowService.recordVitals(
      'enc-1',
      { vitals: [{ vital_type: 'TEMPERATURE', value: '37.5' }] },
      { user_id: 'actor-1', tenant_id: 'tenant-1', facility_id: 'facility-1' }
    );

    expect(prisma.notification.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          priority: 'HIGH'
        })
      })
    );
  });

  it.each([
    ['cancelEncounter', { reason_code: 'PATIENT_LEFT' }, 'CANCELLED', 'CANCELLED', 'NO_SHOW'],
    ['closeEncounter', { reason_notes: 'Completed' }, 'CLOSED', 'COMPLETED', 'COMPLETED']
  ])(
    '%s finalizes the encounter and linked queue/appointment',
    async (method, payload, encounterStatus, queueStatus, appointmentStatus) => {
      const initialEncounter = {
        id: 'enc-1',
        human_friendly_id: 'ENC000001',
        tenant_id: 'tenant-1',
        facility_id: 'facility-1',
        patient_id: 'patient-1',
        provider_user_id: null,
        encounter_type: 'OPD',
        status: 'OPEN',
        extension_json: {
          opd_flow: {
            stage: 'WAITING_VITALS',
            visit_queue_id: 'queue-1',
            appointment_id: 'appointment-1',
            consultation: {}
          }
        }
      };
      const finalizedEncounter = {
        ...initialEncounter,
        status: encounterStatus,
        tenant: null,
        facility: null,
        patient: null,
        provider: null,
        vital_signs: [],
        clinical_notes: [],
        diagnoses: [],
        procedures: [],
        care_plans: [],
        alerts: [],
        admissions: []
      };
      const tx = {
      admission: {
        findFirst: jest.fn().mockResolvedValue(null)
      },
      encounter: {
          findFirst: jest
            .fn()
            .mockResolvedValueOnce(initialEncounter)
            .mockResolvedValueOnce(finalizedEncounter),
          update: jest.fn().mockResolvedValue(finalizedEncounter)
        },
        visit_queue: {
          findFirst: jest.fn().mockResolvedValue({
            id: 'queue-1',
            human_friendly_id: 'QUE000001',
            status: queueStatus
          }),
          update: jest.fn().mockResolvedValue({ id: 'queue-1' })
        },
        appointment: {
          findFirst: jest.fn().mockResolvedValue({
            id: 'appointment-1',
            status: 'IN_PROGRESS'
          }),
          update: jest.fn().mockResolvedValue({ id: 'appointment-1' })
        },
        invoice: {
          findFirst: jest.fn().mockResolvedValue(null)
        },
        payment: {
          findFirst: jest.fn().mockResolvedValue(null)
        },
        emergency_case: {
          findFirst: jest.fn().mockResolvedValue(null)
        },
        triage_assessment: {
          findFirst: jest.fn().mockResolvedValue(null)
        }
      };
      prisma.$transaction.mockImplementation(async (callback) => callback(tx));

      const result = await opdFlowService[method]('ENC000001', payload, {
        user_id: 'actor-1',
        tenant_id: 'tenant-1',
        facility_id: 'facility-1'
      });

      expect(tx.visit_queue.update).toHaveBeenCalledWith({
        where: { id: 'queue-1' },
        data: { status: queueStatus }
      });
      expect(tx.appointment.update).toHaveBeenCalledWith({
        where: { id: 'appointment-1' },
        data: { status: appointmentStatus }
      });
      expect(tx.encounter.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: 'enc-1' },
          data: expect.objectContaining({ status: encounterStatus })
        })
      );
      expect(result.encounter.human_friendly_id).toBe('ENC000001');
      expect(createAuditLog).toHaveBeenCalled();
    }
  );
});
