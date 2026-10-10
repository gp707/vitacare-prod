-- Patient's own name — a brand-new field on care_receivers (which previously
-- had no name at all, just age/gender/weight/feeding/etc.). Mandatory going
-- forward on every form that creates/edits a care receiver (nursenow-app's
-- Individual registration/edit card, admin-web's _JobFormDialog), enforced
-- at the DTO layer (CareReceiverDto.patient_name, Validation.NAME_REGEX +
-- NAME_MAX_LENGTH, same convention as every other "name" field in this
-- product). Nullable at the DB level only because existing rows predate
-- this column and there's no backfill data to give them.
ALTER TABLE care_receivers ADD COLUMN patient_name VARCHAR(24);
