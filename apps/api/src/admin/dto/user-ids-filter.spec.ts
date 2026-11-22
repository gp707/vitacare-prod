import 'reflect-metadata';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ListIndividualsQueryDto } from './list-individuals-query.dto';
import { ListOrganisationsQueryDto } from './list-organisations-query.dto';

const ID_A = '3f2b8c1e-9d4a-4c11-8a55-0b2a7d9e1c01';
const ID_B = '8a7d6c5b-4e3f-4a2b-9c1d-0e9f8a7b6c02';

describe.each([
  ['individuals', ListIndividualsQueryDto],
  ['organisations', ListOrganisationsQueryDto],
])('%s list: user_ids filter', (_name, Dto) => {
  it('accepts a comma-separated list of account ids', async () => {
    const dto = plainToInstance(Dto as any, { user_ids: `${ID_A},${ID_B}` }) as any;
    expect(await validate(dto)).toHaveLength(0);
    expect(dto.user_ids).toEqual([ID_A, ID_B]);
  });

  it('is optional', async () => {
    const dto = plainToInstance(Dto as any, {}) as any;
    expect(await validate(dto)).toHaveLength(0);
    expect(dto.user_ids).toBeUndefined();
  });

  it('rejects something that is not an id', async () => {
    const dto = plainToInstance(Dto as any, { user_ids: `${ID_A},not-an-id` }) as any;
    expect((await validate(dto)).length).toBeGreaterThan(0);
  });
});
