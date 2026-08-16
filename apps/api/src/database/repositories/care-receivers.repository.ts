import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import { Communication, FeedingType, MedicalAssistance, MedicalCondition, Mobility } from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface CareReceiverRecord {
  id: string;
  mobility: Mobility;
  communication: Communication;
  feeding_type: FeedingType;
  tube_feeding_needs_assistance: boolean | null;
  medical_assistance: MedicalAssistance[];
  has_medical_condition: boolean;
  medical_conditions: MedicalCondition[];
  medical_info: string | null;
  created_at: Date;
  updated_at: Date;
}

export interface CreateCareReceiverInput {
  mobility: Mobility;
  communication: Communication;
  feeding_type: FeedingType;
  tube_feeding_needs_assistance?: boolean | null;
  medical_assistance: MedicalAssistance[];
  has_medical_condition: boolean;
  medical_conditions?: MedicalCondition[];
  medical_info?: string | null;
}

@Injectable()
export class CareReceiversRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(input: CreateCareReceiverInput, client?: PoolClient): Promise<CareReceiverRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<CareReceiverRecord>(
      `INSERT INTO care_receivers
         (mobility, communication, feeding_type, tube_feeding_needs_assistance,
          medical_assistance, has_medical_condition, medical_conditions, medical_info)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING *`,
      [
        input.mobility,
        input.communication,
        input.feeding_type,
        input.tube_feeding_needs_assistance ?? null,
        JSON.stringify(input.medical_assistance),
        input.has_medical_condition,
        JSON.stringify(input.medical_conditions ?? []),
        input.medical_info ?? null,
      ],
    );
    return result.rows[0];
  }

  async findById(id: string): Promise<CareReceiverRecord | null> {
    const result = await this.db.query<CareReceiverRecord>(
      'SELECT * FROM care_receivers WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }
}
