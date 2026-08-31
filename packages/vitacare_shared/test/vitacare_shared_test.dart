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
      String feedingType = FeedingType.oralIndependent,
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

    test('diaper assistance derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(toiletAssistance: const [ToiletAssistance.usesDiapers])),
        CareTier.bedsideCare,
      );
    });

    test('bed pan assistance derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(toiletAssistance: const [ToiletAssistance.usesBedPan])),
        CareTier.bedsideCare,
      );
    });

    test('feeding assistance derives to bedsideCare', () {
      expect(
        deriveCareTier(careReceiver(feedingType: FeedingType.oralNeedsAssistance)),
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

    test('oral and tube feeding derives to criticalCare', () {
      expect(deriveCareTier(careReceiver(feedingType: FeedingType.oralAndTube)), CareTier.criticalCare);
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
          toiletAssistance: const [ToiletAssistance.usesDiapers, ToiletAssistance.usesCatheter],
          feedingType: FeedingType.oralNeedsAssistance,
          requiresVitalMonitoring: true,
        )),
        CareTier.criticalCare,
      );
    });
  });
}
