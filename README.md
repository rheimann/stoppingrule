# Stopping Rules for AI Deployment Evaluation

> A dual-lane, rate-bounded, saturation-aware method for deciding when pre-deployment evaluation has produced enough evidence to support a release.

**Paper:** (https://github.com/rheimann/stoppingrule/blob/main/Toward_Transparent_Stopping_Rules_for_AI_Deployment_Evaluation_A_Dual_Lane_Rate_Bounded_and_Saturation_Aware_Method.pdf)  
**Status:** Research prototype and technical reference, not an implementation guide.

## Why this exists

When is an AI system ready for production?

This is not the same question as whether the system performs well on a benchmark, receives mostly positive feedback, or has been tested for a fixed number of days. It is a governance question:

> How much evidence is enough to make a release decision defensible?

Most evaluation practices do not answer it. The problem is often a category error: documentation, proxy scoring, benchmarking, and telemetry are treated as if they were release criteria.

## Why common evaluation approaches are insufficient

These approaches are not useless. They are simply being asked to answer a question they cannot answer.

| Approach | What it is useful for | Why it does not establish release readiness |
|---|---|---|
| **System cards** | Documentation, transparency, known limitations, and intended-use statements | A system card can document a release decision, but it does not determine how much evidence is enough or define an acceptance threshold. |
| **RAGAS-style metrics** | Regression detection and coarse diagnostics for retrieval and generation pipelines | They compress proxies such as relevance, faithfulness, or context use into aggregate scores, often using another model as the judge. Unless those scores are calibrated to a specific failure and a pre-specified threshold, the decimal creates precision without a defensible risk claim. |
| **Model-level benchmarks** | Comparing models on standardized tasks | Organizations deploy applications, not isolated models. Deployment risk lives in the prompts, retrieval, tools, memory, permissions, controls, users, data, and workflow. A benchmark can contain thousands of items and still provide little evidence if it measures the wrong distribution and failure modes. |
| **Positive user feedback** | Product telemetry and prioritization | A system can receive 80% positive feedback and still contain a severe unresolved failure mode. Aggregate satisfaction can hide low-frequency, high-consequence failures, and users may not recognize subtle errors. |
| **Fixed evaluation budgets** | Planning time and cost | Fourteen days, 500 traces, or one red-team sprint tells a team when the budget ends. It does not establish that the evidence is sufficient. |
| **Informal saturation** | Guiding exploratory manual testing | “We stopped finding new things” is highly dependent on the testers, taxonomy, search strategy, incentives, and schedule pressure. When saturation is declared after reviewing the results, it becomes a post hoc acceptance criterion. |

## Manual error analysis is the right starting point

The application-specific evaluation methodology taught by Hamel Husain and Shreya Shankar is much stronger than generic benchmark or aggregate-score approaches.

The basic loop is:

1. Inspect real application outputs and traces.
2. Identify concrete failures.
3. Build an error taxonomy.
4. Construct targeted evaluations around observed failure mechanisms.
5. Improve the system and repeat.

This is how a team learns how its application actually fails. It answers the engineering questions:

- What is going wrong?
- Why is it going wrong?
- What should we fix next?

But it does not fully answer the governance questions:

- How much evidence is enough?
- When should evaluation stop?
- What makes the release decision consistent and reviewable?

## AI evaluation has a stopping problem

Without an explicit stopping rule, teams tend to stop for reasons unrelated to evidence sufficiency:

- the launch date arrives;
- the evaluation budget is exhausted;
- the results feel reassuring;
- the team is burned out; or
- everyone believes the system has been “tested to death.”

A fixed evaluation budget is not a stopping rule. It is a budget cap.

The absence of a stopping rule creates two symmetric problems. Teams can stop too early and leave material residual risk unresolved, or continue evaluating after additional testing is unlikely to change the release decision.

## “Saturation vibes” are not acceptance criteria

Saturation is a useful idea. Informal saturation is a weak release standard.

Different teams will reach different conclusions because saturation depends on:

- who performs the testing;
- how creative or adversarial the testers are;
- how severe failures are classified;
- which parts of the application are searched;
- whether the taxonomy is too broad or too narrow;
- how much schedule pressure the team is under; and
- whether the search process is repeatedly sampling the same region of the problem space.

More importantly, saturation is often defined only after the results are known. The team stops finding new failures, decides that the evidence feels sufficient, and then describes that point as the acceptance criterion.

That is a version of the Texas sharpshooter problem: draw the target around the observed evidence and then claim the evidence hit the target.

This may be workable inside an engineering iteration loop. It is a poor standard for PMs, product owners, executives, risk owners, and public officials who must make consistent and defensible release decisions.

## What a defensible stopping rule requires

The target must be drawn before testing begins.

For a fixed release candidate, the evaluation plan should pre-specify:

- what counts as a severe failure;
- which deployment-critical slices matter;
- the maximum acceptable severe-failure rate in each slice;
- the confidence required for each rate claim;
- what counts as a relevant evaluation opportunity;
- the minimum evidence required before saturation statistics are interpreted;
- what evidence would indicate that targeted testing is no longer discovering materially new severe failure mechanisms; and
- the monitoring, escalation, rollback, and post-deployment evaluation controls required for release.

The purpose is not to eliminate judgment. It is to make judgment prospective, explicit, consistent, and reviewable.

## Proposed method: two lanes

Deployment readiness is framed as the conjunction of two different claims.

### Lane A: representative testing

Lane A asks:

> In deployment-critical situations, is the post-control severe-failure rate below an agreed threshold with a stated level of confidence?

For each critical slice `h`, define:

- `n_h`: relevant evaluation opportunities;
- `x_h`: uncaught severe failures;
- `τ_h`: accepted severe-failure threshold; and
- `U_h(α)`: a one-sided exact upper confidence bound.

The lane passes only when:

```text
U_h(α) ≤ τ_h  for every deployment-critical slice h
```

The denominator matters. A relevant opportunity is an interaction in which the failure could actually have occurred. Arbitrary chat counts can dilute the denominator and produce a misleadingly reassuring rate.

### A useful zero-failure intuition

When no severe failures are observed, the one-sided 95% upper bound is approximately `3 / n`, commonly called the rule of three.

| Desired upper bound | Approximate zero-failure opportunities required |
|---:|---:|
| 1.0% | 300 |
| 0.5% | 600 |
| 0.1% | 3,000 |

Zero observed failures therefore does not mean zero risk. It means the data support an upper bound whose strength depends on the number of relevant opportunities tested.

### Lane B: targeted discovery

Lane B asks:

> Under targeted, adversarial, and edge-case testing, are we still discovering materially new ways the system can fail?

Failure types are defined at the mechanism level, not the prompt-string level. Ten prompts that trigger the same fabricated-citation mechanism are repetitions of one mechanism, not ten distinct types.

The targeted lane tracks:

- the cumulative discovery curve for distinct severe mechanisms;
- rolling novelty, or the number of new severe mechanisms found in a recent evaluation window; and
- estimated missing mass, using the proportion of severe mechanisms observed only once as a signal that substantial unseen tail mass may remain.

A simple form of the saturation criteria is:

```text
No new severe mechanism appears in the current targeted window
and
estimated missing mass ≤ the pre-specified threshold
```

The targeted lane is a search process, not a production sample. Its missing-mass estimate should not be interpreted as the production probability of failure. It is evidence about whether the current search process is still learning important new ways the system breaks.

### Operational readiness

A statistical stopping rule is not sufficient by itself. Release also requires:

- monitoring;
- escalation paths;
- rollback capability;
- incident ownership; and
- post-deployment test, evaluation, verification, and validation.

Stopping is not a claim of perfection. It is a claim that the remaining uncertainty is bounded enough to be managed for the proposed release stage.

## Composite stopping rule

A system advances only when all of the following are true:

1. **Rate bound:** every deployment-critical slice satisfies its pre-specified severe-failure threshold.
2. **Recent saturation:** the current targeted-testing window contains no materially new severe mechanism.
3. **Tail mass:** the estimated unseen mass under the targeted search process is below a pre-specified threshold after sufficient evidence has accumulated.
4. **Operational readiness:** monitoring, escalation, rollback, and post-deployment evaluation are in place.

Neither lane is sufficient on its own.

- A low representative failure rate does not establish that the long tail of failure mechanisms has been adequately explored.
- A period with no newly discovered failure types does not establish that the production-relevant failure rate is acceptable.
- A fixed budget establishes only that the organization spent its allotted time or money.

## What the simulation suggests

The paper includes a stylized Monte Carlo study comparing fixed-budget, recent-novelty, rate-only, and dual-lane stopping rules.

In the safe, long-tail scenario:

| Rule | Premature-stop rate |
|---|---:|
| Fixed budget | 100.0% |
| Recent novelty | 22.7% |
| Rate only | 25.0% |
| Dual rule | 5.0% |

The dual rule used more evaluations and stopped less often. That is the intended tradeoff: the evidence requirement follows the risk rather than the project calendar.

In the unsafe, long-tail scenario, the recent-novelty rule stopped in every run and was wrong every time. The dual rule refused to stop within the available budget because the representative risk claim could not be supported.

These simulations are not field validation. They show that the method has interpretable operating characteristics and that the second lane adds value in long-tail settings where simpler heuristics are fragile.

## The release claim

The method does not prove that an AI system is safe, correct, or complete. It supports a narrower claim:

> For this release candidate, this use case, this severity taxonomy, these deployment-critical slices, and this targeted search process, the available evidence is sufficient to justify stopping because additional testing is unlikely to materially change the release decision.

That is the missing bridge between good manual error analysis and deployment governance.

Without a stopping rule, evaluation may still be excellent engineering work. It remains a weak framework for deciding whether to release.

## What this method does not claim

This project does not provide:

- a universal number of evaluations required for every AI system;
- proof that no harmful failure will occur after deployment;
- an exact production-risk estimate from targeted testing;
- a substitute for application-specific severity definitions and risk tolerances; or
- a way to combine evidence across changing release candidates without additional assumptions.

The method currently assumes a fixed release candidate. If the model, prompt, retrieval system, tools, controls, or workflow changes materially, the accumulated evidence may no longer support the same claim.

## Open questions

The most important remaining questions are organizational as much as statistical:

- How should organizations translate risk tolerance into per-slice thresholds?
- How should severe-failure taxonomies be governed?
- How robust are saturation signals under adaptive human red-teaming?
- How should evidence carry over across model and system revisions?
- How should cost, latency, utility, and multiple harm types be incorporated into the same release policy?
- What minimum evidence is needed before missing-mass estimates become decision-relevant?

Feedback on these assumptions and their practical implementation is welcome.

## Citation

```bibtex
@misc{heimann2026stoppingrules,
  author = {Richard Heimann},
  title = {Stopping Rules for AI Deployment Evaluation: A Dual-Lane Rate-Bounded and Saturation-Aware Method},
  year = {2026},
  month = {April},
  note = {South Carolina Department of Administration}
}
```
