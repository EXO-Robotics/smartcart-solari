import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { loadContractSchemas } from './contract-registry.js';

export class ContractValidationError extends Error {
  constructor(schemaId, errors) {
    super(`Value does not satisfy SmartCart contract ${schemaId}`);
    this.name = 'ContractValidationError';
    this.schemaId = schemaId;
    this.errors = errors;
  }
}

function orderedEstimate(_schema, value) {
  return value.minimum <= value.preferred && value.preferred <= value.maximum;
}

export async function createContractValidator(options = {}) {
  const ajv = new Ajv2020({
    allErrors: true,
    strict: true,
    validateFormats: true
  });
  addFormats(ajv);
  ajv.addKeyword({
    keyword: 'smartcartOrderedEstimate',
    schemaType: 'boolean',
    type: 'object',
    validate: orderedEstimate,
    errors: false
  });

  const entries = await loadContractSchemas(options);
  for (const { schema } of entries) {
    ajv.addSchema(schema);
  }

  return {
    schemaIds: entries.map(({ schema }) => schema.$id).sort(),
    validate(schemaId, value) {
      const validate = ajv.getSchema(schemaId);
      if (!validate) throw new Error(`Unknown SmartCart contract schema: ${schemaId}`);
      const valid = validate(value);
      return {
        valid,
        errors: valid ? [] : structuredClone(validate.errors ?? [])
      };
    },
    assert(schemaId, value) {
      const result = this.validate(schemaId, value);
      if (!result.valid) throw new ContractValidationError(schemaId, result.errors);
      return value;
    }
  };
}
