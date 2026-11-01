import {
  accountBlocked,
  accountUnblocked,
  applicationAccepted,
  caregiverClosedEngagement,
  changedAny,
  jobCancelled,
  jobNoLongerOpen,
  jobUpdated,
  JOB_APPLICANT_FIELDS,
  noApplicantsYet,
  applicationDeclined,
  caregiverApplied,
  dutyReminder,
  dutyReminderStage,
  dutyStartAt,
  inSendWindow,
  jobDisplayId,
  nextWindowOpen,
  organisationJobDisplayId,
  PushRoutes,
  shouldDefer,
  stagesUsedBy,
} from './notification-templates';

const H = 60 * 60 * 1000;
// IST helper: build a Date from an IST wall-clock time.
const ist = (iso: string) => new Date(`${iso}+05:30`);

describe('dutyStartAt', () => {
  it('day and live-in shifts start at 08:00 IST, night at 20:00 IST', () => {
    expect(dutyStartAt('2026-11-05', 'day_duty').toISOString()).toBe(ist('2026-11-05T08:00:00').toISOString());
    expect(dutyStartAt('2026-11-05', 'live_in').toISOString()).toBe(ist('2026-11-05T08:00:00').toISOString());
    expect(dutyStartAt('2026-11-05', 'night_duty').toISOString()).toBe(ist('2026-11-05T20:00:00').toISOString());
  });

  it('accepts a full ISO timestamp from the database and uses only the date', () => {
    expect(dutyStartAt('2026-11-05T00:00:00.000Z', 'day_duty').toISOString()).toBe(
      ist('2026-11-05T08:00:00').toISOString(),
    );
  });
});

describe('dutyReminderStage', () => {
  it.each([
    [49 * H, null],
    [48 * H, '2d'],
    [30 * H, '2d'],
    [24 * H + 1, '2d'],
    [24 * H, '1d'],
    [13 * H, '1d'],
    [12 * H + 1, '1d'],
    [12 * H, '12h'],
    [1 * H, '12h'],
    [1, '12h'],
    [0, null],
    [-5 * H, null],
  ])('%d ms left -> %s', (remaining, expected) => {
    expect(dutyReminderStage(remaining)).toBe(expected);
  });

  it('sending a stage uses up every less urgent one', () => {
    expect(stagesUsedBy('2d')).toEqual(['2d']);
    expect(stagesUsedBy('1d')).toEqual(['1d', '2d']);
    expect(stagesUsedBy('12h')).toEqual(['12h', '1d', '2d']);
  });
});

describe('send window (08:00-21:00 IST)', () => {
  it('is open from 08:00 up to but not including 21:00', () => {
    expect(inSendWindow(ist('2026-11-05T07:59:00'))).toBe(false);
    expect(inSendWindow(ist('2026-11-05T08:00:00'))).toBe(true);
    expect(inSendWindow(ist('2026-11-05T20:59:00'))).toBe(true);
    expect(inSendWindow(ist('2026-11-05T21:00:00'))).toBe(false);
    expect(inSendWindow(ist('2026-11-05T00:30:00'))).toBe(false);
  });

  it('finds the next 08:00 IST, today or tomorrow', () => {
    expect(nextWindowOpen(ist('2026-11-05T03:00:00')).toISOString()).toBe(ist('2026-11-05T08:00:00').toISOString());
    expect(nextWindowOpen(ist('2026-11-05T22:00:00')).toISOString()).toBe(ist('2026-11-06T08:00:00').toISOString());
  });

  it('holds routine reminders overnight', () => {
    const start = ist('2026-11-06T08:00:00');
    expect(shouldDefer(ist('2026-11-05T23:00:00'), '2d', start)).toBe(true);
    expect(shouldDefer(ist('2026-11-05T23:00:00'), '1d', start)).toBe(true);
    expect(shouldDefer(ist('2026-11-05T12:00:00'), '1d', start)).toBe(false);
  });

  it('still lets the final reminder out overnight if waiting would be too late', () => {
    // Shift starts 08:00; at 21:30 the next window opens exactly at 08:00 = start, so waiting is too late.
    expect(shouldDefer(ist('2026-11-05T21:30:00'), '12h', ist('2026-11-06T08:00:00'))).toBe(false);
    // Shift starts 20:00; at 03:00 the window opens at 08:00, 12h before start - waiting is fine.
    expect(shouldDefer(ist('2026-11-05T03:00:00'), '12h', ist('2026-11-05T20:00:00'))).toBe(true);
  });
});

describe('messages', () => {
  const job = { display_id: 'PAT-JOB-512', area: 'Indiranagar', city: 'bangalore' };

  it('words the three duty reminders as specified', () => {
    expect(dutyReminder('2d', job).body).toBe('You need to go to work in 2 days. PAT-JOB-512 · Indiranagar, Bangalore');
    expect(dutyReminder('1d', job).body).toBe('You need to go to work in 1 day. PAT-JOB-512 · Indiranagar, Bangalore');
    expect(dutyReminder('12h', job).body).toBe(
      'You need to go on duty soon. Do not forget! PAT-JOB-512 · Indiranagar, Bangalore',
    );
    for (const stage of ['2d', '1d', '12h'] as const) {
      expect(dutyReminder(stage, job).route).toBe(PushRoutes.caregiverMyJobs);
    }
  });

  it('copes with a job that has no area', () => {
    expect(dutyReminder('1d', { display_id: 'ADMIN-JOB-9', city: 'pune' }).body).toBe(
      'You need to go to work in 1 day. ADMIN-JOB-9 · Pune',
    );
  });

  it('builds display ids from whichever number is set', () => {
    expect(jobDisplayId({ admin_job_number: 501, patient_job_number: null })).toBe('ADMIN-JOB-501');
    expect(jobDisplayId({ admin_job_number: null, patient_job_number: 502 })).toBe('PAT-JOB-502');
    expect(organisationJobDisplayId(7)).toBe('ORG-JOB-7');
  });

  it('merges several applicants into one count', () => {
    expect(caregiverApplied('PAT-JOB-1', 1, '/home').title).toBe('A caregiver applied');
    expect(caregiverApplied('PAT-JOB-1', 5, '/home').title).toBe('5 caregivers applied');
  });

  it('includes the decline reason only when there is one', () => {
    expect(applicationDeclined('PAT-JOB-1', 'Found someone closer').body).toContain('Found someone closer');
    expect(applicationDeclined('PAT-JOB-1').body).not.toContain('undefined');
    expect(applicationAccepted('PAT-JOB-1').route).toBe(PushRoutes.caregiverMyJobs);
  });
});

describe('posting-change messages', () => {
  it('tells the poster a caregiver closed out, and whether the job is open again', () => {
    expect(caregiverClosedEngagement('PAT-JOB-5', true, '/home').body).toBe(
      'A caregiver closed their engagement on PAT-JOB-5. It is open for new applicants again.',
    );
    expect(caregiverClosedEngagement('ORG-JOB-5', false, '/org-home').body).toBe(
      'A caregiver closed their engagement on ORG-JOB-5.',
    );
  });

  it('sends an accepted caregiver to MyJobs and a waiting one to Jobs when a job changes', () => {
    expect(jobUpdated('PAT-JOB-5', true).route).toBe(PushRoutes.caregiverMyJobs);
    expect(jobUpdated('PAT-JOB-5', false).route).toBe(PushRoutes.caregiverJobs);
    expect(jobCancelled('PAT-JOB-5').body).toBe('PAT-JOB-5 was cancelled by the employer.');
    expect(jobNoLongerOpen('ORG-JOB-5').body).toBe('ORG-JOB-5 is no longer accepting applications.');
  });

  it('words a block differently for posting and for the whole account', () => {
    expect(accountBlocked('job_posting', '/home').title).toBe('Posting paused');
    expect(accountBlocked('full', '/home').title).toBe('Account blocked');
    expect(accountUnblocked('job_posting', '/org-home').title).toBe('Posting restored');
    expect(accountUnblocked('full', '/org-home').title).toBe('Account restored');
    expect(accountBlocked('full', '/org-home').route).toBe('/org-home');
  });

  it('suggests the right next step in the no-applicants nudge', () => {
    expect(noApplicantsYet('PAT-JOB-5', false).body).toContain('raising the salary');
    expect(noApplicantsYet('PAT-JOB-5', false).route).toBe('/home');
    expect(noApplicantsYet('ORG-JOB-5', true).body).toContain('editing your requirement');
    expect(noApplicantsYet('ORG-JOB-5', true).route).toBe('/org-home');
    expect(noApplicantsYet('PAT-JOB-5', false).body).toContain('3 days');
  });
});

describe('changedAny', () => {
  const job = { city: 'pune', area: 'Baner', duty_type: 'day_duty', start_date: '2030-06-10', salary_amount: '1800' };

  it('is false when nothing an applicant cares about changed', () => {
    expect(changedAny(job, { ...job, description: 'new text' }, JOB_APPLICANT_FIELDS)).toBe(false);
  });

  it.each([
    ['salary_amount', '2000'],
    ['start_date', '2030-06-12'],
    ['duty_type', 'night_duty'],
    ['area', 'Aundh'],
  ])('is true when %s changes', (field, value) => {
    expect(changedAny(job, { ...job, [field]: value }, JOB_APPLICANT_FIELDS)).toBe(true);
  });

  it('treats null and missing as the same, and compares numbers and strings by value', () => {
    expect(changedAny({ salary_amount: null }, {}, ['salary_amount'])).toBe(false);
    expect(changedAny({ n: 5 }, { n: '5' }, ['n'])).toBe(false);
  });
});
