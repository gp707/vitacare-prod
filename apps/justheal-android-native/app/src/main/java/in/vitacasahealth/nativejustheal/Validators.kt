package `in`.vitacasahealth.nativejustheal

object Validators {
    fun isValidPhone(local10Digit: String) = Validation.PHONE_REGEX.matches(local10Digit)
    fun isValidCode(code: String) = Validation.CODE_REGEX.matches(code)
    fun isValidName(name: String) = name.trim().isNotEmpty() && Validation.NAME_REGEX.matches(name.trim())
    fun isValidAge(age: Int?) = age != null && age in Validation.AGE_MIN..Validation.AGE_MAX
}
