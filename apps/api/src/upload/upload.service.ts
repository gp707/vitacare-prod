import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { Config } from '@vitacare/shared-constants';
import { AppException } from '../common/exceptions/app.exception';

@Injectable()
export class UploadService {
  private readonly logger = new Logger(UploadService.name);
  private readonly client: SupabaseClient;

  constructor(configService: ConfigService) {
    this.client = createClient(
      configService.getOrThrow<string>('SUPABASE_URL'),
      configService.getOrThrow<string>('SUPABASE_SERVICE_ROLE_KEY'),
    );
  }

  /** [path] is relative within the bucket, e.g. "{profile_id}/selfie.jpg". Overwrites on re-upload. */
  async uploadFile(
    bucket: string,
    path: string,
    buffer: Buffer,
    contentType?: string,
  ): Promise<void> {
    const { error } = await this.client.storage.from(bucket).upload(path, buffer, {
      upsert: true,
      contentType,
    });
    if (error) {
      this.logger.error(`Upload failed for ${bucket}/${path}: ${error.message}`);
      throw new AppException('UPLOAD_005');
    }
  }

  async getSignedUrl(
    bucket: string,
    path: string,
    expiresInSeconds: number = Config.SIGNED_URL_EXPIRY_SECONDS,
  ): Promise<string> {
    const { data, error } = await this.client.storage
      .from(bucket)
      .createSignedUrl(path, expiresInSeconds);
    if (error || !data) {
      this.logger.error(`Signed URL failed for ${bucket}/${path}: ${error?.message}`);
      throw new AppException('UPLOAD_005');
    }
    return data.signedUrl;
  }

  async getSignedUrlOrNull(bucket: string, path: string | null): Promise<string | null> {
    if (!path) return null;
    return this.getSignedUrl(bucket, path);
  }

  /** Returns the extension without the leading dot, or '' if the filename has none. */
  extractExtension(originalFilename: string): string {
    const lastDot = originalFilename.lastIndexOf('.');
    if (lastDot === -1 || lastDot === originalFilename.length - 1) return '';
    return originalFilename.slice(lastDot + 1);
  }
}
