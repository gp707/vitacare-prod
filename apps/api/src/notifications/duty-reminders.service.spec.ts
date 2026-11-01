import { DutyRemindersService } from './duty-reminders.service';

const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('DutyRemindersService', () => {
  let applicationsRepo: any;
  let fcmService: any;
  let service: DutyRemindersService;

  const candidate = (overrides: Record<string, unknown> = {}) => ({
    application_id: 'app-1',
    user_id: 'cg-1',
    start_date: '2026-11-06',
    duty_type: 'day_duty', // starts 08:00 IST
    area: 'Indiranagar',
    city: 'bangalore',
    admin_job_number: null,
    patient_job_number: 512,
    duty_reminder_2d_at: null,
    duty_reminder_1d_at: null,
    duty_reminder_12h_at: null,
    ...overrides,
  });

  beforeEach(() => {
    applicationsRepo = {
      listAcceptedStartingBetween: jest.fn(),
      claimDutyReminder: jest.fn().mockResolvedValue(true),
    };
    fcmService = { sendToUser: jest.fn().mockResolvedValue(undefined) };
    service = new DutyRemindersService(applicationsRepo, fcmService);
  });

  it('sends the 2-day reminder with the right words and tap target', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate()]);
    // 40h before the 08:00 start, mid-day IST.
    const sent = await service.sweep(ist('2026-11-04T16:00:00'));
    expect(sent).toBe(1);
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledWith('app-1', '2d');
    expect(fcmService.sendToUser).toHaveBeenCalledWith(
      'cg-1',
      'Duty in 2 days',
      'You need to go to work in 2 days. PAT-JOB-512 · Indiranagar, Bangalore',
      { route: '/caregiver/my-jobs' },
    );
  });

  it('sends the 1-day reminder', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate({ duty_reminder_2d_at: new Date() })]);
    await service.sweep(ist('2026-11-05T12:00:00')); // 20h before
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledWith('app-1', '1d');
    expect(fcmService.sendToUser.mock.calls[0][2]).toContain('in 1 day');
  });

  it('sends the final "go on duty soon — do not forget" reminder under 12 hours', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([
      candidate({ duty_reminder_2d_at: new Date(), duty_reminder_1d_at: new Date() }),
    ]);
    await service.sweep(ist('2026-11-05T20:15:00')); // 11h45m before
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledWith('app-1', '12h');
    expect(fcmService.sendToUser.mock.calls[0][1]).toBe('Duty starting soon');
    expect(fcmService.sendToUser.mock.calls[0][2]).toContain('Do not forget');
  });

  it('sends nothing more than 48 hours out, or once the duty has started', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate()]);
    expect(await service.sweep(ist('2026-11-03T12:00:00'))).toBe(0);
    expect(await service.sweep(ist('2026-11-06T09:00:00'))).toBe(0);
    expect(fcmService.sendToUser).not.toHaveBeenCalled();
  });

  it('never repeats a reminder that was already sent', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate({ duty_reminder_2d_at: new Date() })]);
    expect(await service.sweep(ist('2026-11-04T16:00:00'))).toBe(0);
    expect(applicationsRepo.claimDutyReminder).not.toHaveBeenCalled();
  });

  it('sends nothing if another API instance claimed the reminder first', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate()]);
    applicationsRepo.claimDutyReminder.mockResolvedValue(false);
    expect(await service.sweep(ist('2026-11-04T16:00:00'))).toBe(0);
    expect(fcmService.sendToUser).not.toHaveBeenCalled();
  });

  it('holds a routine reminder overnight, then sends the one that is true when the window opens', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate()]);
    // 23:30 IST, 32.5h before the start: the 2-day reminder is due but it is night.
    expect(await service.sweep(ist('2026-11-04T23:30:00'))).toBe(0);
    expect(fcmService.sendToUser).not.toHaveBeenCalled();
    // 08:30 next morning it is 23.5h out: the caregiver is told "1 day", not a stale "2 days".
    expect(await service.sweep(ist('2026-11-05T08:30:00'))).toBe(1);
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledWith('app-1', '1d');
  });

  it('a caregiver accepted late gets only the reminder that is true now, not the earlier ones', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([candidate()]);
    await service.sweep(ist('2026-11-05T19:00:00')); // 13h before: 1-day band
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledTimes(1);
    expect(applicationsRepo.claimDutyReminder).toHaveBeenCalledWith('app-1', '1d');
  });

  it('keeps going if one reminder fails to send', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockResolvedValue([
      candidate({ application_id: 'a1', user_id: 'c1' }),
      candidate({ application_id: 'a2', user_id: 'c2' }),
    ]);
    fcmService.sendToUser.mockRejectedValueOnce(new Error('fcm down'));
    expect(await service.sweep(ist('2026-11-04T16:00:00'))).toBe(2);
    expect(fcmService.sendToUser).toHaveBeenCalledTimes(2);
  });

  it('a failing database query does not crash the scheduler', async () => {
    applicationsRepo.listAcceptedStartingBetween.mockRejectedValue(new Error('db'));
    await expect(service.sweep(new Date())).resolves.toBe(0);
  });
});
