import { loadConfig } from '../config.js';
import { HandoffClaimService } from './handoff-claim-service.js';

export function createHandoffClaimService(options = {}) {
  const config = loadConfig(options.config);
  if (!config.smartCartHandoffTokenSecret) {
    throw new Error('SmartCart handoffs require HANDOFF_TOKEN_SECRET.');
  }
  if (config.env === 'production' && !config.smartCartHandoffBaseUrl) {
    throw new Error('Production SmartCart handoffs require SMARTCART_HANDOFF_BASE_URL.');
  }
  return new HandoffClaimService({
    secret: config.smartCartHandoffTokenSecret,
    validator: options.validator,
    baseUrl: config.smartCartHandoffBaseUrl ?? 'https://smartcart.app',
    ttlMs: config.smartCartHandoffTtlMs,
    maxPayloadBytes: config.smartCartHandoffMaxPayloadBytes,
    maxTokenCharacters: config.smartCartHandoffMaxTokenCharacters,
    now: options.now,
    randomBytesImpl: options.randomBytesImpl
  });
}
