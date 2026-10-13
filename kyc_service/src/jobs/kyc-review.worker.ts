import type { Logger } from '../config/logger';
import type { KycRepository } from '../repositories/kyc.repository';
import { type KycAutoReviewer, decisionUpdate } from '../services/kyc-reviewer.service';

export interface KycReviewWorkerConfig {
  /** Time between submission and the automated decision (requirement: 10s). */
  decisionDelayMs: number;
  pollIntervalMs: number;
  batchSize: number;
}

/**
 * Simulated asynchronous review pipeline (stands in for a queue consumer / vendor webhook).
 *
 *   SUBMITTED  --(picked up on next tick)-->  PROCESSING
 *   PROCESSING --(submittedAt + delay)----->  APPROVED | REJECTED | RESUBMISSION_REQUESTED
 *
 * It polls the database instead of using in-memory timers, so:
 *  - pending reviews survive a server restart;
 *  - it is safe to run several API instances: every transition is a conditional update,
 *    so only one worker can move a given application.
 * In production this would be a queue (BullMQ / SQS) or a KYC vendor webhook.
 */
export class KycReviewWorker {
  private timer: NodeJS.Timeout | null = null;
  private running: Promise<void> | null = null;

  constructor(
    private readonly repo: KycRepository,
    private readonly reviewer: KycAutoReviewer,
    private readonly logger: Logger,
    private readonly config: KycReviewWorkerConfig,
  ) {}

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => void this.tick(), this.config.pollIntervalMs);
    this.logger.info('KYC review worker started', {
      decisionDelayMs: this.config.decisionDelayMs,
      pollIntervalMs: this.config.pollIntervalMs,
    });
  }

  async stop(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    await this.running; // let an in-flight tick finish
  }

  /** One polling cycle. Overlapping ticks are skipped. Public for tests. */
  tick(): Promise<void> {
    if (this.running) return this.running;
    this.running = this.runCycle().finally(() => {
      this.running = null;
    });
    return this.running;
  }

  private async runCycle(): Promise<void> {
    try {
      await this.pickUpSubmitted();
      await this.decideDue();
    } catch (err) {
      this.logger.error('KYC review worker cycle failed', { err });
    }
  }

  private async pickUpSubmitted(): Promise<void> {
    const ids = await this.repo.findIdsByStatus('SUBMITTED', this.config.batchSize);
    for (const id of ids) {
      const moved = await this.repo.transition({
        id,
        from: ['SUBMITTED'],
        to: 'PROCESSING',
        actor: 'SYSTEM',
        reason: 'Automated verification started',
        data: { processingStartedAt: new Date() },
      });
      if (moved) this.logger.info('KYC application processing', { applicationId: id });
    }
  }

  private async decideDue(): Promise<void> {
    const cutoff = new Date(Date.now() - this.config.decisionDelayMs);
    const due = await this.repo.findDueForDecision(cutoff, this.config.batchSize);

    for (const app of due) {
      const result = this.reviewer.decide(app);
      const { decision, reason } = result;
      const decided = await this.repo.transition({
        id: app.id,
        from: ['PROCESSING'],
        to: decision,
        actor: 'SYSTEM',
        reason,
        data: decisionUpdate(result),
      });
      if (decided) this.logger.info('KYC application reviewed', { applicationId: app.id, decision });
    }
  }
}
