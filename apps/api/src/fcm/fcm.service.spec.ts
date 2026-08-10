import { FcmService } from './fcm.service';

const send = jest.fn();
const sendEachForMulticast = jest.fn();

jest.mock('firebase-admin/app', () => ({
  initializeApp: jest.fn(() => ({})),
  cert: jest.fn((x) => x),
}));

jest.mock('firebase-admin/messaging', () => ({
  getMessaging: jest.fn(() => ({ send, sendEachForMulticast })),
}));

describe('FcmService', () => {
  let service: FcmService;
  let configService: any;
  let usersRepo: any;

  const config: Record<string, string> = {
    FIREBASE_PROJECT_ID: 'vitacasahealth-caregivers',
    FIREBASE_CLIENT_EMAIL: 'firebase-adminsdk@vitacasahealth-caregivers.iam.gserviceaccount.com',
    FIREBASE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\\nfakekey\\n-----END PRIVATE KEY-----\\n',
  };

  beforeEach(() => {
    send.mockReset().mockResolvedValue('projects/x/messages/1');
    sendEachForMulticast.mockReset().mockResolvedValue({ successCount: 1, failureCount: 0 });
    configService = { getOrThrow: jest.fn((key: string) => config[key]) };
    usersRepo = { findById: jest.fn(), listCaregiverFcmTokens: jest.fn() };
    service = new FcmService(configService, usersRepo);
    service.onModuleInit();
  });

  it('sends a push notification when the user has an fcm_token', async () => {
    usersRepo.findById.mockResolvedValue({ id: 'user-1', fcm_token: 'device-token-abc' });
    await service.sendToUser('user-1', 'Title', 'Body');
    expect(send).toHaveBeenCalledWith({
      token: 'device-token-abc',
      notification: { title: 'Title', body: 'Body' },
    });
  });

  it('no-ops silently when the user has no fcm_token', async () => {
    usersRepo.findById.mockResolvedValue({ id: 'user-1', fcm_token: null });
    await service.sendToUser('user-1', 'Title', 'Body');
    expect(send).not.toHaveBeenCalled();
  });

  it('no-ops silently when the user does not exist', async () => {
    usersRepo.findById.mockResolvedValue(null);
    await service.sendToUser('missing', 'Title', 'Body');
    expect(send).not.toHaveBeenCalled();
  });

  it('swallows send failures so a notification failure never throws', async () => {
    usersRepo.findById.mockResolvedValue({ id: 'user-1', fcm_token: 'device-token-abc' });
    send.mockRejectedValueOnce(new Error('messaging/invalid-registration-token'));
    await expect(service.sendToUser('user-1', 'Title', 'Body')).resolves.toBeUndefined();
  });

  it('broadcasts to every caregiver fcm_token via multicast', async () => {
    usersRepo.listCaregiverFcmTokens.mockResolvedValue(['token-a', 'token-b']);
    await service.sendToAllCaregivers('New Job: Bedside Care', 'Bangalore • 24Hrs (Live-In)');
    expect(sendEachForMulticast).toHaveBeenCalledWith({
      tokens: ['token-a', 'token-b'],
      notification: { title: 'New Job: Bedside Care', body: 'Bangalore • 24Hrs (Live-In)' },
    });
  });

  it('no-ops the broadcast when no caregiver has a token yet', async () => {
    usersRepo.listCaregiverFcmTokens.mockResolvedValue([]);
    await service.sendToAllCaregivers('Title', 'Body');
    expect(sendEachForMulticast).not.toHaveBeenCalled();
  });

  it('swallows broadcast failures so a job post never fails because of push', async () => {
    usersRepo.listCaregiverFcmTokens.mockResolvedValue(['token-a']);
    sendEachForMulticast.mockRejectedValueOnce(new Error('messaging/internal-error'));
    await expect(service.sendToAllCaregivers('Title', 'Body')).resolves.toBeUndefined();
  });

  it('unescapes literal \\n sequences in the private key before initializing', () => {
    const { cert } = jest.requireMock('firebase-admin/app');
    expect(cert).toHaveBeenCalledWith(
      expect.objectContaining({
        privateKey: '-----BEGIN PRIVATE KEY-----\nfakekey\n-----END PRIVATE KEY-----\n',
      }),
    );
  });
});
