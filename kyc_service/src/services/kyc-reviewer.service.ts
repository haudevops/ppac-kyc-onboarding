import {
  type KycApplicationWithRelations,
  type ResubmissionItem,
  type ReviewDecisionStatus,
  requiredDocumentsFor,
} from '../models/kyc.model';

export type ReviewMode = 'rule' | 'approve' | 'reject' | 'resubmit' | 'random';

export interface ReviewDecision {
  decision: ReviewDecisionStatus;
  reason: string;
  /** Only for RESUBMISSION_REQUESTED. */
  items?: ResubmissionItem[];
}

/**
 * Simulated KYC vendor (stands in for Onfido / Sumsub / an internal ops review).
 *
 * KYC_AUTO_REVIEW_MODE:
 *  - rule (default) deterministic rules so every outcome is easy to demo:
 *      * full name contains "reject"                       -> REJECTED (final)
 *      * full name contains "retake", first submission     -> RESUBMISSION_REQUESTED (selfie)
 *        (the resubmission is then approved)
 *      * ID expired / required photo missing               -> RESUBMISSION_REQUESTED (those items)
 *      * otherwise                                          -> APPROVED
 *  - approve / reject / resubmit : always that outcome
 *  - random                      : one of the three
 */
export class KycAutoReviewer {
  constructor(
    private readonly mode: ReviewMode,
    private readonly random: () => number = Math.random,
  ) {}

  decide(app: KycApplicationWithRelations): ReviewDecision {
    switch (this.mode) {
      case 'approve':
        return approve();
      case 'reject':
        return reject();
      case 'resubmit':
        return resubmitSelfie();
      case 'random': {
        const roll = this.random();
        return roll < 0.5 ? approve() : roll < 0.75 ? resubmitSelfie() : reject();
      }
      case 'rule':
        return this.applyRules(app);
    }
  }

  private applyRules(app: KycApplicationWithRelations): ReviewDecision {
    const name = app.fullName?.toLowerCase() ?? '';
    if (name.includes('reject')) return reject();

    const submissions = app.history.filter((h) => h.toStatus === 'SUBMITTED').length;
    if (name.includes('retake') && submissions <= 1) return resubmitSelfie();

    const today = new Date().toISOString().slice(0, 10);
    if (!app.idExpiryDate || app.idExpiryDate <= today) {
      const sides: ResubmissionItem[] = app.idType === 'PASSPORT' ? ['ID_FRONT'] : ['ID_FRONT', 'ID_BACK'];
      return {
        decision: 'RESUBMISSION_REQUESTED',
        reason: 'Your ID document has expired. Please update your details and photograph a valid document.',
        items: ['PERSONAL_DETAILS', ...sides],
      };
    }

    const uploaded = new Set(app.documents.map((d) => d.type));
    const missing = requiredDocumentsFor(app.idType).filter((t) => !uploaded.has(t));
    if (missing.length > 0) {
      return {
        decision: 'RESUBMISSION_REQUESTED',
        reason: `Some photos are missing: ${missing.join(', ')}.`,
        items: missing,
      };
    }

    return approve();
  }
}

/** Columns written when a decision is applied (shared by the worker and the dev endpoint). */
export function decisionUpdate(decision: ReviewDecision, now: Date = new Date()) {
  return {
    reviewedAt: now,
    rejectionReason: decision.decision === 'APPROVED' ? null : decision.reason,
    resubmissionItems:
      decision.decision === 'RESUBMISSION_REQUESTED' ? JSON.stringify(decision.items ?? []) : null,
  };
}

const approve = (): ReviewDecision => ({ decision: 'APPROVED', reason: 'All automated checks passed' });

const reject = (): ReviewDecision => ({
  decision: 'REJECTED',
  reason: 'We could not verify your identity. Please contact support if you believe this is a mistake.',
});

const resubmitSelfie = (): ReviewDecision => ({
  decision: 'RESUBMISSION_REQUESTED',
  reason: 'Your selfie is blurry or your face is not fully visible. Please take a new selfie.',
  items: ['SELFIE'],
});
