## Question

Two network hospitals, HOS-017 and HOS-022, both process claims in two ways: cashless (the insurer settles directly with the hospital) and reimbursement (the member pays first and claims back). The question asked: which of the two hospitals rejects more claims? The answer should guide network quality reviews - we would rather steer members to the hospital with the safer claims experience.

Source: claims.analytics.r9_paradox (decided = approved + settled + rejected claims; submitted-but-undecided claims are excluded; rejection_rate = rejected / decided, rounded to 4 decimal places).

## Overall

Looking at all decided claims combined, HOS-022 looks clearly better:

| hospital_id | claim_type | decided_count | rejected_count | rejection_rate |
| --- | --- | --- | --- | --- |
| HOS-017 | ALL | 100 | 21 | 0.2100 |
| HOS-022 | ALL | 100 | 11 | 0.1100 |

On the blended number, HOS-017 rejects roughly one claim in five while HOS-022 rejects about one in nine - HOS-022 appears almost twice as good.

## Split by claim type

The same claims, separated by claim type, tell the opposite story:

| hospital_id | claim_type | decided_count | rejected_count | rejection_rate |
| --- | --- | --- | --- | --- |
| HOS-017 | cashless | 20 | 1 | 0.0500 |
| HOS-022 | cashless | 80 | 5 | 0.0625 |
| HOS-017 | reimbursement | 80 | 20 | 0.2500 |
| HOS-022 | reimbursement | 20 | 6 | 0.3000 |

Within cashless claims, HOS-017 rejects 5.00% against HOS-022's 6.25%. Within reimbursement claims, HOS-017 rejects 25.00% against HOS-022's 30.00%. HOS-017 is better in BOTH claim types, yet worse overall.

## Why the overall number misleads

The two hospitals do not see the same mix of work. HOS-017 decided only 20 cashless claims against 80 reimbursement claims (a 20/80 split), while HOS-022 decided 80 cashless against 20 reimbursement (80/20). Cashless claims are rejected far less often than reimbursement claims for both hospitals, so whichever hospital handles more cashless claims gets an artificially low blended rate. HOS-022's overall advantage comes almost entirely from its cashless-heavy caseload, not from better claim handling - in a like-for-like comparison inside either claim type it is the worse performer.

This reversal - the aggregate ranking flipping once the data is split by a hidden subgroup - is the textbook statistical effect known as Simpson's paradox.

## Recommendation

Do not rank hospitals on blended rejection rates. Compare hospitals within each claim type (like-for-like), or use mix-adjusted (stratified or weighted) rates, before any network decision. On like-for-like numbers, HOS-017 is the better-performing hospital in both cashless and reimbursement claims, and HOS-022's favorable overall rate is a composition effect that should not drive member steering or network quality actions.
