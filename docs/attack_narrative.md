# Attack Narrative -- CodeBreach

*An incident report-style retelling of the CodeBreach attack, based on the Wiz Research disclosure of January 15, 2026.*

## Summary

Two missing characters in a regular expression nearly compromised every AWS account on Earth. The vulnerability existed in AWS CodeBuild webhook filters protecting four AWS-managed open-source repositories, including the JavaScript SDK used by 66% of cloud environments and the AWS Console itself.

## Timeline

**T+0:00 -- Reconnaissance.** The security researcher discovers that four AWS-managed CodeBuild projects have public visibility enabled. The project configurations, including webhook filter patterns, are readable by anyone through the CodeBuild API and public builds dashboard. The researcher examines the ACTOR_ACCOUNT_ID filter patterns: lists of GitHub user IDs separated by pipe characters. The patterns look correct at first glance. They are not.

**T+0:15 -- The Discovery.** The researcher notices that the filter patterns lack regex anchor characters. The pattern `755743|234567` should be `^(755743|234567)$`. Without anchors, the regex engine performs substring matching: any 9-digit GitHub user ID containing `755743` anywhere within it will pass the filter. The trusted 6-digit maintainer ID `755743` is a substring of future 9-digit IDs like `226755743`.

**T+0:30 -- The Eclipse.** GitHub assigns user IDs sequentially from a shared counter. The researcher samples the counter by creating and deleting organizations, tracking the auto-incrementing values. They calculate that ID `226755743` will be assigned within days. They prepare 200 GitHub App manifest registration requests and wait.

**T+1:00 -- ID Capture.** When the counter approaches the target range, the researcher visits all 200 confirmation URLs simultaneously. Each creates a new GitHub App with a sequential ID. One of them receives ID `226755743` -- the exact ID needed to bypass the ACTOR_ACCOUNT_ID filter on the aws-sdk-js-v3 repository.

**T+1:05 -- Build Trigger.** Using the new GitHub identity, the researcher submits a pull request to aws-sdk-js-v3. The PR contains a legitimate bug fix with a hidden npm dependency. The dependency's preinstall script is the payload. CodeBuild evaluates the webhook: the ACTOR_ACCOUNT_ID filter passes (substring match). The build triggers.

**T+1:06 -- Credential Theft.** During `npm install`, the malicious dependency executes. It dumps process memory using `/proc/*/environ`, extracting environment variables from all running processes -- including the CodeBuild agent. A GitHub Classic Personal Access Token belonging to `aws-sdk-js-automation` is found in memory. The token has admin access to the repository.

**T+1:10 -- Game Over.** The researcher authenticates with the stolen PAT and confirms admin access to aws-sdk-js-v3 plus three additional repositories, including one linked to an AWS employee's personal account. They can push to main, approve PRs, modify release workflows, and inject code into the next weekly npm release. They stop and report to AWS.

## Impact Assessment

If exploited by a malicious actor, this vulnerability would have enabled injection of arbitrary code into the AWS JavaScript SDK. The SDK is released weekly to npm and is present in 66% of cloud environments. The AWS Console itself bundles recent SDK versions. A single poisoned release would propagate globally, potentially giving the attacker access to every AWS account.

## Resolution

AWS fixed the core regex issue within 48 hours of disclosure and implemented a new Pull Request Comment Approval build gate for all CodeBuild customers. They audited all public build environments, rotated the compromised PAT, and implemented memory protections to prevent credential extraction from build agent processes.
