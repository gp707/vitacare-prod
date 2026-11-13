import { Injectable } from '@nestjs/common';
import { AppException } from '../common/exceptions/app.exception';

/** Wrong PINs allowed inside the window before the account is paused. */
export const MAX_WRONG_PINS = 7;
/** Only wrong PINs this recent count towards the limit. */
export const WRONG_PIN_WINDOW_MS = 15 * 60_000;
/** How long the account is paused after the latest wrong PIN once the limit is hit. */
export const PIN_LOCK_MS = 5 * 60_000;

/**
 * A 4-digit PIN has only 10,000 possibilities, so guessing has to be slowed
 * down. After {@link MAX_WRONG_PINS} wrong PINs within 15 minutes the account
 * refuses PIN logins until {@link PIN_LOCK_MS} after the latest wrong guess —
 * even a correct PIN is refused during that time, otherwise a guesser would
 * simply keep trying. Every further wrong guess restarts the pause, so a
 * guesser gets roughly one try per 5 minutes after the first 7.
 *
 * Kept in memory, per account (`users.id`), so a burst of parallel requests
 * is counted immediately (a database count would let them all through before
 * the first row is written). Only accounts that exist are ever tracked, so
 * random phone numbers cannot grow it. It resets when the API restarts and
 * is not shared between API instances — fine for a single Render instance;
 * move it to the database if the API is ever scaled out.
 */
@Injectable()
export class LoginThrottleService {
  private readonly wrongPins = new Map<string, number[]>();

  /** Throws AUTH_017 (429) while the account is paused. */
  assertNotLocked(userId: string, now = Date.now()): void {
    const recent = this.recent(userId, now);
    if (recent.length < MAX_WRONG_PINS) return;
    const unlockAt = recent[recent.length - 1] + PIN_LOCK_MS;
    if (now >= unlockAt) return;
    const minutes = Math.max(1, Math.ceil((unlockAt - now) / 60_000));
    throw new AppException(
      'AUTH_017',
      `Too many wrong PINs. Please wait ${minutes} minute${minutes === 1 ? '' : 's'} and try again.`,
    );
  }

  recordWrongPin(userId: string, now = Date.now()): void {
    const recent = this.recent(userId, now);
    recent.push(now);
    this.wrongPins.set(userId, recent);
  }

  /** A correct PIN wipes the slate. */
  clear(userId: string): void {
    this.wrongPins.delete(userId);
  }

  private recent(userId: string, now: number): number[] {
    const kept = (this.wrongPins.get(userId) ?? []).filter((t) => now - t < WRONG_PIN_WINDOW_MS);
    if (kept.length === 0) this.wrongPins.delete(userId);
    return kept;
  }
}
