import { Injectable } from '@nestjs/common';
import { AdminReportsRepository } from '../database/repositories/admin-reports.repository';

@Injectable()
export class AdminReportsService {
  constructor(private readonly reportsRepo: AdminReportsRepository) {}

  findUnassignedOrNoDutyCaregivers() {
    return this.reportsRepo.findUnassignedOrNoDutyCaregivers();
  }

  findStalledDuty(days: number) {
    return this.reportsRepo.findStalledDuty(days);
  }

  findOverThresholdActiveCaregivers(minJobs: number) {
    return this.reportsRepo.findOverThresholdActiveCaregivers(minJobs);
  }

  findCaregiverActivity(days: number, order: 'asc' | 'desc') {
    return this.reportsRepo.findCaregiverActivity(days, order);
  }

  findPatientsWithNoApplicants(days: number) {
    return this.reportsRepo.findPatientsWithNoApplicants(days);
  }

  findPatientsWithNoPendingCandidate() {
    return this.reportsRepo.findPatientsWithNoPendingCandidate();
  }

  findPatientsWithUnconvertedApplicants() {
    return this.reportsRepo.findPatientsWithUnconvertedApplicants();
  }

  findPatientActivity(days: number, order: 'asc' | 'desc') {
    return this.reportsRepo.findPatientActivity(days, order);
  }

  findOrganisationsWithNoJobsPosted() {
    return this.reportsRepo.findOrganisationsWithNoJobsPosted();
  }

  findOrganisationsWithNoApplicants(days: number) {
    return this.reportsRepo.findOrganisationsWithNoApplicants(days);
  }

  findOrganisationsWithUnconvertedApplicants() {
    return this.reportsRepo.findOrganisationsWithUnconvertedApplicants();
  }

  findOrganisationActivity(days: number, order: 'asc' | 'desc') {
    return this.reportsRepo.findOrganisationActivity(days, order);
  }
}
