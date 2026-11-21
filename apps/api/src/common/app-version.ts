/**
 * Compares dotted app versions ("1.2.0", or a shorter "1.2" — missing parts count as 0). Never throws:
 * an unparseable part counts as 0, so a malformed string just cannot out-rank a real one instead of
 * crashing a launch-time check.
 */
export function isBelowMinVersion(current: string, min: string): boolean {
  const parse = (v: string) => v.split('.').map((part) => parseInt(part, 10) || 0);
  const [c1 = 0, c2 = 0, c3 = 0] = parse(current);
  const [m1 = 0, m2 = 0, m3 = 0] = parse(min);
  if (c1 !== m1) return c1 < m1;
  if (c2 !== m2) return c2 < m2;
  return c3 < m3;
}
