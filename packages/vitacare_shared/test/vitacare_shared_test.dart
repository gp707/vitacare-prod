import 'package:test/test.dart';
import 'package:vitacare_shared/vitacare_shared.dart';

void main() {
  group('Validators', () {
    test('accepts a valid +91 mobile number', () {
      expect(Validators.isValidPhone('+919876543210'), isTrue);
    });

    test('rejects a number missing the +91 prefix', () {
      expect(Validators.isValidPhone('9876543210'), isFalse);
    });

    test('rejects a landline-style number starting with 5', () {
      expect(Validators.isValidPhone('+915876543210'), isFalse);
    });

    test('accepts a valid 4-digit code', () {
      expect(Validators.isValidCode('1234'), isTrue);
    });

    test('rejects a non-numeric code', () {
      expect(Validators.isValidCode('12a4'), isFalse);
    });

    test('age boundaries are inclusive', () {
      expect(Validators.isValidAge(18), isTrue);
      expect(Validators.isValidAge(65), isTrue);
      expect(Validators.isValidAge(17), isFalse);
      expect(Validators.isValidAge(66), isFalse);
    });
  });

  group('Enums', () {
    test('VerificationStatus.all has all 5 statuses from SPEC.md', () {
      expect(VerificationStatus.all, hasLength(5));
      expect(VerificationStatus.all, contains('pending_call'));
      expect(VerificationStatus.all, contains('available'));
    });

    test('Language has 9 values matching CLAUDE.md source of truth', () {
      expect(Language.all, hasLength(9));
    });
  });

  group('ErrorCodes', () {
    test('resolves a known code to its catalog message', () {
      expect(ErrorCodes.messageFor('AUTH_001'), 'Phone number is already registered');
    });

    test('falls back to server message for an unrecognized code', () {
      expect(
        ErrorCodes.messageFor('UNKNOWN_CODE', fallback: 'server said this'),
        'server said this',
      );
    });
  });

  group('ApiResponse', () {
    test('parses a success envelope', () {
      final res = ApiResponse.fromJson({
        'success': true,
        'data': {'user_id': 'abc'},
      });
      expect(res.success, isTrue);
      expect(res.data['user_id'], 'abc');
      expect(res.error, isNull);
    });

    test('parses an error envelope', () {
      final res = ApiResponse.fromJson({
        'success': false,
        'error': {'code': 'AUTH_002', 'message': 'No account found with this phone number'},
      });
      expect(res.success, isFalse);
      expect(res.error!.code, 'AUTH_002');
    });
  });

  group('CaregiverProfileModel', () {
    test('parses a profile with unset fields as null and empty arrays', () {
      final model = CaregiverProfileModel.fromJson({
        'user_id': 'u1',
        'profile_id': 'p1',
        'full_name': 'Ramesh Kumar',
        'phone': '+919876543210',
        'email': null,
        'gender': 'male',
        'age': 32,
        'selfie_photo_url': null,
        'languages': ['hindi', 'english'],
        'highest_qualification': null,
        'qualification_document_url': null,
        'aadhaar_document_url': null,
        'other_document_urls': [],
        'religion': null,
        'terms_accepted': false,
        'verification_status': 'pending_call',
        'rejection_message': null,
        'preferred_cities': [],
        'created_at': '2026-08-01T10:00:00Z',
      });

      expect(model.languages, ['hindi', 'english']);
      expect(model.preferredCities, isEmpty);
      expect(model.hasRequiredDocuments, isFalse);
    });

    test('hasRequiredDocuments is true once aadhaar is set, regardless of qualification/selfie', () {
      final base = {
        'user_id': 'u1',
        'profile_id': 'p1',
        'full_name': 'Ramesh Kumar',
        'phone': '+919876543210',
        'gender': 'male',
        'age': 32,
        'languages': ['hindi'],
        'other_document_urls': [],
        'terms_accepted': false,
        'verification_status': 'pending_call',
        'created_at': '2026-08-01T10:00:00Z',
        'selfie_photo_url': 'https://signed/selfie',
        'qualification_document_url': null,
        'aadhaar_document_url': 'https://signed/aadhaar',
      };
      expect(CaregiverProfileModel.fromJson(base).hasRequiredDocuments, isTrue);
      expect(
        CaregiverProfileModel.fromJson({...base, 'aadhaar_document_url': null}).hasRequiredDocuments,
        isFalse,
      );
    });
  });

  group('ScopeOfWorkModel', () {
    final scopeOfWork = ScopeOfWorkModel(
      companionCare: ['Emotional companionship', 'Walking & mobility support'],
      bedsideCare: ['Diaper changing & hygiene care', 'Feeding assistance'],
      criticalCare: ['Catheter care', 'Vitals monitoring'],
    );

    test('bulletsFor companionCare returns only the companion bullets', () {
      expect(scopeOfWork.bulletsFor(CareTier.companionCare), scopeOfWork.companionCare);
    });

    test('bulletsFor bedsideCare stacks companion + bedside', () {
      expect(
        scopeOfWork.bulletsFor(CareTier.bedsideCare),
        [...scopeOfWork.companionCare, ...scopeOfWork.bedsideCare],
      );
    });

    test('bulletsFor criticalCare stacks all 3 tiers', () {
      expect(
        scopeOfWork.bulletsFor(CareTier.criticalCare),
        [...scopeOfWork.companionCare, ...scopeOfWork.bedsideCare, ...scopeOfWork.criticalCare],
      );
    });
  });

  group('deriveCareTier', () {
    CareReceiverModel careReceiver({
      String feedingType = FeedingType.oralFeeding,
      bool hasMedicalCondition = false,
      List<String> medicalConditions = const [],
      List<String> toiletAssistance = const [ToiletAssistance.independent],
      bool requiresVitalMonitoring = false,
    }) =>
        CareReceiverModel(
          id: 'cr-1',
          age: 70,
          gender: 'male',
          weightKg: 60,
          communication: Communication.verbal,
          feedingType: feedingType,
          hasMedicalCondition: hasMedicalCondition,
          medicalConditions: medicalConditions,
          toiletAssistance: toiletAssistance,
          requiresVitalMonitoring: requiresVitalMonitoring,
          vitalMonitoringTypes: const [],
        );

    test('an independent patient with no medical needs derives to companionCare', () {
      expect(deriveCareTier(careReceiver()), CareTier.companionCare);
    });

    test('diapers/bedside support derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(toiletAssistance: const [ToiletAssistance.diapersBedsideSupport])),
        CareTier.bedsideCare,
      );
    });

    test('an unspecified other toileting need derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(toiletAssistance: const [ToiletAssistance.others])),
        CareTier.bedsideCare,
      );
    });

    test('any other medical condition derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(hasMedicalCondition: true, medicalConditions: const [MedicalCondition.diabetes])),
        CareTier.bedsideCare,
      );
    });

    test('catheter use derives to criticalCare', () {
      expect(
        deriveCareTier(careReceiver(toiletAssistance: const [ToiletAssistance.usesCatheter])),
        CareTier.criticalCare,
      );
    });

    test('tube feeding derives to criticalCare', () {
      expect(deriveCareTier(careReceiver(feedingType: FeedingType.tubeFeeding)), CareTier.criticalCare);
    });

    test('"Others (Cannula etc.)" feeding derives to criticalCare', () {
      expect(deriveCareTier(careReceiver(feedingType: FeedingType.others)), CareTier.criticalCare);
    });

    test('requiring vital monitoring derives to criticalCare', () {
      expect(deriveCareTier(careReceiver(requiresVitalMonitoring: true)), CareTier.criticalCare);
    });

    test('insulin administration support derives to criticalCare', () {
      expect(
        deriveCareTier(careReceiver(
          hasMedicalCondition: true,
          medicalConditions: const [MedicalCondition.insulinAdministrationSupport],
        )),
        CareTier.criticalCare,
      );
    });

    test('oxygen support derives to criticalCare', () {
      expect(
        deriveCareTier(
          careReceiver(hasMedicalCondition: true, medicalConditions: const [MedicalCondition.oxygenSupport]),
        ),
        CareTier.criticalCare,
      );
    });

    test('critical-tier needs win even when bedside-tier needs are also present', () {
      expect(
        deriveCareTier(careReceiver(
          toiletAssistance: const [ToiletAssistance.diapersBedsideSupport, ToiletAssistance.usesCatheter],
          requiresVitalMonitoring: true,
        )),
        CareTier.criticalCare,
      );
    });
  });

  group('frequencyForCareDuration', () {
    test('few days and few weeks map to daily', () {
      expect(frequencyForCareDuration(CareDuration.fewDays), FrequencyOfCare.daily);
      expect(frequencyForCareDuration(CareDuration.fewWeeks), FrequencyOfCare.daily);
    });

    test('few months and long term map to monthly', () {
      expect(frequencyForCareDuration(CareDuration.fewMonths), FrequencyOfCare.monthly);
      expect(frequencyForCareDuration(CareDuration.longTerm), FrequencyOfCare.monthly);
    });
  });

  group('suggestedRate', () {
    final rateCards = [
      RateCardModel(
        frequencyOfCare: FrequencyOfCare.daily,
        title: 'Daily',
        columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
        rowLabels: const ['Care'],
        cells: const [
          ['867 per day', '933 per day', '1067 per day'],
        ],
      ),
      RateCardModel(
        frequencyOfCare: FrequencyOfCare.monthly,
        title: 'Monthly',
        columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
        rowLabels: const ['Care'],
        cells: const [
          ['26000 pm', '28000 pm', '32000 pm'],
        ],
      ),
    ];

    test('picks the Companion column from the matching frequency', () {
      expect(suggestedRate(rateCards, CareTier.companionCare, FrequencyOfCare.daily), '867 per day');
      expect(suggestedRate(rateCards, CareTier.companionCare, FrequencyOfCare.monthly), '26000 pm');
    });

    test('picks the Bedside and Critical columns correctly', () {
      expect(suggestedRate(rateCards, CareTier.bedsideCare, FrequencyOfCare.daily), '933 per day');
      expect(suggestedRate(rateCards, CareTier.criticalCare, FrequencyOfCare.monthly), '32000 pm');
    });

    test('returns null when no rate card matches the requested frequency', () {
      expect(suggestedRate([rateCards[0]], CareTier.companionCare, FrequencyOfCare.monthly), isNull);
    });

    test('returns null for an unrecognized tier', () {
      expect(suggestedRate(rateCards, 'unknown_tier', FrequencyOfCare.daily), isNull);
    });

    test('returns null when the matching rate card has no rows', () {
      final empty = RateCardModel(
        frequencyOfCare: FrequencyOfCare.daily,
        title: 'Daily',
        columnLabels: const ['Companion care', 'Bedside Care', 'Critical Care'],
        rowLabels: const [],
        cells: const [],
      );
      expect(suggestedRate([empty], CareTier.companionCare, FrequencyOfCare.daily), isNull);
    });
  });
}
