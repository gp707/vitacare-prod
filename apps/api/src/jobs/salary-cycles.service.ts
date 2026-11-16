import { Injectable } from '@nestjs/common';
import { JobApplicationStatus } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';
import { listSalaryCycles, SalaryCycle } from '../common/salary-cycles';
import { CaregiverProfilesRepository } from '../database/repositories/caregiver-profiles.repository';
import { JobApplicationLeavesRepository } from '../database/repositories/job-application-leaves.repository';
import { JobApplicationRecord, JobApplicationsRepository } from '../database/repositories/job-applications.repository';
import { SalaryCyclePaymentsRepository } from '../database/repositories/salary-cycle-payments.repository';

/** Today's date on the IST calendar (YYYY-MM-DD). */
export const istToday = (): string => new Date(Date.now() + 5.5 * 3600 * 1000).toISOString().slice(0, 10);

/** The cycle-by-cycle salary record of one caregiver on one job, shared by the
 *  patient's and the caregiver's endpoints so both see exactly the same figures. */
@Injectable()
export class SalaryCyclesService {
  constructor(
    private readonly paymentsRepo: SalaryCyclePaymentsRepository,
    private readonly leavesRepo: JobApplicationLeavesRepository,
    private readonly applicationsRepo: JobApplicationsRepository,
    private readonly profilesRepo: CaregiverProfilesRepository,
  ) {}

  /** Paid cycles always; unpaid ones only while the caregiver is still accepted on
   *  the job with the agreement filled in. Newest first. */
  async listForApplication(application: JobApplicationRecord, today = istToday()): Promise<SalaryCycle[]> {
    const paid = await this.paymentsRepo.listByApplication(application.id);
    const active =
      application.status === JobApplicationStatus.ACCEPTED &&
      application.agreed_salary != null &&
      application.agreed_salary_unit != null &&
      application.agreed_start_date != null;
    const leaveDates = active ? (await this.leavesRepo.getState(application.id)).leave_dates : [];
    return listSalaryCycles({
      paid,
      agreement: active
        ? {
            startDate: application.agreed_start_date as string,
            rate: application.agreed_salary as number,
            unit: application.agreed_salary_unit as 'daily' | 'monthly',
            leaveDates,
          }
        : null,
      today,
    });
  }

  /** The signed-in caregiver's own record for one job. */
  async listForCaregiver(userId: string, jobId: string) {
    const profile = await this.profilesRepo.findByUserId(userId);
    if (!profile) throw new AppException('PROFILE_019');
    const application = await this.applicationsRepo.findByJobAndProfile(jobId, profile.id);
    if (!application) return { cycles: [] };
    return { cycles: await this.listForApplication(application) };
  }
}
