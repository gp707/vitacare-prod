import { isBelowMinVersion } from './app-version';

describe('isBelowMinVersion', () => {
  it.each([
    ['1.0.0', '1.0.1', true],
    ['1.0.1', '1.0.1', false],
    ['1.0.2', '1.0.1', false],
    ['1.9.9', '2.0.0', true],
    ['2.0.0', '1.9.9', false],
    ['1.10.0', '1.9.0', false], // numeric, not alphabetical
    ['1.2', '1.2.0', false], // a short version counts as 1.2.0
    ['1.2', '1.2.1', true],
    ['1', '1.0.0', false],
    ['0.9.9', '1', true],
  ])('%s against minimum %s -> below: %s', (current, min, below) => {
    expect(isBelowMinVersion(current, min)).toBe(below);
  });

  it('never throws on garbage; an unparseable version counts as 0', () => {
    expect(isBelowMinVersion('abc', '1.0.0')).toBe(true);
    expect(isBelowMinVersion('', '0.0.1')).toBe(true);
    expect(isBelowMinVersion('1.0.0', 'abc')).toBe(false);
  });
});
