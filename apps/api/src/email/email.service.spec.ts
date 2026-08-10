import { EmailService } from './email.service';

const sendMail = jest.fn();

jest.mock('nodemailer', () => ({
  createTransport: jest.fn(() => ({ sendMail })),
}));

describe('EmailService', () => {
  let service: EmailService;
  let configService: any;

  const config: Record<string, string> = {
    SMTP_HOST: 'smtp.gmail.com',
    SMTP_USER: 'vitacasahealthindia@gmail.com',
    SMTP_PASSWORD: 'app-password',
    ADMIN_NOTIFICATION_EMAIL: 'vitacasahealthindia@gmail.com',
  };

  beforeEach(() => {
    sendMail.mockReset().mockResolvedValue(undefined);
    configService = {
      getOrThrow: jest.fn((key: string) => config[key]),
      get: jest.fn(() => undefined),
    };
    service = new EmailService(configService);
    service.onModuleInit();
  });

  it('sends a plain-text email via the configured transport', async () => {
    await service.send('caregiver@example.com', 'Subject', 'Body text');
    expect(sendMail).toHaveBeenCalledWith({
      from: 'vitacasahealthindia@gmail.com',
      to: 'caregiver@example.com',
      subject: 'Subject',
      text: 'Body text',
    });
  });

  it('sendToAdmin sends to the configured admin notification address', async () => {
    await service.sendToAdmin('Subject', 'Body text');
    expect(sendMail).toHaveBeenCalledWith(
      expect.objectContaining({ to: 'vitacasahealthindia@gmail.com' }),
    );
  });

  it('swallows transport errors so a notification failure never throws', async () => {
    sendMail.mockRejectedValueOnce(new Error('SMTP down'));
    await expect(service.send('x@y.com', 'S', 'B')).resolves.toBeUndefined();
  });
});
