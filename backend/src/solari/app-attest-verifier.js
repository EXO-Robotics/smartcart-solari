import { createHash, createPublicKey, timingSafeEqual, verify as verifySignature, webcrypto, X509Certificate } from 'node:crypto';
import * as asn1js from 'asn1js';
import cbor from 'cbor';
import { Certificate, ContentInfo, CryptoEngine, setEngine, SignedData } from 'pkijs';
import { SolariResearchError } from './errors.js';

const NONCE_OID = '1.2.840.113635.100.8.2';
const { decodeFirstSync } = cbor;
const PROD_AAGUID = Buffer.concat([Buffer.from('appattest', 'ascii'), Buffer.alloc(7)]);
const APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;
const RECEIPT_ROOT_DER = Buffer.from('MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==','base64');

setEngine('smartcart-node', new CryptoEngine({ name: 'smartcart-node', crypto: webcrypto, subtle: webcrypto.subtle }));

function fail(code, message) { throw new SolariResearchError(code, message, { status: 403 }); }
function sha256(...parts) { const hash=createHash('sha256'); for(const part of parts)hash.update(part); return hash.digest(); }
function equal(a,b){return Buffer.isBuffer(a)&&Buffer.isBuffer(b)&&a.length===b.length&&timingSafeEqual(a,b);}
function strictBase64(value, maxBytes, name) {
  if (typeof value !== 'string' || value.length === 0 || value.length > maxBytes * 2 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) fail('app_attest_malformed', `${name} must be canonical Base64.`);
  const bytes=Buffer.from(value,'base64'); if(bytes.length===0||bytes.length>maxBytes||bytes.toString('base64')!==value)fail('app_attest_malformed',`${name} is malformed.`); return bytes;
}
function strictBase64URL(value, expected, name) {
  if(typeof value!=='string'||!/^[A-Za-z0-9_-]+$/.test(value))fail('app_attest_malformed',`${name} must be unpadded Base64URL.`);const bytes=Buffer.from(value,'base64url');if(bytes.length!==expected||bytes.toString('base64url')!==value)fail('app_attest_malformed',`${name} is malformed.`);return bytes;
}
function strictCBOR(bytes, name) { try{return decodeFirstSync(bytes,{preventDuplicateKeys:true,preferMap:false});}catch{fail('app_attest_malformed',`${name} is not one strict CBOR object.`);} }
function parseX509(bytes){try{return new X509Certificate(bytes);}catch{fail('app_attest_certificate_invalid','The App Attest certificate is invalid.');}}
function parsePKICertificate(bytes){const parsed=asn1js.fromBER(bytes);if(parsed.offset===-1||parsed.offset!==bytes.length)fail('app_attest_certificate_invalid','The certificate DER is invalid.');return new Certificate({schema:parsed.result});}
function assertCurrent(cert,now){const instant=now();if(instant<Date.parse(cert.validFrom)||instant>Date.parse(cert.validTo))fail('app_attest_certificate_invalid','The App Attest certificate is outside its validity period.');}
function decodeASN1(bytes){const parsed=asn1js.fromBER(bytes);if(parsed.offset===-1||parsed.offset!==bytes.length)fail('app_attest_malformed','An App Attest ASN.1 value is malformed.');return parsed.result;}
function findOctet(node,length){if(node instanceof asn1js.OctetString){const b=Buffer.from(node.valueBlock.valueHexView);if(b.length===length)return b;try{return findOctet(decodeASN1(b),length);}catch{return null;}}for(const child of node?.valueBlock?.value??[]){const found=findOctet(child,length);if(found)return found;}return null;}
function parseAuthenticatorData(authData,{attestation=false}={}){
  if(!Buffer.isBuffer(authData)||authData.length<(attestation?55:37)||authData.length>4096)fail('app_attest_malformed','Authenticator data is truncated or oversized.');
  const base={rpIdHash:authData.subarray(0,32),flags:authData[32],counter:authData.readUInt32BE(33)};
  if(!attestation){if(authData.length!==37||(base.flags&0xc0)!==0)fail('app_attest_invalid','Assertion authenticator flags or length are invalid.');return base;}
  if((base.flags&0x40)===0||(base.flags&0x80)===0)fail('app_attest_invalid','Attested credential data or required extensions are missing.');
  const credentialLength=authData.readUInt16BE(53),credentialStart=55,credentialEnd=credentialStart+credentialLength;
  if(credentialLength!==32||credentialEnd>=authData.length)fail('app_attest_invalid','Credential ID is malformed.');
  const cose=decodeFirstSync(authData.subarray(credentialEnd),{extendedResults:true,preventDuplicateKeys:true,preferMap:true});
  if(cose.unused===null)fail('app_attest_invalid','Required App Attest authenticator extensions are missing.');
  const extensions=strictCBOR(Buffer.from(cose.unused),'authenticator extensions');
  return {...base,aaguid:authData.subarray(37,53),credentialID:authData.subarray(credentialStart,credentialEnd),coseKey:cose.value,extensions};
}
function extensionValue(extensions,name){return extensions instanceof Map?extensions.get(name):extensions?.[name];}
function validationCategory(value){if(Number.isSafeInteger(value))return value;if(Buffer.isBuffer(value)&&value.length===4)return value.readUInt32LE(0);return null;}
function bundleVersion(value){if(typeof value==='string')return value;if(Buffer.isBuffer(value)){try{const node=decodeASN1(value);return node.valueBlock?.value??node.valueBlock?.valueHexView?.toString();}catch{return value.toString('utf8');}}return null;}
function publicKeyPoint(cert){const jwk=cert.publicKey.export({format:'jwk'});return Buffer.concat([Buffer.from([4]),Buffer.from(jwk.x,'base64url'),Buffer.from(jwk.y,'base64url')]);}
function assertCoseMatchesCertificate(cose,cert){const jwk=cert.publicKey.export({format:'jwk'});if(!(cose instanceof Map)||cose.get(1)!==2||cose.get(3)!==-7||cose.get(-1)!==1||!equal(cose.get(-2),Buffer.from(jwk.x,'base64url'))||!equal(cose.get(-3),Buffer.from(jwk.y,'base64url')))fail('app_attest_key_mismatch','The COSE credential key does not match its certificate.');}
function spkiBase64(cert){return cert.publicKey.export({type:'spki',format:'der'}).toString('base64');}

function parseReceiptFields(payload){
  const root=decodeASN1(payload); const fields=new Map();
  for(const sequence of root.valueBlock?.value??[]){const items=sequence.valueBlock?.value??[];if(items.length!==3)continue;const type=Number(items[0].valueBlock?.valueDec);const raw=Buffer.from(items[2].valueBlock?.valueHexView??[]);if(Number.isSafeInteger(type))fields.set(type,raw);}
  return fields;
}
function innerString(bytes){const node=decodeASN1(bytes);return String(node.valueBlock?.value??'');}
function cmsContentBytes(eContent){
  if(!eContent)return Buffer.alloc(0);
  const direct=Buffer.from(eContent.valueBlock?.valueHexView??[]);if(direct.length)return direct;
  return Buffer.concat((eContent.valueBlock?.value??[]).map((part)=>Buffer.from(part.valueBlock?.valueHexView??[])));
}

async function verifyReceipt(receipt,{appID,leaf,clientDataHash,now,receiptRootDER=RECEIPT_ROOT_DER}){
  const parsed=asn1js.fromBER(receipt);if(parsed.offset===-1||parsed.offset!==receipt.length)fail('app_attest_receipt_invalid','The App Attest receipt is malformed.');
  const contentInfo=new ContentInfo({schema:parsed.result});if(contentInfo.contentType!=='1.2.840.113549.1.7.2')fail('app_attest_receipt_invalid','The App Attest receipt is not CMS SignedData.');
  const signed=new SignedData({schema:contentInfo.content});
  const content=cmsContentBytes(signed.encapContentInfo.eContent);if(content.length===0)fail('app_attest_receipt_invalid','The App Attest receipt has no signed payload.');
  const fields=parseReceiptFields(content);const creation=Date.parse(innerString(fields.get(12)??Buffer.alloc(0)));
  if(!Number.isFinite(creation)||Math.abs(now()-creation)>300000)fail('app_attest_receipt_invalid','The App Attest receipt is stale.');
  const root=parsePKICertificate(receiptRootDER);let verified=false;try{verified=await signed.verify({signer:0,trustedCerts:[root],checkDate:new Date(creation),checkChain:true});}catch{}
  if(!verified)fail('app_attest_receipt_invalid','The App Attest receipt signature or chain is invalid.');
  if(innerString(fields.get(2)??Buffer.alloc(0))!==appID)fail('app_attest_receipt_invalid','The App Attest receipt App ID does not match.');
  if(innerString(fields.get(4)??Buffer.alloc(0)).toLowerCase()!==clientDataHash.toString('hex'))fail('app_attest_receipt_invalid','The App Attest receipt client hash does not match the challenge.');
  if(innerString(fields.get(6)??Buffer.alloc(0))!=='ATTEST')fail('app_attest_receipt_invalid','The initial App Attest receipt type is invalid.');
  const attested=fields.get(3);if(!attested)fail('app_attest_receipt_invalid','The App Attest receipt omitted its attested public key.');
  let matches=false;
  try {
    const encoded=innerString(attested),certificateDER=Buffer.from(encoded,'base64');
    if(certificateDER.length===0||certificateDER.toString('base64')!==encoded)throw new Error('non-canonical receipt key');
    matches=spkiBase64(new X509Certificate(certificateDER))===spkiBase64(leaf);
  } catch {
    try{matches=spkiBase64(new X509Certificate(attested))===spkiBase64(leaf);}catch{}
  }
  if(!matches)fail('app_attest_receipt_invalid','The App Attest receipt public key does not match.');
  return {creationTime:new Date(creation).toISOString(),digest:sha256(receipt).toString('base64url')};
}

export function assertionClientData({challenge,method='POST',path='/v1/solari/research',payloadBytes}){
  const challengeBytes=strictBase64URL(challenge,32,'challenge');
  const bodyDigest=sha256(payloadBytes).toString('base64url');
  const bytes=Buffer.from(`smartcart-app-attest-v1\n${challengeBytes.toString('base64url')}\n${method}\n${path}\n${bodyDigest}\n`,'utf8');
  return {bytes,hash:sha256(bytes),bodyDigest};
}

export class AppleAppAttestVerifier {
  constructor({teamID,bundleID,allowedBuilds,allowedValidationCategories=[2],researchPath='/v1/solari/research',now=Date.now,appAttestRootPEM=APP_ATTEST_ROOT_PEM,receiptRootDER=RECEIPT_ROOT_DER,receiptVerifier=verifyReceipt}={}){
    this.appID=`${teamID}.${bundleID}`;this.rpIdHash=sha256(Buffer.from(this.appID));this.allowedBuilds=new Set(allowedBuilds??[]);this.allowedValidationCategories=new Set(allowedValidationCategories??[]);this.researchPath=researchPath;this.now=now;this.appAttestRoot=new X509Certificate(appAttestRootPEM);this.receiptRootDER=receiptRootDER;this.receiptVerifier=receiptVerifier;
    if(!teamID||!bundleID||this.allowedBuilds.size===0||this.allowedValidationCategories.size!==1||[...this.allowedValidationCategories].some((value)=>![2,3,4].includes(value))||!['/v1/solari/research','/dev/v1/solari/research'].includes(this.researchPath))throw new SolariResearchError('app_attest_not_configured','App Attest identity, build, validation-category, and research-path allowlists are not configured.',{status:503});
  }
  async verifyAttestation({keyID,attestationObject,challenge}){
    const keyBytes=strictBase64(keyID,64,'keyID');if(keyBytes.length!==32)fail('app_attest_malformed','keyID must decode to 32 bytes.');
    const object=strictCBOR(strictBase64(attestationObject,32768,'attestationObject'),'attestationObject');
    if(object?.fmt!=='apple-appattest'||!Buffer.isBuffer(object.authData)||!Array.isArray(object.attStmt?.x5c)||object.attStmt.x5c.length<2||object.attStmt.x5c.length>4||!Buffer.isBuffer(object.attStmt.receipt))fail('app_attest_malformed','Attestation object shape is invalid.');
    const certs=object.attStmt.x5c.map(parseX509),leaf=certs[0];for(const cert of certs)assertCurrent(cert,this.now);if(leaf.ca||certs.slice(1).some((cert)=>!cert.ca))fail('app_attest_certificate_invalid','The App Attest certificate constraints are invalid.');
    for(let index=0;index<certs.length-1;index++)if(!certs[index].verify(certs[index+1].publicKey))fail('app_attest_certificate_invalid','The App Attest certificate chain is invalid.');
    const last=certs.at(-1);if(!last.verify(this.appAttestRoot.publicKey)||last.ca!==true)fail('app_attest_certificate_invalid','The App Attest certificate chain is not rooted in Apple.');
    const clientDataHash=sha256(strictBase64URL(challenge,32,'challenge')),nonce=sha256(object.authData,clientDataHash);
    const leafPKI=parsePKICertificate(leaf.raw);const extension=leafPKI.extensions?.find(({extnID})=>extnID===NONCE_OID);if(!extension||!equal(findOctet(decodeASN1(Buffer.from(extension.extnValue.valueBlock.valueHexView)),32),nonce))fail('app_attest_nonce_invalid','The App Attest nonce does not match the challenge.');
    if(!equal(sha256(publicKeyPoint(leaf)),keyBytes))fail('app_attest_key_mismatch','The App Attest key ID does not match its certificate.');
    const auth=parseAuthenticatorData(object.authData,{attestation:true});if(!equal(auth.rpIdHash,this.rpIdHash)||auth.counter!==0||!equal(auth.aaguid,PROD_AAGUID)||!equal(auth.credentialID,keyBytes))fail('app_attest_identity_invalid','The App Attest authenticator identity is invalid.');assertCoseMatchesCertificate(auth.coseKey,leaf);
    const category=validationCategory(extensionValue(auth.extensions,'apple_validation_category_01'));const build=bundleVersion(extensionValue(auth.extensions,'apple_bundle_version_01'));
    if(!this.allowedValidationCategories.has(category)||!this.allowedBuilds.has(build))fail('app_attest_distribution_invalid','The App Attest validation category or build is not allowlisted.');
    const receipt=await this.receiptVerifier(object.attStmt.receipt,{appID:this.appID,leaf,clientDataHash,now:this.now,receiptRootDER:this.receiptRootDER});
    return {publicKeySPKI:spkiBase64(leaf),appID:this.appID,environment:'production',validationCategory:category,bundleVersion:build,counter:0,receiptCreatedAt:receipt.creationTime,receiptDigest:receipt.digest};
  }
  verifyAssertion({assertionObject,challenge,payloadBytes,keyRecord}){
    const object=strictCBOR(strictBase64(assertionObject,16384,'assertionObject'),'assertionObject');if(!Buffer.isBuffer(object?.authenticatorData)||!Buffer.isBuffer(object?.signature))fail('app_attest_malformed','Assertion object shape is invalid.');
    const auth=parseAuthenticatorData(object.authenticatorData);if(!equal(auth.rpIdHash,this.rpIdHash))fail('app_attest_identity_invalid','Assertion RP ID does not match.');
    const client=assertionClientData({challenge,path:this.researchPath,payloadBytes});const signed=Buffer.concat([object.authenticatorData,client.hash]);
    const publicKey=createPublicKey({key:Buffer.from(keyRecord.publicKeySPKI,'base64'),format:'der',type:'spki'});if(!verifySignature('sha256',signed,publicKey,object.signature))fail('app_attest_assertion_invalid','The App Attest assertion signature is invalid.');
    if(keyRecord.environment!=='production'||!this.allowedValidationCategories.has(keyRecord.validationCategory)||!this.allowedBuilds.has(keyRecord.bundleVersion))fail('app_attest_distribution_invalid','The attested key validation category or build is not allowlisted.');
    return {counter:auth.counter,bodyDigest:client.bodyDigest};
  }
}

export const appAttestEncoding = { strictBase64, strictBase64URL };
