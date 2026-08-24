import '../constants/validation.dart';

class Validators {
  static bool isValidPhone(String value) => Validation.phoneRegex.hasMatch(value);

  static bool isValidName(String value) =>
      value.isNotEmpty &&
      value.length <= Validation.nameMaxLength &&
      Validation.nameRegex.hasMatch(value);

  static bool isValidCode(String value) => Validation.codeRegex.hasMatch(value);

  static bool isValidOtp(String value) => Validation.otpRegex.hasMatch(value);

  static bool isValidAge(int age) => age >= Validation.ageMin && age <= Validation.ageMax;
}
