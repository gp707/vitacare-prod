import { UserNotificationsService } from './user-notifications.service';

describe('UserNotificationsService', () => {
  let repo: any;
  let service: UserNotificationsService;

  beforeEach(() => {
    repo = { listActiveForUser: jest.fn(), markRead: jest.fn(), purge: jest.fn() };
    service = new UserNotificationsService(repo);
  });

  it('lists the caller\'s own unread, unexpired alerts', async () => {
    const created_at = new Date();
    repo.listActiveForUser.mockResolvedValue([{ id: 'n1', title: 'T', body: 'B', route: '/home', created_at }]);
    await expect(service.list('user-1')).resolves.toEqual([{ id: 'n1', title: 'T', body: 'B', route: '/home', created_at }]);
    expect(repo.listActiveForUser).toHaveBeenCalledWith('user-1');
  });

  it('marking read works only on the caller\'s own unread alert; anything else is GEN_002', async () => {
    repo.markRead.mockResolvedValueOnce(true);
    await expect(service.markRead('user-1', 'n1')).resolves.toEqual({ message: 'Marked as read' });
    expect(repo.markRead).toHaveBeenCalledWith('user-1', 'n1');
    repo.markRead.mockResolvedValueOnce(false);
    await expect(service.markRead('user-1', 'someone-elses')).rejects.toMatchObject({ code: 'GEN_002' });
  });

  it('the nightly purge asks the repository and never throws', async () => {
    repo.purge.mockResolvedValueOnce(3);
    await service.purge();
    expect(repo.purge).toHaveBeenCalled();
    repo.purge.mockRejectedValueOnce(new Error('db'));
    await expect(service.purge()).resolves.toBeUndefined();
  });
});
