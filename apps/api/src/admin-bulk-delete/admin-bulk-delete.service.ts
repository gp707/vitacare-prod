import { Injectable } from '@nestjs/common';
import { AuditAction } from '@vitacare/shared-constants';
import { DatabaseService } from '../database/database.service';
import { JobsRepository } from '../database/repositories/jobs.repository';
import { OrganisationRequirementsRepository } from '../database/repositories/organisation-requirements.repository';
import { AuditService } from '../audit/audit.service';
import { BulkDeleteJobsDto } from './dto/bulk-delete-jobs.dto';

export interface BulkDeleteResult {
  jobs_deleted: number;
  requirements_deleted: number;
  applications_deleted: number;
}

/** Super-admin-only permanent bulk delete for admin-web's merged Jobs
 *  screen — the screen shows rows from two entirely separate tables
 *  (see CLAUDE.md's "NurseNow" section: admin/individual jobs live in
 *  `jobs`, organisation postings live in `organisation_requirements`), so
 *  one call here can delete a mix of both, split by [dto.items[].type].
 *  Fully transactional: either every selected row (and its cascaded
 *  applications, and — for jobs — its now-orphaned care_receiver) is
 *  deleted, or nothing is. */
@Injectable()
export class AdminBulkDeleteService {
  constructor(
    private readonly db: DatabaseService,
    private readonly jobsRepo: JobsRepository,
    private readonly organisationRequirementsRepo: OrganisationRequirementsRepository,
    private readonly auditService: AuditService,
  ) {}

  async bulkDelete(adminId: string, dto: BulkDeleteJobsDto, ipAddress: string | null): Promise<BulkDeleteResult> {
    const jobIds = dto.items.filter((item) => item.type === 'job').map((item) => item.id);
    const requirementIds = dto.items
      .filter((item) => item.type === 'organisation_requirement')
      .map((item) => item.id);

    const { deletedJobs, deletedRequirements, applicationsDeleted } = await this.db.withTransaction(
      async (client) => {
        // Counted before deleting — the cascade itself doesn't return a
        // count, and after the delete these rows are gone.
        const jobApplicationsCount = await this.jobsRepo.countApplicationsForJobs(jobIds, client);
        const requirementApplicationsCount = await this.organisationRequirementsRepo.countApplicationsForRequirements(
          requirementIds,
          client,
        );

        const deletedJobs = await this.jobsRepo.bulkDelete(jobIds, client);
        const deletedRequirements = await this.organisationRequirementsRepo.bulkDelete(requirementIds, client);

        return {
          deletedJobs,
          deletedRequirements,
          applicationsDeleted: jobApplicationsCount + requirementApplicationsCount,
        };
      },
    );

    // Audit logging is best-effort, outside the transaction — same
    // convention as every other mutating action in this codebase (a
    // logging failure must never roll back a legitimate admin action).
    await this.auditService.log({
      userId: adminId,
      action: AuditAction.JOBS_BULK_DELETED,
      entityType: 'jobs',
      beforeValue: {
        job_ids: deletedJobs.map((job) => job.id),
        requirement_ids: deletedRequirements.map((requirement) => requirement.id),
        jobs_deleted: deletedJobs.length,
        requirements_deleted: deletedRequirements.length,
        applications_deleted: applicationsDeleted,
      },
      afterValue: null,
      ipAddress,
    });

    return {
      jobs_deleted: deletedJobs.length,
      requirements_deleted: deletedRequirements.length,
      applications_deleted: applicationsDeleted,
    };
  }
}
