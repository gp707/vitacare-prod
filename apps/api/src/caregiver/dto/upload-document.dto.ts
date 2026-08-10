import { IsIn } from 'class-validator';
import { DocumentType } from '@vitacare/shared-constants';

export class UploadDocumentDto {
  @IsIn(Object.values(DocumentType), { message: 'UPLOAD_004' })
  document_type!: DocumentType;
}
