import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { JwtPayload } from '../common/interfaces/jwt-payload.interface';
import { AppEventInput, AppEventsRepository } from '../database/repositories/app-events.repository';
import { InsightsRepository } from '../database/repositories/insights.repository';
import { RecordEventsDto } from './dto/record-events.dto';
import {
  ActiveUsersQueryDto,
  InactiveSinceRegistrationQueryDto,
  PagedInsightsQueryDto,
  TopActionsQueryDto,
} from './dto/insights-query.dto';

/** How long usage events are kept. Insights only ever looks back at most
 *  90 days (TopActionsQueryDto.days), so anything older is dead weight. */
const EVENT_RETENTION_DAYS = 90;

/** A device clock can be wrong, and events are batched so they arrive late.
 *  Accept timestamps up to this far in the past, and never in the future —
 *  anything outside is replaced by the server's own "now" so a bad clock
 *  can't poison "active in the last 24h" or the retention sweep. */
const MAX_EVENT_AGE_MS = 24 * 60 * 60 * 1000;

const PAGE_ONE_SINGLE: PagedInsightsQueryDto = { page: 1, limit: 1 };

@Injectable()
export class InsightsService {
  private readonly logger = new Logger(InsightsService.name);

  constructor(
    private readonly appEventsRepo: AppEventsRepository,
    private readonly insightsRepo: InsightsRepository,
  ) {}

  /** POST /events. [user] is undefined for an anonymous (pre-login) sender. */
  async recordEvents(dto: RecordEventsDto, user: JwtPayload | undefined): Promise<{ accepted: number }> {
    const now = Date.now();
    const events: AppEventInput[] = dto.events.map((event) => {
      const parsed = event.occurred_at ? Date.parse(event.occurred_at) : NaN;
      const valid = !Number.isNaN(parsed) && parsed <= now && now - parsed <= MAX_EVENT_AGE_MS;
      return {
        kind: event.kind,
        flow: event.flow,
        screen: event.screen,
        action: event.kind === 'tap' ? (event.action ?? null) : null,
        occurredAt: new Date(valid ? parsed : now),
      };
    });
    await this.appEventsRepo.insertMany(events, user?.sub ?? null, user?.role ?? null);
    return { accepted: events.length };
  }

  /** One round-trip for the screen's headline cards: each count is the same
   *  query its own tab runs, just with a page size of 1 so only `total`
   *  matters. */
  async getSummary() {
    const [active24, active48, active168, inactive, posters, caregivers] = await Promise.all([
      this.insightsRepo.listActiveUsers({ ...PAGE_ONE_SINGLE, hours: 24 }),
      this.insightsRepo.listActiveUsers({ ...PAGE_ONE_SINGLE, hours: 48 }),
      this.insightsRepo.listActiveUsers({ ...PAGE_ONE_SINGLE, hours: 168 }),
      this.insightsRepo.listInactiveSinceRegistration({ ...PAGE_ONE_SINGLE, minAgeHours: 24 }),
      this.insightsRepo.listPostersWithoutAccepted(PAGE_ONE_SINGLE),
      this.insightsRepo.listCaregiversNeverApplied(PAGE_ONE_SINGLE),
    ]);
    return {
      active_users_24h: active24.total,
      active_users_48h: active48.total,
      active_users_7d: active168.total,
      inactive_since_registration: inactive.total,
      posters_without_accepted: posters.total,
      caregivers_never_applied: caregivers.total,
    };
  }

  async listActiveUsers(query: ActiveUsersQueryDto) {
    const { items, total } = await this.insightsRepo.listActiveUsers({
      page: query.page,
      limit: query.limit,
      hours: query.hours,
      role: query.role,
    });
    return this.paged(items, total, query);
  }

  async listInactiveSinceRegistration(query: InactiveSinceRegistrationQueryDto) {
    const { items, total } = await this.insightsRepo.listInactiveSinceRegistration({
      page: query.page,
      limit: query.limit,
      minAgeHours: query.min_age_hours,
      role: query.role,
    });
    return this.paged(items, total, query);
  }

  async listPostersWithoutAccepted(query: PagedInsightsQueryDto) {
    const { items, total } = await this.insightsRepo.listPostersWithoutAccepted(query);
    return this.paged(items, total, query);
  }

  async listCaregiversNeverApplied(query: PagedInsightsQueryDto) {
    const { items, total } = await this.insightsRepo.listCaregiversNeverApplied(query);
    return this.paged(items, total, query);
  }

  async getTopActions(query: TopActionsQueryDto) {
    return this.appEventsRepo.topActions({
      kind: query.kind,
      days: query.days,
      flow: query.flow,
      limit: query.limit,
    });
  }

  /** Daily 3:30 AM IST — same shape as the audit/error-log sweeps, offset
   *  so the three never start in the same instant. */
  @Cron('30 3 * * *', { timeZone: 'Asia/Kolkata' })
  async purgeExpiredEvents(): Promise<void> {
    const cutoff = new Date(Date.now() - EVENT_RETENTION_DAYS * 24 * 60 * 60 * 1000);
    const deleted = await this.appEventsRepo.deleteOlderThan(cutoff);
    if (deleted === 0) return;
    this.logger.log(`Purged ${deleted} app_events row(s) older than ${cutoff.toISOString()}`);
  }

  private paged<T>(items: T[], total: number, query: PagedInsightsQueryDto) {
    return {
      data: items,
      meta: { page: query.page, limit: query.limit, total, totalPages: Math.ceil(total / query.limit) },
    };
  }
}
