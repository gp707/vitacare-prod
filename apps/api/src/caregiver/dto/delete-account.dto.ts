import { Matches } from 'class-validator';
import { Validation } from '@vitacare/shared-constants';

/** Re-entering the login PIN before an irreversible account deletion —
 *  shared by caregiver/individual/organisation, same reuse precedent as
 *  UpdatePhoneDto/UpdateCodeDto. A wrong code is checked in the service
 *  layer against the stored hash and throws AUTH_008 (the same "Invalid
 *  code" used at login); this decorator only rejects a malformed shape. */
export class DeleteAccountDto {
  @Matches(Validation.CODE_REGEX, { message: 'PROFILE_016' })
  code!: string;
}
