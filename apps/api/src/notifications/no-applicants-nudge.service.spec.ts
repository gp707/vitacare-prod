import { NoApplicantsNudgeService } from './no-applicants-nudge.service';

const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('NoApplicantsNudgeService', () => {
  let jobsRepo: any;
  let requirementsRepo: any;
  let fcmService: any;
  let service: NoApplicantsNudgeService;

  beforeEach(() => {
    jobsRepo = {
      listNoApplicantNudgeCandidates: jest.fn().mockResolvedValue([]),
      claimNoApplicantNudge: jest.fn().mockResolvedValue(true),
    };
    requirementsRepo = {
      listNoApplicantNudgeCandidates: jest.fn().mockResolvedValue([]),
      claimNoApplicantNudge: jest.fn().mockResolvedValue(true),
    };
    fcmService = { sendToUser: jest.fn().mockResolvedValue(undefined) };
    service = new NoApplicantsNudgeService(jobsRepo, requirementsRepo, fcmService);
  });

  it('nudges a patient whose job has had no applicants for 3 days', async () => {
    jobsRepo.listNoApplicantNudgeCandidates.mockResolvedValue([
      { id: 'job-1', posted_by: 'p1', admin_job_number: null, patient_job_number: 512 },
    ]);
    expect(await service.sweep(ist('2026-11-05T11:00:00'))).toBe(1);
    expect(jobsRepo.listNoApplicantNudgeCandidates).toHaveBeenCalledWith(3);
    expect(fcmService.sendToUser).toHaveBeenCalledWith('p1', 'No applicants yet', expect.stringContaining('PAT-JOB-512'), {
      route: '/home',
    });
  });

  it('nudges an organisation with its own wording and home screen', async () => {
    requirementsRepo.listNoApplicantNudgeCandidates.mockResolvedValue([
      { id: 'req-1', posted_by: 'o1', requirement_number: 507 },
    ]);
    expect(await service.sweep(ist('2026-11-05T11:00:00'))).toBe(1);
    expect(fcmService.sendToUser).toHaveBeenCalledWith('o1', 'No applicants yet', expect.stringContaining('ORG-JOB-507'), {
      route: '/org-home',
    });
  });

  it('only runs 08:00-21:00 IST — nothing is even looked up overnight', async () => {
    expect(await service.sweep(ist('2026-11-05T23:00:00'))).toBe(0);
    expect(await service.sweep(ist('2026-11-05T06:00:00'))).toBe(0);
    expect(jobsRepo.listNoApplicantNudgeCandidates).not.toHaveBeenCalled();
  });

  it('sends nothing if another instance claimed the nudge, or someone applied in the meantime', async () => {
    jobsRepo.listNoApplicantNudgeCandidates.mockResolvedValue([
      { id: 'job-1', posted_by: 'p1', admin_job_number: null, patient_job_number: 512 },
    ]);
    jobsRepo.claimNoApplicantNudge.mockResolvedValue(false);
    expect(await service.sweep(ist('2026-11-05T11:00:00'))).toBe(0);
    expect(fcmService.sendToUser).not.toHaveBeenCalled();
  });

  it('keeps going if one send fails, and survives a database error', async () => {
    jobsRepo.listNoApplicantNudgeCandidates.mockResolvedValue([
      { id: 'a', posted_by: 'p1', admin_job_number: null, patient_job_number: 1 },
      { id: 'b', posted_by: 'p2', admin_job_number: null, patient_job_number: 2 },
    ]);
    fcmService.sendToUser.mockRejectedValueOnce(new Error('fcm'));
    expect(await service.sweep(ist('2026-11-05T11:00:00'))).toBe(2);
    jobsRepo.listNoApplicantNudgeCandidates.mockRejectedValue(new Error('db'));
    await expect(service.sweep(ist('2026-11-05T11:00:00'))).resolves.toBe(0);
  });
});
