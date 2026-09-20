/**
 * Follow-up service tests
 *
 * @module tests/modules/follow-up/services
 * Per testing.mdc: Test business logic with mocked repositories
 */

const { HttpError } = require("@lib/errors");

// Mock dependencies
jest.mock("@repositories/follow-up/follow-up.repository");
jest.mock("@lib/audit");
jest.mock("@lib/identifiers/service-identifier-resolution", () => ({
  resolveIdentifierForFilter: jest.fn(async ({ value }) => value),
  resolveIdentifierForPayload: jest.fn(async ({ value }) => value)}));
jest.mock("@prisma/client", () => ({
  follow_up: {
    count: jest.fn(),
    findMany: jest.fn(),
    findFirst: jest.fn(),
    update: jest.fn()},
  encounter: {
    findFirst: jest.fn()},
  user_role: {
    findMany: jest.fn()},
  notification: {
    create: jest.fn()},
  notification_delivery: {
    createMany: jest.fn()}}));
jest.mock("@lib/websocket", () => ({
  emitToUser: jest.fn(),
  NOTIFICATION_EVENTS: {
    NOTIFICATION_CREATED: "notification.created"}}));

const followUpRepository = require("@repositories/follow-up/follow-up.repository");
const prisma = require("@prisma/client");
const { createAuditLog } = require("@lib/audit");
const { emitToUser } = require("@lib/websocket");
const {
  resolveIdentifierForFilter,
  resolveIdentifierForPayload} = require("@lib/identifiers/service-identifier-resolution");
const {
  listFollowUps,
  getFollowUpById,
  createFollowUp,
  updateFollowUp,
  deleteFollowUp,
  dispatchFollowUpReminders} = require("@services/follow-up/follow-up.service");

describe("Follow-up Service", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    createAuditLog.mockResolvedValue();
    resolveIdentifierForFilter.mockImplementation(async ({ value }) => value);
    resolveIdentifierForPayload.mockImplementation(async ({ value }) => value);
    prisma.follow_up.count.mockResolvedValue(0);
    prisma.follow_up.findMany.mockResolvedValue([]);
    prisma.follow_up.findFirst.mockResolvedValue(null);
    prisma.follow_up.update.mockResolvedValue({});
    prisma.encounter.findFirst.mockResolvedValue({
      id: "encounter-uuid-1",
      patient_id: "patient-1"});
    prisma.user_role.findMany.mockResolvedValue([]);
    prisma.notification.create.mockImplementation(async ({ data }) => ({
      id: `notif-${data.user_id}`,
      human_friendly_id: `NTF-${data.user_id}`,
      user_id: data.user_id,
      tenant_id: data.tenant_id,
      notification_type: data.notification_type,
      priority: data.priority,
      title: data.title,
      message: data.message,
      target_path: data.target_path || null,
      context_type: data.context_type || null,
      context_public_id: data.context_public_id || null,
      read_at: null,
      created_at: new Date("2026-03-04T12:00:00.000Z"),
      updated_at: new Date("2026-03-04T12:00:00.000Z")}));
    prisma.notification_delivery.createMany.mockResolvedValue({ count: 0 });
  });

  describe("listFollowUps", () => {
    it("should list follow-ups with pagination", async () => {
      const mockFollowUps = [
        {
          id: "fu-1",
          human_friendly_id: "FU-1",
          encounter_id: "enc-1",
          scheduled_at: "2026-07-22T09:00:00.000Z",
          status: "SCHEDULED",
          notes: "Call back",
          encounter: {
            id: "enc-1",
            human_friendly_id: "ENC-1",
            encounter_type: "OPD",
            patient: {
              id: "pat-1",
              human_friendly_id: "PAT-1",
              first_name: "Ada",
              last_name: "Lovelace",
              contacts: [
                {
                  contact_type: "PHONE",
                  value: "+256700000001",
                  is_primary: true},
                {
                  contact_type: "EMAIL",
                  value: "ada@example.com",
                  is_primary: true}]}}}];
      followUpRepository.findMany.mockResolvedValue(mockFollowUps);
      followUpRepository.count.mockResolvedValue(1);

      const result = await listFollowUps(
        { tenant_id: "tenant-1" },
        1,
        20,
        "created_at",
        "desc",
        "user-1",
        "127.0.0.1",
      );

      expect(followUpRepository.findMany).toHaveBeenCalledWith(
        {
          encounter: {
            tenant_id: "tenant-1",
            deleted_at: null,
          },
        },
        0,
        20,
        { created_at: "desc" },
        expect.objectContaining({
          encounter: expect.any(Object)})
      );
      expect(result.followUps).toEqual([
        expect.objectContaining({
          id: "FU-1",
          encounter_id: "ENC-1",
          patient_id: "PAT-1",
          patient_display_name: "Ada Lovelace",
          patient_primary_phone: "+256700000001",
          patient_primary_email: "ada@example.com",
          encounter_type: "OPD",
          status: "SCHEDULED",
          notes: "Call back"})]);
      expect(result.pagination.total).toBe(1);
    });

    it("should filter by encounter_type", async () => {
      followUpRepository.findMany.mockResolvedValue([]);
      followUpRepository.count.mockResolvedValue(0);

      await listFollowUps(
        { tenant_id: "tenant-1", encounter_type: "IPD", status: "SCHEDULED" },
        1,
        20,
        "scheduled_at",
        "asc",
        "user-1",
        "127.0.0.1",
      );

      expect(followUpRepository.findMany).toHaveBeenCalledWith(
        {
          status: "SCHEDULED",
          encounter: {
            encounter_type: "IPD",
            deleted_at: null,
            tenant_id: "tenant-1"}},
        0,
        20,
        { scheduled_at: "asc" },
        expect.objectContaining({
          encounter: expect.any(Object)})
      );
    });

    it("returns no follow-ups when a tenant user has no tenant scope", async () => {
      const result = await listFollowUps({}, 1, 20, "scheduled_at", "asc");

      expect(followUpRepository.findMany).not.toHaveBeenCalled();
      expect(result.followUps).toEqual([]);
      expect(result.pagination.total).toBe(0);
    });

    it("does not list another tenant's follow-ups", async () => {
      followUpRepository.findMany.mockResolvedValue([]);
      followUpRepository.count.mockResolvedValue(0);

      await listFollowUps(
        { tenant_id: "fairbanks-tenant" },
        1,
        20,
        "scheduled_at",
        "asc",
      );

      expect(followUpRepository.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          encounter: expect.objectContaining({
            tenant_id: "fairbanks-tenant",
            deleted_at: null,
          }),
        }),
        0,
        20,
        { scheduled_at: "asc" },
        expect.objectContaining({
          encounter: expect.any(Object),
        }),
      );
      expect(followUpRepository.findMany.mock.calls[0][0]).not.toEqual(
        expect.objectContaining({
          encounter: expect.objectContaining({
            tenant_id: "demo-tenant",
          }),
        }),
      );
    });
  });

  describe("getFollowUpById", () => {
    it("should get follow-up by ID", async () => {
      const mockFollowUp = {
        id: "fu-1",
        human_friendly_id: "FU-1",
        encounter_id: "enc-1",
        status: "SCHEDULED",
        encounter: {
          id: "enc-1",
          human_friendly_id: "ENC-1",
          patient: {
            id: "pat-1",
            human_friendly_id: "PAT-1",
            first_name: "Ada",
            last_name: "Lovelace",
            contacts: []}}};
      followUpRepository.findById.mockResolvedValue(mockFollowUp);

      const result = await getFollowUpById("fu-1", "user-1", "127.0.0.1");

      expect(result).toEqual(
        expect.objectContaining({
          id: "FU-1",
          patient_id: "PAT-1",
          patient_display_name: "Ada Lovelace",
          patient_primary_phone: null})
      );
    });

    it("should throw HttpError if not found", async () => {
      followUpRepository.findById.mockResolvedValue(null);

      await expect(
        getFollowUpById("fu-1", "user-1", "127.0.0.1"),
      ).rejects.toThrow(HttpError);
    });

    it("looks up the follow-up inside the actor tenant", async () => {
      followUpRepository.findById.mockResolvedValue({
        id: "fu-1",
        human_friendly_id: "FU-1",
        encounter_id: "enc-1",
        status: "SCHEDULED",
        encounter: {
          id: "enc-1",
          human_friendly_id: "ENC-1",
          tenant_id: "tenant-1",
          patient: {
            id: "pat-1",
            human_friendly_id: "PAT-1",
            first_name: "Ada",
            last_name: "Lovelace",
            contacts: [],
          },
        },
      });

      await getFollowUpById("fu-1", "user-1", "127.0.0.1", {
        tenant_id: "tenant-1",
      });

      expect(followUpRepository.findById).toHaveBeenCalledWith(
        "fu-1",
        expect.objectContaining({ encounter: expect.any(Object) }),
        {
          encounter: {
            tenant_id: "tenant-1",
            deleted_at: null,
          },
        },
      );
    });
  });

  describe("createFollowUp", () => {
    it("should create follow-up and audit log", async () => {
      const mockFollowUp = { id: "fu-1" };
      followUpRepository.create.mockResolvedValue(mockFollowUp);
      resolveIdentifierForPayload.mockResolvedValue("encounter-uuid-1");

      const result = await createFollowUp(
        { encounter_id: "ENC000001", scheduled_at: "2026-01-25" },
        "user-1",
        "127.0.0.1",
      );

      expect(result).toEqual(mockFollowUp);
      expect(resolveIdentifierForPayload).toHaveBeenCalledWith({
        value: "ENC000001",
        field: "encounter_id",
        model: "encounter",
        where: { deleted_at: null }});
      expect(followUpRepository.create).toHaveBeenCalledWith(
        expect.objectContaining({
          encounter_id: "encounter-uuid-1",
          status: "SCHEDULED"}),
      );
      expect(createAuditLog).toHaveBeenCalled();
    });

    it("should reject a second scheduled follow-up for the same patient", async () => {
      resolveIdentifierForPayload.mockResolvedValue("encounter-uuid-2");
      prisma.encounter.findFirst.mockResolvedValue({
        id: "encounter-uuid-2",
        patient_id: "patient-1"});
      prisma.follow_up.findFirst.mockResolvedValue({ id: "fu-existing" });

      await expect(
        createFollowUp(
          { encounter_id: "ENC000002", scheduled_at: "2026-01-26" },
          "user-1",
          "127.0.0.1",
        ),
      ).rejects.toMatchObject({
        messageKey: "errors.follow_up.already_scheduled",
        statusCode: 409});
      expect(followUpRepository.create).not.toHaveBeenCalled();
    });
  });

  describe("updateFollowUp", () => {
    it("should update follow-up and audit log", async () => {
      const mockBefore = { id: "fu-1", notes: "Old notes" };
      const mockAfter = { id: "fu-1", notes: "New notes" };
      followUpRepository.findById.mockResolvedValue(mockBefore);
      followUpRepository.update.mockResolvedValue(mockAfter);

      const result = await updateFollowUp(
        "fu-1",
        { notes: "New notes" },
        "user-1",
        "127.0.0.1",
      );

      expect(result).toEqual(mockAfter);
      expect(createAuditLog).toHaveBeenCalled();
    });

    it("should throw HttpError if not found", async () => {
      followUpRepository.findById.mockResolvedValue(null);

      await expect(
        updateFollowUp("fu-1", {}, "user-1", "127.0.0.1"),
      ).rejects.toThrow(HttpError);
    });
  });

  describe("deleteFollowUp", () => {
    it("should soft delete follow-up and audit log", async () => {
      const mockFollowUp = { id: "fu-1" };
      followUpRepository.findById.mockResolvedValue(mockFollowUp);
      followUpRepository.softDelete.mockResolvedValue(mockFollowUp);

      await deleteFollowUp("fu-1", "user-1", "127.0.0.1");

      expect(followUpRepository.softDelete).toHaveBeenCalledWith("fu-1");
      expect(createAuditLog).toHaveBeenCalled();
    });

    it("should throw HttpError if not found", async () => {
      followUpRepository.findById.mockResolvedValue(null);

      await expect(
        deleteFollowUp("fu-1", "user-1", "127.0.0.1"),
      ).rejects.toThrow(HttpError);
    });
  });

  describe("dispatchFollowUpReminders", () => {
    it("routes IPD medication reminders back to the medication panel and emits realtime notifications", async () => {
      prisma.follow_up.findMany.mockResolvedValue([
        {
          id: "fu-ipd-1",
          human_friendly_id: "FU-001",
          scheduled_at: new Date("2026-03-04T10:00:00.000Z"),
          status: "SCHEDULED",
          reminder_due_sent_at: null,
          reminder_24h_sent_at: null,
          notes:
            "Paracetamol 500 mg reminder 1/3 | BID\n" +
            'IPD_MEDICATION_REMINDER::{"kind":"IPD_MEDICATION_REMINDER","admission_public_id":"ADM-001","encounter_public_id":"ENC-001","prescription_public_id":"RX-001","medication_label":"Paracetamol 500 mg","dose":"500","unit":"mg","route":"ORAL","frequency":"BID","occurrence":1,"total_occurrences":3}',
          encounter: {
            tenant_id: "tenant-1",
            facility_id: "facility-1",
            provider_user_id: "doctor-1",
            patient: {
              first_name: "Jane",
              last_name: "Doe"}}}]);
      prisma.user_role.findMany.mockResolvedValue([
        { user_id: "doctor-1" },
        { user_id: "nurse-1" }]);

      const result = await dispatchFollowUpReminders({
        tenant_id: "tenant-1",
        user_id: "dispatcher-1"});

      expect(prisma.notification.create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            target_path: "/ipd?id=ADM-001&panel=medication",
            context_type: "ipd_medication_reminder",
            context_public_id: "ADM-001"})}),
      );
      expect(emitToUser).toHaveBeenCalledWith(
        "doctor-1",
        "notification.created",
        expect.objectContaining({
          target_path: "/ipd?id=ADM-001&panel=medication"}),
      );
      expect(prisma.follow_up.update).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: "fu-ipd-1" },
          data: { reminder_due_sent_at: expect.any(Date) }}),
      );
      expect(result.sent_due).toBe(1);
      expect(result.sent_24h).toBe(0);
    });
  });
});
