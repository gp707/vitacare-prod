import { Injectable } from '@nestjs/common';
import { PoolClient } from 'pg';
import {
  Communication,
  FeedingType,
  Gender,
  MedicalAssistance,
  MedicalCondition,
  Mobility,
  ToiletAssistance,
  VitalMonitoringType,
} from '@vitacare/shared-constants';
import { DatabaseService, QueryRunner } from '../database.service';

export interface CareReceiverRecord {
  id: string;
  age: number;
  gender: Gender;
  weight_kg: number;
  mobility: Mobility;
  communication: Communication;
  feeding_type: FeedingType;
  medical_assistance: MedicalAssistance[];
  has_medical_condition: boolean;
  medical_conditions: MedicalCondition[];
  medical_info: string | null;
  medical_condition_other: string | null;
  toilet_assistance: ToiletAssistance[];
  toilet_assistance_other: string | null;
  requires_vital_monitoring: boolean;
  vital_monitoring_types: VitalMonitoringType[];
  created_at: Date;
  updated_at: Date;
}

export interface CreateCareReceiverInput {
  age: number;
  gender: Gender;
  weight_kg: number;
  mobility: Mobility;
  communication: Communication;
  feeding_type: FeedingType;
  medical_assistance: MedicalAssistance[];
  has_medical_condition: boolean;
  medical_conditions?: MedicalCondition[];
  medical_info?: string | null;
  medical_condition_other?: string | null;
  toilet_assistance: ToiletAssistance[];
  toilet_assistance_other?: string | null;
  requires_vital_monitoring: boolean;
  vital_monitoring_types?: VitalMonitoringType[];
}

@Injectable()
export class CareReceiversRepository {
  constructor(private readonly db: DatabaseService) {}

  async create(input: CreateCareReceiverInput, client?: PoolClient): Promise<CareReceiverRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<CareReceiverRecord>(
      `INSERT INTO care_receivers
         (age, gender, weight_kg, mobility, communication, feeding_type,
          medical_assistance, has_medical_condition, medical_conditions, medical_info,
          medical_condition_other, toilet_assistance, toilet_assistance_other,
          requires_vital_monitoring, vital_monitoring_types)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
       RETURNING *`,
      [
        input.age,
        input.gender,
        input.weight_kg,
        input.mobility,
        input.communication,
        input.feeding_type,
        JSON.stringify(input.medical_assistance),
        input.has_medical_condition,
        JSON.stringify(input.medical_conditions ?? []),
        input.medical_info ?? null,
        input.medical_condition_other ?? null,
        JSON.stringify(input.toilet_assistance),
        input.toilet_assistance_other ?? null,
        input.requires_vital_monitoring,
        JSON.stringify(input.vital_monitoring_types ?? []),
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

  async update(
    id: string,
    input: CreateCareReceiverInput,
    client?: PoolClient,
  ): Promise<CareReceiverRecord> {
    const runner: QueryRunner = client ?? this.db;
    const result = await runner.query<CareReceiverRecord>(
      `UPDATE care_receivers SET
         age = $1, gender = $2, weight_kg = $3, mobility = $4, communication = $5,
         feeding_type = $6, medical_assistance = $7,
         has_medical_condition = $8, medical_conditions = $9, medical_info = $10,
         medical_condition_other = $11, toilet_assistance = $12, toilet_assistance_other = $13,
         requires_vital_monitoring = $14, vital_monitoring_types = $15,
         updated_at = NOW()
       WHERE id = $16
       RETURNING *`,
      [
        input.age,
        input.gender,
        input.weight_kg,
        input.mobility,
        input.communication,
        input.feeding_type,
        JSON.stringify(input.medical_assistance),
        input.has_medical_condition,
        JSON.stringify(input.medical_conditions ?? []),
        input.medical_info ?? null,
        input.medical_condition_other ?? null,
        JSON.stringify(input.toilet_assistance),
        input.toilet_assistance_other ?? null,
        input.requires_vital_monitoring,
        JSON.stringify(input.vital_monitoring_types ?? []),
        id,
      ],
    );
    return result.rows[0];
  }
}
