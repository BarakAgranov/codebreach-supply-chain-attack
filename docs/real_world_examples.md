# Real-World Examples -- CodeBreach

Breaches and incidents that used techniques similar to this scenario.

## 1. CodeBreach (Wiz Research, January 2026)

This exact attack chain. Two missing regex characters in AWS CodeBuild webhook filters exposed the aws-sdk-js-v3 repository to supply chain compromise. The SDK is used by 66% of cloud environments and the AWS Console itself. AWS fixed the issue within 48 hours of Wiz's responsible disclosure in August 2025.

**Techniques in common:** Webhook filter bypass, build environment credential theft, GitHub PAT exploitation, CI/CD pipeline as attack vector.

## 2. SolarWinds SUNBURST (December 2020)

APT29 (Cozy Bear) compromised the SolarWinds Orion build pipeline to inject the SUNBURST backdoor into software updates. The poisoned update was distributed to approximately 18,000 organizations including US government agencies and Fortune 500 companies. The attackers had access for 14 months before detection.

**Techniques in common:** Build pipeline compromise, supply chain propagation, credential theft from build environment, legitimate software distribution as attack vector.

## 3. Codecov Bash Uploader (April 2021)

Attackers modified Codecov's bash uploader script to harvest environment variables from CI pipelines. For over two months, the modified script exfiltrated AWS keys, deploy keys, and API tokens from 29,000 customers. The attack went undetected because the modified script still performed its intended function.

**Techniques in common:** CI/CD environment variable theft, build-time credential harvesting, supply chain through developer tooling.

## 4. tj-actions/changed-files (March 2025)

A compromised bot PAT allowed attackers to rewrite GitHub Action version tags. By modifying the action code pointed to by existing tags, they injected credential-dumping code that executed in CI runners across 23,000 repositories. CISA issued a formal advisory (CVE-2025-30066).

**Techniques in common:** GitHub PAT compromise, CI/CD pipeline injection, credential dumping from build environment, supply chain through GitHub Actions.

## 5. event-stream (November 2018)

A social engineering campaign gave an attacker npm publish access to the event-stream package (8 million weekly downloads). They injected an encrypted payload targeting the Copay Bitcoin wallet. The malicious code was active for three months before a developer noticed the dependency change.

**Techniques in common:** npm supply chain compromise, malicious dependency injection, targeting widely-used packages for maximum blast radius.

## 6. ua-parser-js (October 2021)

An attacker compromised the npm account for ua-parser-js (8 million weekly downloads) and published three malicious versions containing a cryptocurrency miner and password stealer. The attack lasted only 4 hours but affected millions of installations due to automatic dependency resolution.

**Techniques in common:** npm credential compromise, supply chain through popular package, automated propagation through package managers.

## Key Patterns Across All Incidents

1. **CI/CD is the new perimeter.** Build pipelines have broad access to credentials, source code, and deployment infrastructure. Compromising the pipeline gives access to everything it touches.

2. **Identity credentials are the primary target.** Every incident involves stealing or abusing identity credentials (PATs, API keys, npm tokens) found in build environments.

3. **Supply chain amplifies impact.** A single compromised component propagates to thousands or millions of downstream consumers automatically.

4. **Detection is harder than prevention.** Most of these attacks were discovered weeks or months later. CSPM-style prevention (finding the misconfiguration before exploitation) is more effective than CDR-style detection (catching the attack in progress).
