import { DailyCaregiverUpdateService } from './daily-caregiver-update.service';
import { NEW_CAREGIVERS_DISPLAY_BONUS, newCaregiversUpdate } from './notification-templates';

const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('newCaregiversUpdate', () => {
  it('uses each account type\'s own home screen', () => {
    expect(newCaregiversUpdate(9, false).route).toBe('/home');
    expect(newCaregiversUpdate(9, true).route).toBe('/org-home');
  });
  it('says how many joined, pluralised', () => {
    expect(newCaregiversUpdate(9, false).body).toContain('9 new caregivers joined');
    expect(newCaregiversUpdate(1, false).body).toContain('1 new caregiver joined');
  });
});

describe('DailyCaregiverUpdateService', () => {
  let usersRepo: any;
  let claimsRepo: any;
  let fcmService: any;
  let service: DailyCaregiverUpdateService;

  beforeEach(() => {
    usersRepo = {
      countCaregiversRegisteredSince: jest.fn().mockResolvedValue(3),
      listFcmTokensByRole: jest.fn().mockImplementation(async (role: string) =>
        role === 'individual' ? ['t1', 't2'] : ['t3'],
      ),
    };
    claimsRepo = { claim: jest.fn().mockResolvedValue(true) };
    fcmService = { broadcastToTokens: jest.fn().mockImplementation(async (tokens: string[]) => tokens.length) };
    service = new DailyCaregiverUpdateService(usersRepo, claimsRepo, fcmService);
  });

  it('shows the real count plus the display bonus, to patients and organisations separately', async () => {
    const result = await service.run(ist('2026-11-16T10:00:00'));
    expect(result).toEqual({ individuals: 2, organisations: 1 });
    const shown = 3 + NEW_CAREGIVERS_DISPLAY_BONUS;
    expect(fcmService.broadcastToTokens).toHaveBeenCalledWith(
      ['t1', 't2'],
      'New caregivers on JustHeal',
      expect.stringContaining(`${shown} new caregivers joined`),
      { route: '/home' },
    );
    expect(fcmService.broadcastToTokens).toHaveBeenCalledWith(
      ['t3'],
      'New caregivers on JustHeal',
      expect.stringContaining(`${shown} new caregivers joined`),
      { route: '/org-home' },
    );
  });

  it('counts the last 24 hours and records real and displayed numbers on the claim', async () => {
    const now = ist('2026-11-16T10:00:00');
    await service.run(now);
    expect(usersRepo.countCaregiversRegisteredSince).toHaveBeenCalledWith(new Date(now.getTime() - 24 * 3600 * 1000));
    expect(claimsRepo.claim).toHaveBeenCalledWith('new_caregivers_update', '2026-11-16', {
      real_count: 3,
      displayed_count: 3 + NEW_CAREGIVERS_DISPLAY_BONUS,
    });
  });

  it('sends nothing when another instance (or an earlier run) already claimed today', async () => {
    claimsRepo.claim.mockResolvedValue(false);
    expect(await service.run(ist('2026-11-16T10:00:00'))).toBeNull();
    expect(fcmService.broadcastToTokens).not.toHaveBeenCalled();
  });

  it('does nothing outside 08:00-21:00 IST', async () => {
    expect(await service.run(ist('2026-11-16T23:30:00'))).toBeNull();
    expect(usersRepo.countCaregiversRegisteredSince).not.toHaveBeenCalled();
    expect(claimsRepo.claim).not.toHaveBeenCalled();
  });

  it('uses the IST calendar day for the claim, not the UTC one', async () => {
    // 00:30 IST on the 17th is still the 16th in UTC, but that is outside the window anyway;
    // 08:15 IST on the 17th is the 16th in UTC and must claim "2026-11-17".
    await service.run(ist('2026-11-17T08:15:00'));
    expect(claimsRepo.claim).toHaveBeenCalledWith('new_caregivers_update', '2026-11-17', expect.anything());
  });

  it('never throws if sending fails', async () => {
    fcmService.broadcastToTokens.mockRejectedValue(new Error('fcm down'));
    await expect(service.run(ist('2026-11-16T10:00:00'))).resolves.toBeNull();
  });
});
