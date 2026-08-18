export const SMARTCART_SCHEMA_VERSION = '1.0';

export function contractEnvelope({ requestId, resolverVersion, data }) {
  return {
    schemaVersion: SMARTCART_SCHEMA_VERSION,
    resolverVersion,
    requestId,
    data
  };
}
