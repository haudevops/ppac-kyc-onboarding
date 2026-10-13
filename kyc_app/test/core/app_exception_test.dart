import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyc_app/core/error/app_exception.dart';

void main() {
  DioException badResponse(int status, Object body) {
    final options = RequestOptions(path: '/kyc/submit');
    return DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(requestOptions: options, statusCode: status, data: body),
    );
  }

  test('maps the backend error envelope', () {
    final e = AppException.fromDio(
      badResponse(400, {
        'success': false,
        'error': {
          'code': 'VALIDATION_ERROR',
          'message': 'Request validation failed',
          'details': [
            {'field': 'body.dateOfBirth', 'message': 'You must be at least 18 years old'},
          ],
        },
        'requestId': 'req-1',
      }),
    );
    expect(e.type, AppErrorType.validation);
    expect(e.code, 'VALIDATION_ERROR');
    expect(e.requestId, 'req-1');
    expect(e.fieldErrors, {'dateOfBirth': 'You must be at least 18 years old'});
  });

  test('reads KYC_INCOMPLETE details', () {
    final e = AppException.fromDio(
      badResponse(422, {
        'error': {
          'code': 'KYC_INCOMPLETE',
          'message': 'incomplete',
          'details': {
            'missingDocuments': ['SELFIE'],
            'fieldIssues': [
              {'field': 'idExpiryDate', 'message': 'The ID document has expired'},
            ],
          },
        },
      }),
    );
    expect(e.missingDocuments, ['SELFIE']);
    expect(e.fieldErrors.keys, ['idExpiryDate']);
  });

  test('connection errors are connectivity problems', () {
    final e = AppException.fromDio(
      DioException(requestOptions: RequestOptions(path: '/kyc'), type: DioExceptionType.connectionError),
    );
    expect(e.isConnectivity, isTrue);
  });
}
