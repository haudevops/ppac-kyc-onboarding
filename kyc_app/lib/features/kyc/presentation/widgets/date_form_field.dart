import 'package:flutter/material.dart';

import '../../../../core/utils/date_utils.dart';

/// Read-only form field that opens a date picker.
class DateFormField extends FormField<DateTime> {
  DateFormField({
    super.key,
    required String label,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime?> onChanged,
    super.initialValue,
    super.validator,
    super.forceErrorText,
    String? helperText,
    DateTime? pickerInitialDate,
    bool enabled = true,
  }) : super(
          enabled: enabled,
          builder: (field) {
            Future<void> pick() async {
              final initial = field.value ?? pickerInitialDate ?? lastDate;
              final picked = await showDatePicker(
                context: field.context,
                initialDate: initial.isBefore(firstDate)
                    ? firstDate
                    : initial.isAfter(lastDate)
                        ? lastDate
                        : initial,
                firstDate: firstDate,
                lastDate: lastDate,
                initialEntryMode: DatePickerEntryMode.calendar,
                helpText: label,
              );
              if (picked != null) {
                field.didChange(picked);
                onChanged(picked);
              }
            }

            final value = field.value;
            return InkWell(
              onTap: enabled ? pick : null,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                isEmpty: value == null,
                decoration: InputDecoration(
                  labelText: label,
                  helperText: helperText,
                  errorText: field.errorText,
                  enabled: enabled,
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                ),
                child: Text(value == null ? '' : formatDisplayDate(value)),
              ),
            );
          },
        );
}
