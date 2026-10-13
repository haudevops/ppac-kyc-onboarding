import 'package:kyc_app/features/kyc/domain/entities/kyc_draft.dart';
import 'package:kyc_app/features/kyc/domain/entities/kyc_enums.dart';
import 'package:kyc_app/features/kyc/domain/entities/personal_details.dart';

final DateTime kNow = DateTime(2026, 1, 15);

PersonalDetails completeDetails() => PersonalDetails(
      fullName: 'Alice Nguyen',
      dateOfBirth: DateTime(1990, 5, 20),
      nationality: 'VN',
      addressLine1: '12 Nguyen Hue',
      city: 'Ho Chi Minh City',
      country: 'VN',
      idType: IdType.nationalId,
      idNumber: '079090001234',
      idIssueDate: DateTime(2021, 1, 15),
      idExpiryDate: DateTime(2031, 1, 15),
    );

KycDraft completeDraft({KycStep step = KycStep.review}) => KycDraft(
      details: completeDetails(),
      step: step,
      lastKnownStatus: KycStatus.draft,
      documents: {
        for (final type in DocumentType.values)
          type: KycDocument(type: type, localPath: '/data/kyc_drafts/user-1/${type.pathSegment}.jpg'),
      },
    );
