import { AdminAcceptedService } from './admin-accepted.service';
import { AdminAcceptedRepository } from '../database/repositories/admin-accepted.repository';
import { ListAcceptedQueryDto } from './dto/list-accepted-query.dto';

describe('AdminAcceptedService', () => {
  const list = jest.fn();
  const service = new AdminAcceptedService({ list } as unknown as AdminAcceptedRepository);

  beforeEach(() => list.mockReset().mockResolvedValue({ items: [{ id: 'x' }], total: 41 }));

  it('passes the status filter and the trimmed search, and returns pagination meta', async () => {
    const query = Object.assign(new ListAcceptedQueryDto(), { page: 2, limit: 20, status: 'accepted', search: '  NUR-589 ' });
    const result = await service.list(query);
    expect(list).toHaveBeenCalledWith({ status: 'accepted', search: 'NUR-589' }, { page: 2, limit: 20 });
    expect(result.meta).toEqual({ page: 2, limit: 20, total: 41, totalPages: 3 });
    expect(result.data).toHaveLength(1);
  });

  it('treats a blank search as no search and no status as every status', async () => {
    await service.list(Object.assign(new ListAcceptedQueryDto(), { search: '   ' }));
    expect(list.mock.calls[0][0]).toEqual({ status: undefined, search: undefined });
  });
});
