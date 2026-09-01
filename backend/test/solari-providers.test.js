import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { SolariBrowserProvider } from '../src/solari/browser-provider.js';
import { SolariSandboxOptimizer } from '../src/solari/sandbox-provider.js';
import { createSolariResearchService } from '../src/solari/research-service.js';
import { controlledDemoProductURL } from '../src/solari/constants.js';
import { runWithinDeadline } from '../src/solari/deadline.js';
import { assertAllowedCandidateURL, assertCanonicalDemoRequest, assertPublicDemoBaseURL } from '../src/solari/url-policy.js';
import { deterministicOptimize, optimizerFingerprint } from '../src/solari/optimizer.js';
import { WalmartFixtureReplayProvider } from '../src/solari/fixture-provider.js';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const fixturePath = path.join(projectRoot, 'contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json');
async function fixtureRequest() { return JSON.parse(await readFile(fixturePath, 'utf8')); }

function demoRequest(request, baseURL = 'https://demo.example/solari-demo') {
  const copy = structuredClone(request);
  copy.retailerID = 'smartcart-demo-grocer';
  copy.executionMode = 'live';
  for (const requirement of copy.requirements) {
    for (const candidate of requirement.candidates) {
      candidate.sourceURL = controlledDemoProductURL(baseURL, candidate.retailerProductID);
    }
  }
  return copy;
}

test('exact URL policy rejects arbitrary hosts, query parameters, and product-ID swaps', async () => {
  const request = await fixtureRequest();
  assert.doesNotThrow(() => assertCanonicalDemoRequest(request));
  for (const sourceURL of [
    'https://evil.example/ip/10414680',
    'https://www.walmart.com/ip/10414680?aff=1',
    'https://www.walmart.com/ip/10534084'
  ]) {
    assert.throws(() => assertAllowedCandidateURL({
      retailerID: 'walmart', productID: '10414680', sourceURL
    }), /allowlist|disallowed/);
  }
  const duplicate = structuredClone(request);
  duplicate.requirements[1].id = duplicate.requirements[0].id;
  assert.throws(() => assertCanonicalDemoRequest(duplicate), { code: 'duplicate_requirement_identity' });
});

test('Browser uses a fresh minimal session and closes page, browser, and client', async () => {
  const request = demoRequest(await fixtureRequest());
  let launchOptions;
  let browserClosed = 0;
  let clientClosed = 0;
  let pageClosed = 0;
  let currentProductID;
  let currentURL;
  const page = {
    async goto(url) { currentURL = url; currentProductID = /([0-9]+)\.html$/.exec(url)[1]; },
    url() { return currentURL; },
    async waitForSelector() {},
    async evaluate() {
      const titles = {
        '623835750': 'Demo Gluten Free Penne Pasta',
        '10307238': 'Demo Shredded Parmesan'
      };
      return {
        productID: currentProductID, title: titles[currentProductID] ?? `Synthetic ${currentProductID}`,
        packageQuantity: currentProductID === '10414680' ? '3' : '6',
        packageUnit: currentProductID === '10414680' ? 'lb' : 'oz',
        priceCents: currentProductID === '10414680' ? '947' : '208', currency: 'USD', rawText: 'visible synthetic evidence'
      };
    },
    async close() { pageClosed += 1; }
  };
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key', now: () => Date.parse('2026-08-31T12:00:00Z'),
    solariFactory: () => ({
      async launch(options) {
        launchOptions = options;
        return { async newPage() { return page; }, async close() { browserClosed += 1; } };
      },
      async close() { clientClosed += 1; }
    })
  });
  const observations = await provider.observe(request);
  assert.equal(observations.length, 6);
  assert.deepEqual(launchOptions, {
    stealth: false, recording: false, captcha: false, proxy: 'off', retries: 0, probe: false
  });
  assert.equal('profileId' in launchOptions, false);
  assert.equal(pageClosed, 6);
  assert.equal(browserClosed, 1);
  assert.equal(clientClosed, 1);
  const glutenFree = observations.find(({ retailerProductID }) => retailerProductID === '623835750');
  assert.equal(glutenFree.confidence, 'medium');
  assert.deepEqual(glutenFree.ambiguityReasons, ['Gluten-free attribute was not requested by this recipe.']);
  const coarseShred = observations.find(({ retailerProductID }) => retailerProductID === '10307238');
  assert.equal(coarseShred.confidence, 'medium');
  assert.deepEqual(coarseShred.ambiguityReasons, ['Shred size is not stated as finely shredded.']);
});

test('Browser and Sandbox fail typed-unavailable when the server key is absent', async () => {
  const request = demoRequest(await fixtureRequest());
  await assert.rejects(() => new SolariBrowserProvider().observe(request), { code: 'solari_unavailable', status: 503 });
  await assert.rejects(() => new SolariSandboxOptimizer().optimize(request.requirements, []), { code: 'solari_unavailable', status: 503 });
});

test('Browser and Sandbox reject work after the aggregate request deadline', async () => {
  const request = demoRequest(await fixtureRequest());
  let browserFactories = 0;
  const browser = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    solariFactory: () => { browserFactories += 1; return {}; }
  });
  await assert.rejects(
    () => browser.observe(request, { deadlineAt: 100, clock: () => 100 }),
    { code: 'solari_request_timeout', status: 504, retryable: true }
  );
  assert.equal(browserFactories, 0);

  let sandboxFactories = 0;
  const sandbox = new SolariSandboxOptimizer({
    apiKey: 'server-only-test-key',
    clientFactory: () => { sandboxFactories += 1; return {}; }
  });
  await assert.rejects(
    () => sandbox.optimize(request.requirements, [], { deadlineAt: 100, clock: () => 100 }),
    { code: 'solari_request_timeout', status: 504, retryable: true }
  );
  assert.equal(sandboxFactories, 0);

  await assert.rejects(
    () => runWithinDeadline(
      () => new Promise(() => {}),
      { configuredTimeoutMs: 20, deadlineAt: Date.now() + 20 }
    ),
    { code: 'solari_request_timeout', status: 504, retryable: true }
  );
});

test('research service shares one aggregate deadline across Browser and Sandbox', async () => {
  const request = demoRequest(await fixtureRequest());
  const fixedNow = Date.parse('2026-09-01T12:00:00Z');
  const observations = await new WalmartFixtureReplayProvider({ now: () => fixedNow }).observe(request);
  let deadlineNow = 1_000;
  let browserDeadline;
  let sandboxDeadline;
  let browserSignal;
  let sandboxSignal;
  const controller = new AbortController();
  const service = createSolariResearchService({
    config: {
      solariDemoRetailerBaseUrl: 'https://demo.example/solari-demo',
      solariRequestTimeoutMs: 45_000
    },
    now: () => fixedNow,
    deadlineClock: () => deadlineNow,
    demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }],
    browserProvider: {
      async observe(_request, context) {
        browserDeadline = context.deadlineAt;
        browserSignal = context.signal;
        deadlineNow = 30_000;
        return observations;
      }
    },
    sandboxOptimizer: {
      async optimize(requirements, admittedObservations, context) {
        sandboxDeadline = context.deadlineAt;
        sandboxSignal = context.signal;
        return deterministicOptimize(requirements, admittedObservations, { method: 'solari-sandbox' });
      }
    }
  });
  const result = await service.research(request, { signal: controller.signal });
  assert.equal(browserDeadline, 46_000);
  assert.equal(sandboxDeadline, browserDeadline);
  assert.equal(browserSignal, controller.signal);
  assert.equal(sandboxSignal, controller.signal);
  assert.equal(result.optimizer.method, 'solari-sandbox');
});

test('aborting an in-flight Browser evaluation closes page, session, and client', async () => {
  const request = demoRequest(await fixtureRequest());
  const controller = new AbortController();
  let evaluationStarted;
  const started = new Promise((resolve) => { evaluationStarted = resolve; });
  let pageClosed = 0;
  let browserClosed = 0;
  let clientClosed = 0;
  let currentURL;
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    timeoutMs: 1_000,
    solariFactory: () => ({
      async launch() {
        return {
          async newPage() {
            return {
              async goto(url) { currentURL = url; },
              url() { return currentURL; },
              async waitForSelector() {},
              async evaluate() {
                evaluationStarted();
                return new Promise(() => {});
              },
              async close() { pageClosed += 1; }
            };
          },
          async close() { browserClosed += 1; }
        };
      },
      async close() { clientClosed += 1; }
    })
  });
  const work = provider.observe(request, {
    deadlineAt: Date.now() + 5_000,
    signal: controller.signal
  });
  await started;
  controller.abort();
  await assert.rejects(() => work, { code: 'solari_request_aborted', status: 408, retryable: true });
  assert.equal(pageClosed, 1);
  assert.equal(browserClosed, 1);
  assert.equal(clientClosed, 1);
});

test('aborting an in-flight Sandbox command kills the microVM', async () => {
  const request = await fixtureRequest();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-07-16T12:01:00Z') }).observe(request);
  const controller = new AbortController();
  let commandStarted;
  const started = new Promise((resolve) => { commandStarted = resolve; });
  let killed = 0;
  const optimizer = new SolariSandboxOptimizer({
    apiKey: 'server-only-test-key',
    timeoutMs: 1_000,
    clientFactory: () => ({
      async create() {
        return {
          commands: {
            async run() {
              commandStarted();
              return new Promise(() => {});
            }
          },
          async kill() { killed += 1; }
        };
      }
    })
  });
  const work = optimizer.optimize(request.requirements, observations, {
    deadlineAt: Date.now() + 5_000,
    signal: controller.signal
  });
  await started;
  controller.abort();
  await assert.rejects(() => work, { code: 'solari_request_aborted', status: 408, retryable: true });
  assert.equal(killed, 1);
});

test('late Browser and Sandbox creation is destroyed before cancellation returns', async () => {
  const request = demoRequest(await fixtureRequest());
  const browserController = new AbortController();let resolveLaunch,launchStarted,lateBrowserClosed=0,clientClosed=0;
  const launchBegan=new Promise((resolve)=>{launchStarted=resolve;});
  const browserProvider=new SolariBrowserProvider({apiKey:'server-only-test-key',timeoutMs:100,
    solariFactory:()=>({launch:async()=>{launchStarted();return new Promise((resolve)=>{resolveLaunch=resolve;});},close:async()=>{clientClosed+=1;}})});
  const browserWork=browserProvider.observe(request,{deadlineAt:Date.now()+1000,signal:browserController.signal});await launchBegan;browserController.abort();
  resolveLaunch({close:async()=>{lateBrowserClosed+=1;}});await assert.rejects(()=>browserWork,{code:'solari_request_aborted'});
  assert.equal(lateBrowserClosed,1);assert.equal(clientClosed,1);

  const sandboxController=new AbortController();let resolveCreate,createStarted,lateKilled=0;
  const createBegan=new Promise((resolve)=>{createStarted=resolve;});
  const optimizer=new SolariSandboxOptimizer({apiKey:'server-only-test-key',timeoutMs:100,
    clientFactory:()=>({create:async()=>{createStarted();return new Promise((resolve)=>{resolveCreate=resolve;});}})});
  const sandboxWork=optimizer.optimize(request.requirements,[],{deadlineAt:Date.now()+1000,signal:sandboxController.signal});await createBegan;sandboxController.abort();
  resolveCreate({kill:async()=>{lateKilled+=1;}});await assert.rejects(()=>sandboxWork,{code:'solari_request_aborted'});assert.equal(lateKilled,1);
});

test('Browser success is withheld unless session and client cleanup are confirmed', async () => {
  const request = demoRequest(await fixtureRequest());
  let currentURL;
  let clientCloseAttempts = 0;
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    solariFactory: () => ({
      async launch() {
        return {
          async newPage() {
            return {
              async goto(url) { currentURL = url; },
              url() { return currentURL; },
              async waitForSelector() {},
              async evaluate() {
                return {
                  productID: /([0-9]+)\.html$/.exec(currentURL)[1],
                  title: 'Synthetic product', packageQuantity: 3, packageUnit: 'lb',
                  priceCents: 947, currency: 'USD', rawText: 'visible synthetic evidence'
                };
              },
              async close() {}
            };
          },
          async close() { throw new Error('release was not confirmed'); }
        };
      },
      async close() { clientCloseAttempts += 1; }
    })
  });
  await assert.rejects(() => provider.observe(request), { code: 'solari_browser_cleanup_failed', status: 502 });
  assert.equal(clientCloseAttempts, 1);
});

test('Browser fails closed when the page does not expose its exact product ID', async () => {
  const request = demoRequest(await fixtureRequest());
  let currentURL;
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    solariFactory: () => ({
      async launch() {
        return {
          async newPage() {
            return {
              async goto(url) { currentURL = url; }, url() { return currentURL; }, async waitForSelector() {},
              async evaluate() { return { productID: null, title: 'Unbound product', packageQuantity: 3, packageUnit: 'lb', priceCents: 947, currency: 'USD', rawText: 'visible' }; },
              async close() {}
            };
          },
          async close() {}
        };
      },
      async close() {}
    })
  });
  await assert.rejects(() => provider.observe(request), { code: 'retailer_product_mismatch' });
});

test('Sandbox uses base microVM, short kill lifecycle, public payload only, and independently verifies output', async () => {
  const request = await fixtureRequest();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-07-16T12:01:00Z') }).observe(request);
  const local = deterministicOptimize(request.requirements, observations, { method: 'solari-sandbox' });
  const expected = optimizerFingerprint(local);
  let createOptions;
  let command;
  let killed = 0;
  const optimizer = new SolariSandboxOptimizer({
    apiKey: 'server-only-test-key', timeoutMs: 7000,
    clientFactory: () => ({
      async create(options) {
        createOptions = options;
        return {
          commands: { async run(name, options) { command = { name, options }; return { exitCode: 0, stdout: expected, stderr: '' }; } },
          async kill() { killed += 1; }
        };
      }
    })
  });
  const result = await optimizer.optimize(request.requirements, observations);
  assert.equal(result.basket.observedSubtotal, 12.79);
  assert.equal(createOptions.template, 'base');
  assert.equal(createOptions.timeoutMs, 7000);
  assert.deepEqual(createOptions.lifecycle, { onTimeout: 'kill', autoResume: false });
  assert.equal('volumes' in createOptions, false);
  assert.equal('fromSnapshot' in createOptions, false);
  assert.equal(command.name, 'python3');
  assert.doesNotMatch(command.options.args[2], /rawText|sourceURL|storeReference|submittedAt/);
  assert.equal(killed, 1);
});

test('Sandbox output is required; live mode never falls back to a local decision', async () => {
  const request = await fixtureRequest();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-07-16T12:01:00Z') }).observe(request);
  let killed = 0;
  const optimizer = new SolariSandboxOptimizer({
    apiKey: 'server-only-test-key',
    clientFactory: () => ({
      async create() {
        return {
          commands: { async run() { return { exitCode: 0, stdout: '{}', stderr: '' }; } },
          async kill() { killed += 1; }
        };
      }
    })
  });
  await assert.rejects(() => optimizer.optimize(request.requirements, observations), { code: 'solari_sandbox_invalid_output' });
  assert.equal(killed, 1);
});

test('Sandbox success is withheld unless microVM destruction is confirmed', async () => {
  const request = await fixtureRequest();
  const observations = await new WalmartFixtureReplayProvider({ now: () => Date.parse('2026-07-16T12:01:00Z') }).observe(request);
  const expected = optimizerFingerprint(deterministicOptimize(request.requirements, observations, { method: 'solari-sandbox' }));
  const optimizer = new SolariSandboxOptimizer({
    apiKey: 'server-only-test-key',
    clientFactory: () => ({
      async create() {
        return {
          commands: { async run() { return { exitCode: 0, stdout: expected, stderr: '' }; } },
          async kill() { throw new Error('kill was not confirmed'); }
        };
      }
    })
  });
  await assert.rejects(() => optimizer.optimize(request.requirements, observations), {
    code: 'solari_sandbox_cleanup_failed', status: 502
  });
});

test('live Walmart Browser never runs without explicit written authorization', async () => {
  const request = await fixtureRequest();
  request.executionMode = 'live';
  let browserCalls = 0;
  const service = createSolariResearchService({
    config: {},
    browserProvider: { async observe() { browserCalls += 1; return []; } },
    sandboxOptimizer: { async optimize() { throw new Error('must not run'); } }
  });
  await assert.rejects(() => service.research(request), { code: 'retailer_research_not_authorized', status: 403 });
  assert.equal(browserCalls, 0);
});

test('only contract-validated public observations reach Solari Sandbox', async () => {
  const request = demoRequest(await fixtureRequest());
  let sandboxCalls = 0;
  const service = createSolariResearchService({
    config: { solariDemoRetailerBaseUrl: 'https://demo.example/solari-demo' },
    demoHostLookup: async () => [{ address: '93.184.216.34', family: 4 }],
    browserProvider: {
      async observe() {
        return [{ schemaVersion: 'retailer-observation-v1', rawText: 'missing all required provenance' }];
      }
    },
    sandboxOptimizer: { async optimize() { sandboxCalls += 1; return {}; } }
  });
  await assert.rejects(() => service.research(request), { code: 'solari_browser_invalid_observation', status: 502 });
  assert.equal(sandboxCalls, 0);
});

test('Solari source contains no interactive commerce, persistence, or evasion calls', async () => {
  const sourceFiles = ['browser-provider.js', 'sandbox-provider.js', 'research-service.js'];
  const source = (await Promise.all(sourceFiles.map((name) => readFile(path.join(projectRoot, 'backend/src/solari', name), 'utf8')))).join('\n');
  for (const pattern of [
    /page\.(click|fill|type|press|check|selectOption)\s*\(/,
    /profiles\.(create|save)\s*\(/,
    /recording:\s*true/,
    /stealth:\s*true/,
    /captcha:\s*true/,
    /createDesktop\s*\(/,
    /\.snapshot\s*\(/,
    /volumes:\s*\[/
  ]) assert.doesNotMatch(source, pattern);
  assert.match(source, /proxy:\s*['"]off['"]/);
  const sandboxSource = await readFile(path.join(projectRoot, 'backend/src/solari/sandbox-provider.js'), 'utf8');
  assert.doesNotMatch(sandboxSource, /deterministicOptimize/);
});

test('controlled Demo Grocer URL rejects private DNS and Browser rejects redirects', async () => {
  await assert.rejects(
    () => assertPublicDemoBaseURL('https://demo.example/solari-demo', { lookup: async () => [{ address: '127.0.0.1', family: 4 }] }),
    { code: 'controlled_demo_url_private' }
  );
  assert.equal(
    await assertPublicDemoBaseURL('https://demo.example/solari-demo', { lookup: async () => [{ address: '93.184.216.34', family: 4 }] }),
    'https://demo.example/solari-demo'
  );

  const request = demoRequest(await fixtureRequest());
  let browserClosed = 0;
  let clientClosed = 0;
  let pageClosed = 0;
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    solariFactory: () => ({
      async launch() {
        return {
          async newPage() {
            return {
              async goto() {}, url() { return 'https://private.example/escaped'; },
              async close() { pageClosed += 1; }
            };
          },
          async close() { browserClosed += 1; }
        };
      },
      async close() { clientClosed += 1; }
    })
  });
  await assert.rejects(() => provider.observe(request), { code: 'retailer_redirect_not_allowed' });
  assert.equal(pageClosed, 1);
  assert.equal(browserClosed, 1);
  assert.equal(clientClosed, 1);
});

test('Browser rejects a client-side redirect that occurs after the admitted page renders', async () => {
  const request = demoRequest(await fixtureRequest());
  let currentURL;
  const provider = new SolariBrowserProvider({
    apiKey: 'server-only-test-key',
    solariFactory: () => ({
      async launch() {
        return {
          async newPage() {
            return {
              async goto(url) { currentURL = url; },
              url() { return currentURL; },
              async waitForSelector() {},
              async evaluate() {
                currentURL = 'https://private.example/client-side-escape';
                return {
                  productID: '10414680', title: 'Synthetic chicken', packageQuantity: 3,
                  packageUnit: 'lb', priceCents: 947, currency: 'USD', rawText: 'redirected evidence'
                };
              },
              async close() {}
            };
          },
          async close() {}
        };
      },
      async close() {}
    })
  });
  await assert.rejects(() => provider.observe(request), { code: 'retailer_redirect_not_allowed' });
});
