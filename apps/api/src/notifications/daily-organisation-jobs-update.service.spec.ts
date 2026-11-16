import { DailyOrganisationJobsUpdateService } from './daily-organisation-jobs-update.service';
import { newOrganisationJobsUpdate } from './notification-templates';

const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('newOrganisationJobsUpdate', () => {
  it('opens the Jobs tab and states the real count, pluralised', () => {
    expect(newOrganisationJobsUpdate(3).route).toBe('/caregiver/jobs');
    expect(newOrganisationJobsUpdate(3).body).toContain('3 new jobs');
    expect(newOrganisationJobsUpdate(1).body).toContain('1 new job ');
  });
});

describe('DailyOrganisationJobsUpdateService', () => {
  let requirementsRepo: any;
  let usersRepo: any;
  let claimsRepo: any;
  let fcmService: any;
  let service: DailyOrganisationJobsUpdateService;

  beforeEach(() => {
    requirementsRepo = { countLivePostedSince: jest.fn().mockResolvedValue(2) };
    usersRepo = { listAllCaregiverFcmTokens: jest.fn().mockResolvedValue(['c1', 'c2', 'c3']) };
    claimsRepo = { claim: jest.fn().mockResolvedValue(true) };
    fcmService = { broadcastToTokens: jest.fn().mockImplementation(async (tokens: string[]) => tokens.length) };
    service = new DailyOrganisationJobsUpdateService(requirementsRepo, usersRepo, claimsRepo, fcmService);
  });

  it('sends the REAL count of new organisation jobs to every caregiver', async () => {
    const now = ist('2026-11-16T11:00:00');
    expect(await service.run(now)).toBe(3);
    expect(requirementsRepo.countLivePostedSince).toHaveBeenCalledWith(new Date(now.getTime() - 24 * 3600 * 1000));
    expect(fcmService.broadcastToTokens).toHaveBeenCalledWith(
      ['c1', 'c2', 'c3'],
      'New hospital & clinic jobs',
      expect.stringContaining('2 new jobs'),
      { route: '/caregiver/jobs' },
    );
    expect(claimsRepo.claim).toHaveBeenCalledWith('new_organisation_jobs_update', '2026-11-16', { count: 2 });
  });

  it('sends nothing, and claims nothing, on a day with zero new organisation jobs', async () => {
    requirementsRepo.countLivePostedSince.mockResolvedValue(0);
    expect(await service.run(ist('2026-11-16T11:00:00'))).toBeNull();
    expect(claimsRepo.claim).not.toHaveBeenCalled();
    expect(fcmService.broadcastToTokens).not.toHaveBeenCalled();
  });

  it('sends nothing when the day was already claimed', async () => {
    claimsRepo.claim.mockResolvedValue(false);
    expect(await service.run(ist('2026-11-16T11:00:00'))).toBeNull();
    expect(fcmService.broadcastToTokens).not.toHaveBeenCalled();
  });

  it('does nothing outside 08:00-21:00 IST', async () => {
    expect(await service.run(ist('2026-11-16T22:00:00'))).toBeNull();
    expect(requirementsRepo.countLivePostedSince).not.toHaveBeenCalled();
  });

  it('never throws if sending fails', async () => {
    fcmService.broadcastToTokens.mockRejectedValue(new Error('fcm down'));
    await expect(service.run(ist('2026-11-16T11:00:00'))).resolves.toBeNull();
  });
});
