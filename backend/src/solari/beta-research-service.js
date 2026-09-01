import { createContractValidator } from '../contracts/contract-validator.js';
import { SolariBrowserProvider } from './browser-provider.js';
import { controlledDemoProductURL, PRODUCT_REQUIREMENT } from './constants.js';
import { SolariResearchError } from './errors.js';
import { SolariSandboxOptimizer } from './sandbox-provider.js';
import { assertPublicDemoBaseURL } from './url-policy.js';

export const V2_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v2/solari/basket-research-request.schema.json';
export const V2_RESULT_SCHEMA_ID = 'https://schemas.smartcart.app/v2/solari/basket-research-result.schema.json';
export const V2_ENVELOPE_SCHEMA_ID = 'https://schemas.smartcart.app/v2/solari/app-attest-research-envelope.schema.json';
export const V2_CHALLENGE_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v2/solari/app-attest-challenge-request.schema.json';
export const V2_ATTESTATION_REQUEST_SCHEMA_ID = 'https://schemas.smartcart.app/v2/solari/app-attestation-request.schema.json';

function assertBoundedRequest(request, baseURL) {
  if (request.retailerID !== 'smartcart-demo-grocer' || request.executionMode !== 'live') {
    throw new SolariResearchError('beta_retailer_not_allowed', 'The beta admits only live owned Demo Grocer research.', { status: 400 });
  }
  const requirementIDs = new Set(), ingredientIDs = new Set(), products = new Set();
  for (const requirement of request.requirements) {
    const rid=requirement.id.toLowerCase(),iid=requirement.ingredientID.toLowerCase();
    if(requirementIDs.has(rid)||ingredientIDs.has(iid))throw new SolariResearchError('duplicate_requirement_identity','Requirement and ingredient IDs must be unique.',{status:400});
    requirementIDs.add(rid);ingredientIDs.add(iid);
    const groups=new Set(requirement.candidateProductIDs.map((id)=>PRODUCT_REQUIREMENT[id]));
    if(groups.has(undefined)||groups.size!==1)throw new SolariResearchError('beta_candidate_group_mismatch','Each requirement must use one admitted Demo Grocer product group.',{status:400});
    const group=[...groups][0],name=requirement.name.toLowerCase();
    const semanticMatch=group==='chicken'?name.includes('chicken')&&requirement.unit==='lb'
      :group==='penne'?(name.includes('penne')||name.includes('pasta'))&&requirement.unit==='oz'
        :name.includes('parmesan')&&requirement.unit==='oz';
    if(!semanticMatch)throw new SolariResearchError('beta_candidate_semantics_mismatch','Candidate products do not match the requirement ingredient and unit.',{status:400});
    for(const id of requirement.candidateProductIDs){if(products.has(id))throw new SolariResearchError('duplicate_candidate','Candidate product IDs must be unique across the request.',{status:400});products.add(id);}
  }
  return {
    ...request,
    requirements: request.requirements.map(({candidateProductIDs,...requirement})=>({
      ...requirement,
      candidates:candidateProductIDs.map((retailerProductID)=>({retailerProductID,sourceURL:controlledDemoProductURL(baseURL,retailerProductID)}))
    }))
  };
}

export function createSolariBetaResearchService(options={}) {
  const config=options.config??{}, now=options.now??Date.now, clock=options.deadlineClock??Date.now;
  const validatorPromise=options.validator?Promise.resolve(options.validator):createContractValidator();
  const browser=options.browserProvider??new SolariBrowserProvider({apiKey:config.solariApiKey,baseURL:config.solariBrowserBaseUrl,timeoutMs:config.solariBrowserTimeoutMs,now});
  const sandbox=options.sandboxOptimizer??new SolariSandboxOptimizer({apiKey:config.solariApiKey,baseURL:config.solariSandboxBaseUrl,timeoutMs:config.solariSandboxTimeoutMs});
  async function research(request,{signal}={}){
    if(!config.solariApiKey)throw new SolariResearchError('solari_unavailable','Solari is unavailable because the server-side API key is not configured.',{status:503});
    if(!config.solariDemoRetailerBaseUrl)throw new SolariResearchError('controlled_demo_unavailable','The owned Demo Grocer base URL is not configured.',{status:503});
    await assertPublicDemoBaseURL(config.solariDemoRetailerBaseUrl,{lookup:options.demoHostLookup});
    const bounded=assertBoundedRequest(request,config.solariDemoRetailerBaseUrl),deadlineAt=clock()+config.solariRequestTimeoutMs;
    const observationsV1=await browser.observe(bounded,{deadlineAt,clock,signal});
    const optimized=await sandbox.optimize(bounded.requirements,observationsV1,{deadlineAt,clock,signal});
    const observations=observationsV1.map((value)=>({...value,schemaVersion:'retailer-observation-v2'}));
    const decisions=optimized.decisions.map((value)=>({...value,schemaVersion:'basket-decision-v2'}));
    const result={
      schemaVersion:'solari-shopping-research-result-v2',requestID:request.requestID,demoID:request.demoID,
      retailerID:'smartcart-demo-grocer',completedAt:new Date(now()).toISOString(),executionMode:'live',status:optimized.basket.completeness,
      observations,decisions,basket:optimized.basket,optimizer:optimized.optimizer,
      provenance:{browser:'solari-browser',sandbox:'solari-sandbox',fixtureReplay:false,accessBoundary:'apple-app-attest',resourceCleanup:{browser:'enforced-before-response',sandbox:'enforced-before-response'}},
      trust:{priceClaim:'observed-visible-price-not-guaranteed',accountAccessed:false,cartModified:false,checkoutAutomated:false,userControlsHandoff:true,limitations:['Visible prices are timestamped observations, not guarantees or checkout quotes.','Availability, tax, fees, fulfillment, and checkout totals remain unknown.','No account, cart, or checkout action was performed.']}
    };
    const validator=await validatorPromise;validator.assert(V2_RESULT_SCHEMA_ID,result);return result;
  }
  return {research};
}
