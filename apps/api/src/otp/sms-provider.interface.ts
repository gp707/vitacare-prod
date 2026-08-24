export interface SmsProvider {
  /** Must throw (never swallow) on failure — unlike email notifications,
   *  an OTP the user never receives means they simply cannot proceed. */
  sendOtp(phone: string, otp: string): Promise<void>;
}
