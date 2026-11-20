import { Injectable } from '@nestjs/common';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { AdminAcceptedRepository } from '../database/repositories/admin-accepted.repository';
import { ListAcceptedQueryDto } from './dto/list-accepted-query.dto';

@Injectable()
export class AdminAcceptedService {
  constructor(private readonly repo: AdminAcceptedRepository) {}

  async list(query: ListAcceptedQueryDto) {
    const { items, total } = await this.repo.list(
      { status: query.status, search: query.search?.trim() || undefined },
      { page: query.page, limit: query.limit },
    );
    const meta: PaginationMeta = {
      page: query.page,
      limit: query.limit,
      total,
      totalPages: Math.max(1, Math.ceil(total / query.limit)),
    };
    return { data: items, meta };
  }
}
