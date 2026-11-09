import { Injectable } from '@nestjs/common';
import { PaginationMeta } from '../common/dto/pagination.dto';
import { AdminRejectionsRepository } from '../database/repositories/admin-rejections.repository';
import { ListRejectionsQueryDto } from './dto/list-rejections-query.dto';

@Injectable()
export class AdminRejectionsService {
  constructor(private readonly repo: AdminRejectionsRepository) {}

  async list(query: ListRejectionsQueryDto) {
    const { items, total } = await this.repo.list(
      { direction: query.direction, search: query.search?.trim() || undefined },
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
