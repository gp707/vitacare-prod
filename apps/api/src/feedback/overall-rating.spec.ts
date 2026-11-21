import { overallRating } from './overall-rating';

describe('overallRating (average + one and a half stars, never above 5)', () => {
  it('shows nothing for a caregiver nobody has rated', () => {
    expect(overallRating(null)).toBeNull();
    expect(overallRating(undefined)).toBeNull();
    expect(overallRating(Number.NaN)).toBeNull();
  });

  it.each([
    [1, 2.5],
    [2, 3.5],
    [3, 4.5],
    [2.5, 4],
    [3.2, 4.7],
    [3.33, 4.8], // one decimal
  ])('an average of %s shows as %s', (average, shown) => {
    expect(overallRating(average)).toBe(shown);
  });

  it('is capped at 5: from an average of 3.5 up, it shows 5', () => {
    expect(overallRating(3.5)).toBe(5);
    expect(overallRating(3.9)).toBe(5);
    expect(overallRating(4)).toBe(5);
  });

  it('an average that is already 5 stays 5', () => {
    expect(overallRating(5)).toBe(5);
  });

  it('never goes below the average itself and never above 5', () => {
    for (let a = 1; a <= 5; a += 0.1) {
      const shown = overallRating(a)!;
      expect(shown).toBeGreaterThanOrEqual(Math.min(5, a) - 0.05);
      expect(shown).toBeLessThanOrEqual(5);
    }
  });
});
