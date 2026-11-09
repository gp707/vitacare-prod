import { AdminRejectionsService } from './admin-rejections.service';
import { AdminRejectionsRepository } from '../database/repositories/admin-rejections.repository';
import { ListRejectionsQueryDto } from './dto/list-rejections-query.dto';

describe('AdminRejectionsService', () => {
  const list = jest.fn();
  const service = new AdminRejectionsService({ list } as unknown as AdminRejectionsRepository);

  beforeEach(() => list.mockReset().mockResolvedValue({ items: [{ id: 'x' }], total: 41 }));

  it('passes the filters and trims the search, returning pagination meta', async () => {
    const query = Object.assign(new ListRejectionsQueryDto(), { page: 2, limit: 20, direction: 'poster', search: '  rani ' });
    const result = await service.list(query);
    expect(list).toHaveBeenCalledWith({ direction: 'poster', search: 'rani' }, { page: 2, limit: 20 });
    expect(result.meta).toEqual({ page: 2, limit: 20, total: 41, totalPages: 3 });
    expect(result.data).toHaveLength(1);
  });

  it('treats a blank search as no search', async () => {
    const query = Object.assign(new ListRejectionsQueryDto(), { search: '   ' });
    await service.list(query);
    expect(list.mock.calls[0][0].search).toBeUndefined();
  });
});
