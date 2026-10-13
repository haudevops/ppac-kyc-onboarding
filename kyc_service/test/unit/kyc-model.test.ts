import '../helpers/test-env';

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  KYC_STATUSES,
  allowedActionsFor,
  assertTransition,
  canTransition,
  maskIdentifier,
  parseResubmissionItems,
  requiredDocumentsFor,
} from '../../src/models/kyc.model';
import { AppError } from '../../src/utils/errors';
import { detectImageType } from '../../src/utils/image';
import { JPEG, PDF, PNG } from '../helpers/fixtures';

describe('KYC state machine', () => {
  it('allows only the documented transitions', () => {
    const allowed = new Set([
      'DRAFT>SUBMITTED',
      'SUBMITTED>PROCESSING',
      'PROCESSING>APPROVED',
      'PROCESSING>REJECTED',
      'PROCESSING>RESUBMISSION_REQUESTED',
      'RESUBMISSION_REQUESTED>DRAFT',
    ]);
    for (const from of KYC_STATUSES) {
      for (const to of KYC_STATUSES) {
        assert.equal(canTransition(from, to), allowed.has(`${from}>${to}`), `${from} -> ${to}`);
      }
    }
  });

  it('APPROVED and REJECTED are final', () => {
    for (const to of KYC_STATUSES) {
      assert.equal(canTransition('APPROVED', to), false);
      assert.equal(canTransition('REJECTED', to), false);
    }
    assert.deepEqual(allowedActionsFor('REJECTED'), []);
    assert.deepEqual(allowedActionsFor('APPROVED'), []);
  });

  it('assertTransition throws a 409 KYC_INVALID_TRANSITION', () => {
    assert.throws(
      () => assertTransition('DRAFT', 'APPROVED'),
      (e: unknown) => e instanceof AppError && e.statusCode === 409 && e.code === 'KYC_INVALID_TRANSITION',
    );
  });

  it('a resubmission request can be acted on by the user', () => {
    assert.ok(allowedActionsFor('RESUBMISSION_REQUESTED').includes('RESUBMIT'));
    assert.deepEqual(allowedActionsFor('PROCESSING'), ['WAIT_FOR_REVIEW']);
  });
});

describe('domain helpers', () => {
  it('passports do not need a back side', () => {
    assert.deepEqual(requiredDocumentsFor('PASSPORT'), ['ID_FRONT', 'SELFIE']);
    assert.deepEqual(requiredDocumentsFor('NATIONAL_ID'), ['ID_FRONT', 'ID_BACK', 'SELFIE']);
    assert.deepEqual(requiredDocumentsFor(null), ['ID_FRONT', 'ID_BACK', 'SELFIE']);
  });

  it('masks identifiers except the last 4 characters', () => {
    assert.equal(maskIdentifier('079090001234'), '********1234');
    assert.equal(maskIdentifier('123'), '***');
    assert.equal(maskIdentifier(null), null);
  });

  it('parses stored resubmission items defensively', () => {
    assert.deepEqual(parseResubmissionItems('["SELFIE","ID_FRONT"]'), ['SELFIE', 'ID_FRONT']);
    assert.deepEqual(parseResubmissionItems('["SELFIE","DROP TABLE"]'), ['SELFIE']);
    assert.deepEqual(parseResubmissionItems('not json'), []);
    assert.deepEqual(parseResubmissionItems(null), []);
  });

  it('detects image types from magic bytes, not from the declared type', () => {
    assert.equal(detectImageType(PNG), 'image/png');
    assert.equal(detectImageType(JPEG), 'image/jpeg');
    assert.equal(detectImageType(Buffer.from('RIFF\0\0\0\0WEBPVP8 ')), 'image/webp');
    assert.equal(detectImageType(PDF), null);
    assert.equal(detectImageType(Buffer.alloc(0)), null);
  });
});
