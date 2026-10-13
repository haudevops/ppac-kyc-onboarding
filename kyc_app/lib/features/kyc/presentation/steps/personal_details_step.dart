import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/presentation/widgets.dart';
import '../../domain/entities/kyc_enums.dart';
import '../../domain/entities/personal_details.dart';
import '../../domain/validation/personal_details_validator.dart';
import '../bloc/kyc_bloc.dart';
import '../widgets/date_form_field.dart';

/// Step 1 - personal details. Every change is autosaved (debounced) through the bloc,
/// so killing the app mid-typing loses nothing.
class PersonalDetailsStep extends StatefulWidget {
  const PersonalDetailsStep({super.key});

  @override
  State<PersonalDetailsStep> createState() => _PersonalDetailsStepState();
}

class _PersonalDetailsStepState extends State<PersonalDetailsStep> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _idNumber;
  late final TextEditingController _address1;
  late final TextEditingController _address2;
  late final TextEditingController _city;
  late final TextEditingController _stateProvince;
  late final TextEditingController _postalCode;

  DateTime? _dateOfBirth;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  Gender? _gender;
  String? _nationality;
  String? _country;
  String _phoneCountry = kDefaultPhoneCountry;
  IdType? _idType;

  AutovalidateMode _autovalidate = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();
    final d = context.read<KycBloc>().state.draft.details;
    _fullName = TextEditingController(text: d.fullName);
    final phone = splitPhoneNumber(d.phoneNumber, preferred: d.country ?? kDefaultPhoneCountry);
    _phoneCountry = phone.countryCode;
    _phone = TextEditingController(text: phone.nationalNumber);
    _idNumber = TextEditingController(text: d.idNumber);
    _address1 = TextEditingController(text: d.addressLine1);
    _address2 = TextEditingController(text: d.addressLine2);
    _city = TextEditingController(text: d.city);
    _stateProvince = TextEditingController(text: d.stateProvince);
    _postalCode = TextEditingController(text: d.postalCode);
    _dateOfBirth = d.dateOfBirth;
    _issueDate = d.idIssueDate;
    _expiryDate = d.idExpiryDate;
    _gender = d.gender;
    _nationality = d.nationality ?? 'VN';
    _country = d.country ?? 'VN';
    _idType = d.idType ?? IdType.nationalId;
  }

  @override
  void dispose() {
    for (final c in [_fullName, _phone, _idNumber, _address1, _address2, _city, _stateProvince, _postalCode]) {
      c.dispose();
    }
    super.dispose();
  }

  PersonalDetails _current() {
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return PersonalDetails(
      fullName: text(_fullName),
      dateOfBirth: _dateOfBirth,
      gender: _gender,
      nationality: _nationality,
      phoneNumber: composePhoneNumber(_phoneCountry, _phone.text),
      addressLine1: text(_address1),
      addressLine2: text(_address2),
      city: text(_city),
      stateProvince: text(_stateProvince),
      postalCode: text(_postalCode),
      country: _country,
      idType: _idType,
      idNumber: text(_idNumber),
      idIssueDate: _issueDate,
      idExpiryDate: _expiryDate,
    );
  }

  void _changed() => context.read<KycBloc>().add(KycPersonalDetailsChanged(_current()));

  void _continue() {
    FocusScope.of(context).unfocus();
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    _formKey.currentState?.validate(); // show local errors immediately
    // The bloc runs the same validation and owns the decision to move on.
    context.read<KycBloc>().add(KycPersonalDetailsSubmitted(_current()));
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return BlocBuilder<KycBloc, KycState>(
      buildWhen: (p, c) =>
          p.fieldErrors != c.fieldErrors || p.canEdit != c.canEdit || p.showRejectionBanner != c.showRejectionBanner,
      builder: (context, state) {
        final errors = state.fieldErrors;
        return Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (state.showRejectionBanner) ...[
                InfoBanner(
                  message: 'Reviewer feedback: ${state.rejectionReason}',
                  icon: Icons.assignment_late_outlined,
                  isError: state.requestedOn(KycStep.personalDetails).isNotEmpty,
                ),
                const SizedBox(height: 16),
              ],
              const _SectionTitle('Personal information', 'Enter your details exactly as shown on your ID.'),
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Full name'),
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                textInputAction: TextInputAction.next,
                onChanged: (_) => _changed(),
                validator: PersonalDetailsValidator.fullName,
                forceErrorText: errors['fullName'],
              ),
              const _Gap(),
              DateFormField(
                label: 'Date of birth',
                initialValue: _dateOfBirth,
                firstDate: DateTime(1900),
                lastDate: DateTime(today.year - PersonalDetailsValidator.minimumAge, today.month, today.day),
                pickerInitialDate: DateTime(today.year - 30),
                validator: (v) => PersonalDetailsValidator.dateOfBirth(v),
                forceErrorText: errors['dateOfBirth'],
                onChanged: (v) {
                  _dateOfBirth = v;
                  _changed();
                },
              ),
              const _Gap(),
              DropdownButtonFormField<Gender?>(
                initialValue: _gender,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gender (optional)'),
                items: [
                  const DropdownMenuItem<Gender?>(value: null, child: Text('Prefer not to say')),
                  for (final g in Gender.values) DropdownMenuItem<Gender?>(value: g, child: Text(g.label)),
                ],
                onChanged: (v) {
                  setState(() => _gender = v);
                  _changed();
                },
              ),
              const _Gap(),
              _CountryField(
                label: 'Nationality',
                value: _nationality,
                onChanged: (v) {
                  setState(() => _nationality = v);
                  _changed();
                },
              ),
              const _Gap(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 124,
                    child: _PhoneCountryField(
                      value: _phoneCountry,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _phoneCountry = v);
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(labelText: 'Phone number (optional)', hintText: '901 234 567'),
                      keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                      onChanged: (_) => _changed(),
                      validator: (v) => PersonalDetailsValidator.phone(composePhoneNumber(_phoneCountry, v ?? '')),
                      forceErrorText: errors['phoneNumber'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Identity document', 'The document you will photograph in the next step.'),
              DropdownButtonFormField<IdType>(
                initialValue: _idType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Document type'),
                items: [for (final t in IdType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                validator: PersonalDetailsValidator.idType,
                onChanged: (v) {
                  setState(() => _idType = v);
                  _changed();
                },
              ),
              const _Gap(),
              TextFormField(
                controller: _idNumber,
                decoration: InputDecoration(
                  labelText: _idType == IdType.passport ? 'Passport number' : 'ID number',
                  counterText: '',
                ),
                maxLength: 30,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), _UpperCaseFormatter()],
                onChanged: (_) => _changed(),
                validator: (v) => PersonalDetailsValidator.idNumber(v, idType: _idType, nationality: _nationality),
                forceErrorText: errors['idNumber'],
              ),
              const _Gap(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DateFormField(
                      label: 'Issue date',
                      helperText: 'Optional',
                      initialValue: _issueDate,
                      firstDate: DateTime(1950),
                      lastDate: today,
                      validator: (v) => PersonalDetailsValidator.idIssueDate(v, dateOfBirth: _dateOfBirth),
                      forceErrorText: errors['idIssueDate'],
                      onChanged: (v) {
                        _issueDate = v;
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DateFormField(
                      label: 'Expiry date',
                      initialValue: _expiryDate,
                      firstDate: today.add(const Duration(days: 1)),
                      lastDate: DateTime(today.year + 30),
                      validator: (v) => PersonalDetailsValidator.idExpiryDate(v, issueDate: _issueDate),
                      forceErrorText: errors['idExpiryDate'],
                      onChanged: (v) {
                        _expiryDate = v;
                        _changed();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const _SectionTitle('Residential address', null),
              TextFormField(
                controller: _address1,
                decoration: const InputDecoration(labelText: 'Address'),
                autofillHints: const [AutofillHints.streetAddressLine1],
                textInputAction: TextInputAction.next,
                onChanged: (_) => _changed(),
                validator: (v) => PersonalDetailsValidator.requiredText(v, 'Address', min: 3),
                forceErrorText: errors['addressLine1'],
              ),
              const _Gap(),
              TextFormField(
                controller: _address2,
                decoration: const InputDecoration(labelText: 'Apartment, suite, etc. (optional)'),
                autofillHints: const [AutofillHints.streetAddressLine2],
                textInputAction: TextInputAction.next,
                onChanged: (_) => _changed(),
                forceErrorText: errors['addressLine2'],
              ),
              const _Gap(),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City'),
                autofillHints: const [AutofillHints.addressCity],
                textInputAction: TextInputAction.next,
                onChanged: (_) => _changed(),
                validator: (v) => PersonalDetailsValidator.requiredText(v, 'City', max: 100),
                forceErrorText: errors['city'],
              ),
              const _Gap(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stateProvince,
                      decoration: const InputDecoration(labelText: 'State / province'),
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _changed(),
                      forceErrorText: errors['stateProvince'],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _postalCode,
                      decoration: const InputDecoration(labelText: 'Postal code'),
                      keyboardType: TextInputType.text,
                      autofillHints: const [AutofillHints.postalCode],
                      onChanged: (_) => _changed(),
                      forceErrorText: errors['postalCode'],
                    ),
                  ),
                ],
              ),
              const _Gap(),
              _CountryField(
                label: 'Country of residence',
                value: _country,
                onChanged: (v) {
                  setState(() => _country = v);
                  _changed();
                },
              ),
              const SizedBox(height: 32),
              PrimaryButton(label: 'Continue', icon: Icons.arrow_forward, onPressed: state.canEdit ? _continue : null),
            ],
          ),
        );
      },
    );
  }
}

class _CountryField extends StatelessWidget {
  const _CountryField({required this.label, required this.value, required this.onChanged});

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: kCountries.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final e in kCountries.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      validator: (v) => PersonalDetailsValidator.country(v, label.toLowerCase()),
      onChanged: onChanged,
    );
  }
}

/// Country dialling-code picker for the phone field: shows `🇻🇳 +84`; the menu lists `🇻🇳 VN +84`
/// (short enough for the field's width, and it tells +1 countries apart).
class _PhoneCountryField extends StatelessWidget {
  const _PhoneCountryField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = kCountries.entries.where((e) => kDialCodes.containsKey(e.key)).toList();
    return DropdownButtonFormField<String>(
      initialValue: kDialCodes.containsKey(value) ? value : kDefaultPhoneCountry,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Code'),
      selectedItemBuilder: (_) => [
        for (final e in entries) Text('${countryFlag(e.key)} +${kDialCodes[e.key]}', overflow: TextOverflow.ellipsis),
      ],
      items: [
        for (final e in entries)
          DropdownMenuItem(value: e.key, child: Text('${countryFlag(e.key)} ${e.key} +${kDialCodes[e.key]}')),
      ],
      onChanged: onChanged,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.subtitle);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: 16);
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
