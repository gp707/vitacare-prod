import { Equals, IsIn } from 'class-validator';
import { Qualification } from '@vitacare/shared-constants';

/**
 * Religion and preferred_cities are intentionally NOT here — both are now
 * collected once at registration (RegisterDto). Religion is locked from
 * further self-edit; preferred_cities remains editable via the separate
 * self-edit endpoint (EditAdvancedProfileDto). father_name, father_phone,
 * current_address, and notes have been removed from the product entirely.
 */
export class SubmitAdvancedDetailsDto {
  @IsIn(Object.values(Qualification), { message: 'PROFILE_018' })
  highest_qualification!: Qualification;

  @Equals(true, { message: 'PROFILE_009' })
  terms_accepted!: boolean;
}
