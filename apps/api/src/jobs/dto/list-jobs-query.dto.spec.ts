import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ListJobsQueryDto } from './list-jobs-query.dto';

describe('ListJobsQueryDto exclude_closed', () => {
  const parse = (query: Record<string, string>) => plainToInstance(ListJobsQueryDto, query);

  it("reads the query string 'true' as true and 'false' as false", () => {
    expect(parse({ exclude_closed: 'true' }).exclude_closed).toBe(true);
    expect(parse({ exclude_closed: 'false' }).exclude_closed).toBe(false);
  });

  it('is optional', async () => {
    const dto = parse({});
    expect(dto.exclude_closed).toBeUndefined();
    expect(await validate(dto)).toHaveLength(0);
  });
});
