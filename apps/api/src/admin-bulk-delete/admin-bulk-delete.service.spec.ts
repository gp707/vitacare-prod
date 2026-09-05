import { AdminBulkDeleteService } from './admin-bulk-delete.service';

describe('AdminBulkDeleteService', () => {
  let service: AdminBulkDeleteService;
  let db: any;
  let jobsRepo: any;
  let organisationRequirementsRepo: any;
  let auditService: any;
  let fakeClient: any;

  beforeEach(() => {
    fakeClient = { query: jest.fn() };
    db = {
      withTransaction: jest.fn((fn: (client: any) => Promise<any>) => fn(fakeClient)),
    };
    jobsRepo = {
      countApplicationsForJobs: jest.fn().mockResolvedValue(0),
      bulkDelete: jest.fn().mockResolvedValue([]),
    };
    organisationRequirementsRepo = {
      countApplicationsForRequirements: jest.fn().mockResolvedValue(0),
      bulkDelete: jest.fn().mockResolvedValue([]),
    };
    auditService = { log: jest.fn() };
    service = new AdminBulkDeleteService(db, jobsRepo, organisationRequirementsRepo, auditService);
  });

  it('splits items by type and deletes each through its own repository', async () => {
    jobsRepo.bulkDelete.mockResolvedValue([{ id: 'job-1' }, { id: 'job-2' }]);
    organisationRequirementsRepo.bulkDelete.mockResolvedValue([{ id: 'req-1' }]);
    jobsRepo.countApplicationsForJobs.mockResolvedValue(3);
    organisationRequirementsRepo.countApplicationsForRequirements.mockResolvedValue(2);

    const result = await service.bulkDelete(
      'admin-1',
      {
        items: [
          { id: 'job-1', type: 'job' },
          { id: 'job-2', type: 'job' },
          { id: 'req-1', type: 'organisation_requirement' },
        ],
        confirm: 'DELETE',
      },
      '127.0.0.1',
    );

    expect(jobsRepo.bulkDelete).toHaveBeenCalledWith(['job-1', 'job-2'], fakeClient);
    expect(organisationRequirementsRepo.bulkDelete).toHaveBeenCalledWith(['req-1'], fakeClient);
    expect(result).toEqual({ jobs_deleted: 2, requirements_deleted: 1, applications_deleted: 5 });
  });

  it('counts applications before deleting (the cascade would otherwise make them uncountable)', async () => {
    await service.bulkDelete(
      'admin-1',
      { items: [{ id: 'job-1', type: 'job' }], confirm: 'DELETE' },
      null,
    );

    // Both the count and the delete calls run inside the same transaction
    // client, in that order (count first).
    const countOrder = jobsRepo.countApplicationsForJobs.mock.invocationCallOrder[0];
    const deleteOrder = jobsRepo.bulkDelete.mock.invocationCallOrder[0];
    expect(countOrder).toBeLessThan(deleteOrder);
  });

  it('runs everything inside a single transaction', async () => {
    await service.bulkDelete(
      'admin-1',
      { items: [{ id: 'job-1', type: 'job' }], confirm: 'DELETE' },
      null,
    );
    expect(db.withTransaction).toHaveBeenCalledTimes(1);
  });

  it('audit-logs one entry summarizing the whole bulk operation, after the transaction commits', async () => {
    jobsRepo.bulkDelete.mockResolvedValue([{ id: 'job-1' }]);
    organisationRequirementsRepo.bulkDelete.mockResolvedValue([{ id: 'req-1' }]);
    jobsRepo.countApplicationsForJobs.mockResolvedValue(4);
    organisationRequirementsRepo.countApplicationsForRequirements.mockResolvedValue(1);

    await service.bulkDelete(
      'admin-1',
      {
        items: [
          { id: 'job-1', type: 'job' },
          { id: 'req-1', type: 'organisation_requirement' },
        ],
        confirm: 'DELETE',
      },
      '10.0.0.1',
    );

    expect(auditService.log).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: 'admin-1',
        action: 'jobs_bulk_deleted',
        entityType: 'jobs',
        beforeValue: {
          job_ids: ['job-1'],
          requirement_ids: ['req-1'],
          jobs_deleted: 1,
          requirements_deleted: 1,
          applications_deleted: 5,
        },
        afterValue: null,
        ipAddress: '10.0.0.1',
      }),
    );
  });

  it('handles a jobs-only selection without touching the organisation-requirements repository', async () => {
    await service.bulkDelete(
      'admin-1',
      { items: [{ id: 'job-1', type: 'job' }], confirm: 'DELETE' },
      null,
    );

    expect(organisationRequirementsRepo.bulkDelete).toHaveBeenCalledWith([], fakeClient);
    expect(organisationRequirementsRepo.countApplicationsForRequirements).toHaveBeenCalledWith([], fakeClient);
  });
});
