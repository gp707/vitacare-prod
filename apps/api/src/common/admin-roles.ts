import { UserRole } from '@vitacare/shared-constants';

/** Every role that is a back-office (admin-web) account. */
export const ADMIN_ACCOUNT_ROLES: UserRole[] = [
  UserRole.ADMIN,
  UserRole.SUPER_ADMIN,
  UserRole.READ_ONLY_ADMIN,
];

export function isAdminAccountRole(role: string): boolean {
  return (ADMIN_ACCOUNT_ROLES as string[]).includes(role);
}
