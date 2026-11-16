import { DailyPatientUpdateService } from './daily-patient-update.service';
import { newPatientsUpdate } from './notification-templates';

const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('newPatientsUpdate', () => {
  it('opens the Jobs tab and states the real count', () => {
    const message = newPatientsUpdate(3);
    expect(message.route).toBe('/caregiver/jobs');
    expect(message.body).toContain('3 new patients joined');
    expect(newPatientsUpdate(1).body).toContain('1 new patient joined');
  });
});

describe('DailyPatientUpdateService', () => {
  let usersRepo: any;
  let claimsRepo: any;
  let fcmService: any;
  let service: DailyPatientUpdateService;

  beforeEach(() => {
    usersRepo = {
      countIndividualsRegisteredSince: jest.fn().mockResolvedValue(3),
      listCaregiverFcmTokens: jest.fn().mockResolvedValue(['c1', 'c2']),
    };
    claimsRepo = { claim: jest.fn().mockResolvedValue(true) };
    fcmService = { broadcastToTokens: jest.fn().mockImplementation(async (tokens: string[]) => tokens.length) };
    service = new DailyPatientUpdateService(usersRepo, claimsRepo, fcmService);
  });

  it('sends the REAL count of new patients to caregivers who can apply', async () => {
    const now = ist('2026-11-16T10:30:00');
    expect(await service.run(now)).toBe(2);
    expect(usersRepo.countIndividualsRegisteredSince).toHaveBeenCalledWith(new Date(now.getTime() - 24 * 3600 * 1000));
    expect(usersRepo.listCaregiverFcmTokens).toHaveBeenCalledWith(null);
    expect(fcmService.broadcastToTokens).toHaveBeenCalledWith(
      ['c1', 'c2'],
      'New patients on JustHeal',
      expect.stringContaining('3 new patients joined'),
      { route: '/caregiver/jobs' },
    );
    expect(claimsRepo.claim).toHaveBeenCalledWith('new_patients_update', '2026-11-16', { count: 3 });
  });

  it('sends nothing, and claims nothing, on a day with zero new patients', async () => {
    usersRepo.countIndividualsRegisteredSince.mockResolvedValue(0);
    expect(await service.run(ist('2026-11-16T10:30:00'))).toBeNull();
    expect(claimsRepo.claim).not.toHaveBeenCalled();
    expect(fcmService.broadcastToTokens).not.toHaveBeenCalled();
  });

  it('sends nothing when the day was already claimed', async () => {
    claimsRepo.claim.mockResolvedValue(false);
    expect(await service.run(ist('2026-11-16T10:30:00'))).toBeNull();
    expect(fcmService.broadcastToTokens).not.toHaveBeenCalled();
  });

  it('does nothing outside 08:00-21:00 IST', async () => {
    expect(await service.run(ist('2026-11-16T22:00:00'))).toBeNull();
    expect(usersRepo.countIndividualsRegisteredSince).not.toHaveBeenCalled();
  });

  it('never throws if sending fails', async () => {
    fcmService.broadcastToTokens.mockRejectedValue(new Error('fcm down'));
    await expect(service.run(ist('2026-11-16T10:30:00'))).resolves.toBeNull();
  });
});
