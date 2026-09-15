# AI Opportunities in Difficult-to-Control Hypertension

## Assessment

The most defensible new candidate for a Philippine student startup is an AI-assisted clinical record review system focused on missed primary aldosteronism (PA), a hormonal cause of hypertension. Its working name is UgatBP. It would assemble evidence from fragmented records, identify gaps in a clinician-approved evaluation pathway, and prepare a source-linked case for physician review. It would not diagnose PA, prescribe treatment, or replace laboratory testing.

This is a conditional recommendation, not a validated startup opportunity. The clinical problem is credible, and there is Philippine evidence that it occurs. However, AI-based PA detection already exists in research, ordinary electronic prompts compete with it, and test affordability may be a larger local obstacle than record review. A team should commit only after obtaining a clinical partner who confirms that the proposed task is both burdensome and worth paying to improve.

Two other AI directions merit comparison: sleep-apnea signal analysis for selected hypertensive patients, and clinician-facing prediction of response to antihypertensive medicines. Both have a plausible relationship to blood-pressure management. Both also face existing competition, substantial validation requirements, and a difficult route from a student demonstration to a clinical product.

This assessment concerns evidence available through 12 September 2026. Proposed features, prices, scores, and development plans are analytical judgments, not findings from clinical studies.

## The clinical problem

Primary aldosteronism involves excessive production of aldosterone by the adrenal glands. It is an underdiagnosed cause of hypertension for which cause-specific treatment exists. The 2025 Endocrine Society guideline conditionally suggests screening all people with hypertension, taking account of resources and local capacity; this is not an instruction to use AI to decide who is allowed to be tested. Screening uses aldosterone and renin measurements, with potassium helping interpretation. A model cannot substitute for these measurements.[^1]

International estimates cited by the Endocrine Society put PA at 5–14% among hypertensive patients in primary care and higher in referral settings. These are not Philippine national prevalence estimates. They establish why this is more than an obscure curiosity, but should not be multiplied by the Philippine hypertensive population to manufacture a customer count.[^2]

A Philippine pilot published in 2021 studied patients with resistant hypertension at Capitol University Medical Center in Cagayan de Oro. Fourteen participated and three met the study's PA confirmation criteria. The sample was small, selected, and from one institution; its 21.43% result must not be presented as a national rate. Diagnostic costs contributed to recruitment difficulties, and one participant declined further testing for financial reasons.[^3]

The local opportunity is therefore narrower than “AI solves hypertension.” A provisional problem statement is: “In clinics managing difficult-to-control hypertension, information needed to review possible secondary causes can be scattered across prescriptions, laboratory reports, and consultation notes; some patients do not complete the resulting evaluation.” The frequency, review time, and reasons for noncompletion need direct measurement in the intended clinic.

The distinction between difficult-to-control and confirmed resistant hypertension matters. Incomplete information about medicine use, measurement quality, and out-of-office BP should remain explicit uncertainty. A prototype must not turn an incomplete prescription list into a confident clinical classification.

## Candidate 1: UgatBP

### Product and workflow

UgatBP is a record-to-review assistant for an internal-medicine clinic or hospital outpatient department. Staff would upload permitted documents or import records from an approved system. AI would extract dated BP readings, medication mentions, laboratory values and units, and relevant history. The clinician would receive a timeline with each extracted item linked to its original location.

The product would distinguish a current medicine from a historical prescription, a documented negative result from an absent record, and an actual laboratory measurement from a value mentioned in free text. Conflicting dates or uncertain readings would be presented for correction rather than silently resolved. A missing test in the uploaded material would be labelled “not found in supplied records,” not “never performed.”

A separate, clinician-maintained rules layer would organize the review pathway. For example, it could show that a case has repeated elevated BP records and no documented PA screening in the supplied material. It would not tell a patient to stop medicines before a test or independently decide which investigation to order. The physician would retain those decisions.

After physician approval, the system could prepare a review packet and record whether the ordered evaluation was completed, deferred, declined, or unaffordable. This workflow is important, but it is ordinary software rather than the AI contribution. The product should not disguise a referral tracker as a novel diagnostic model.

### Why AI is relevant

The strongest student-feasible AI component is evidence extraction from varied, imperfect documents. If all fields are already reliably structured, a straightforward database query and checklist may be sufficient. In that setting, AI should be removed unless it demonstrates an additional benefit.

A disease-risk prediction model is a possible later component, not a prerequisite for the first prototype. Researchers have already investigated routine-record-based models: a June 2026 ENDO presentation described a Mayo Clinic model using longitudinal clinical variables. This is evidence that the technical category is plausible and already occupied, not proof of accuracy in Philippine patients or of improved outcomes after deployment.[^4]

The first prototype should therefore make a modest claim: “AI-assisted evidence preparation for clinician review.” It should not display an invented “87% probability of hormonal hypertension.” A calibrated disease probability would require suitable labelled data and external validation that a small synthetic dataset cannot provide.

### Concrete demonstration

A fictional demonstration could contain several visits, an old prescription, a newer prescription, and laboratory reports with different layouts. The AI assembles a dated history and highlights the source of every fact. It flags the uncertain status of a medicine and the absence of a screening result in the submitted documents. The doctor corrects one extracted item and approves a review packet.

This demonstrates an actual computational task rather than a chatbot conversation. It does not demonstrate diagnosis, clinical effectiveness, or safety on real patients. Those claims require separate studies.

### Differentiation and competition

The novelty cannot be “AI detects PA.” A randomized study across 153 primary-care clinics evaluated decision support with and without a predictive model. Among the highest-risk group, ARR orders occurred in 19 of 2,896 patients in model clinics versus none of 1,210 in comparison clinics. The absolute uptake remained low. A statistically significant change in ordering does not establish that a predictive alert is a strong commercial product or improves BP.[^5]

Non-AI alternatives are particularly important. The September 2026 CONSEP protocol describes evaluation of commercially available, guideline-based electronic decision support integrated into pathology ordering. It is a protocol, not completed outcome evidence. Nevertheless, it establishes that ordinary ordering support is an existing alternative, not an imaginary baseline.[^6]

The proposed differentiation is handling the documents actually encountered in a partner clinic, making extraction auditable, and reducing total review work without increasing clinically important omissions. None of those advantages is established yet. If a checklist produces the same result in comparable time, the proposed AI product has failed its differentiation test.

### Customer and revenue

The initial buyer would be a clinic owner or hospital department responsible for a substantial hypertension caseload and its operating budget. The daily users would be authorized clinical staff. Patients would benefit from a better-organized review process but would not be asked to pay for an unvalidated AI diagnosis.

A possible model is a monthly clinic subscription, with document-processing limits and a separate onboarding fee if integration is necessary. An illustrative interview anchor is PHP3,000 per clinic per month, not a researched market price. At 200 reviewed cases per month, this equals PHP15 per case before accounting for onboarding, support, infrastructure, compliance, and development.

The buyer argument must be measurable: does the clinic save enough staff time or avoid enough duplicated review work to justify the fee? The break-even calculation is monthly case volume multiplied by verified minutes saved per case, divided by 60, then multiplied by the clinic's own value per staff hour. Clinical benefits should be assessed separately, not invented to make that arithmetic attractive.

Do not make commissions for additional tests the core incentive. A model should not be financially rewarded for generating unnecessary investigations. Do not assume PhilHealth coverage, reimbursement, hospital procurement approval, or a supplier partnership without verification.

### Principal weakness

This product does not pay for laboratory tests or create access to specialist care. If cost is the main local barrier, better case identification may not change treatment. The appropriate response is to reject or rescope the product, not to claim that more alerts solve access. A clinic with fragmented records but a workable testing pathway is a more plausible first partner than an institution where the pathway is unavailable.

## Candidate 2: SleepCause AI

SleepCause AI would help a sleep clinic identify possible sleep-disordered breathing in selected patients with difficult-to-control hypertension. It would analyze properly acquired overnight signals and produce a quality-checked report for professional review. Its intended contribution would be signal interpretation, not another sleep-hygiene chatbot.

There is a treatment connection, but it must be stated accurately. In the HIPARCO randomized trial, CPAP treatment in patients with obstructive sleep apnea and resistant hypertension improved 24-hour mean BP by 3.1 mmHg relative to control after 12 weeks. The between-group difference in 24-hour systolic BP was not statistically significant in the intention-to-treat analysis. This is evidence about CPAP in a selected population, not proof that screening software lowers BP.[^7]

The category is already competitive. The US FDA's Samsung Sleep Apnea Feature decision describes a wrist-sensor-based assessment using photoplethysmography and movement signals. Its authorization does not authorize a student product or prove Philippine availability, but it does rule out claiming that AI sleep-apnea screening is new.[^8]

The potential buyer is a sleep center seeking a validated improvement in assessment or review throughput. A per-report software fee is conceivable, but willingness to pay and clinical accuracy remain unknown. The patient must still have access to appropriate confirmatory evaluation and treatment.

An overnight snoring recording alone should not be presented as a diagnosis. A student team would need appropriate labelled recordings, reference sleep-study results, acquisition quality controls, and a clinical partner. This candidate is more signal-processing intensive than UgatBP and less suitable without access to a sleep laboratory.

## Candidate 3: ResponseRx AI

ResponseRx AI would support a clinician reviewing how a patient has responded to medication over time. The ambitious version predicts response to candidate treatment regimens. The safer demonstration version organizes observed responses and uncertainties without recommending an individualized drug or dose.

This direction has the closest relationship to treatment decisions, but also the highest stakes. A registered Chinese trial, NCT06828692, evaluates guideline-plus-machine-learning decision support, with an additional hemodynamic-data arm. The retrieved registry entry describes a planned 2,160 participants and was last updated in February 2026. Its anticipated completion dates are not outcome results and should not be treated as evidence of benefit.[^9]

Historical prescribing data are not automatically suitable training labels. Learning what clinicians prescribed is not the same as learning which treatment would have worked best. Patients receiving different drugs may differ in many other ways, creating confounding. A model must also respect missing information and clinician-defined safety constraints.

A hospital or specialist service is a conceivable buyer, but a three-person team cannot establish efficacy through a classroom demonstration. The expected needs for longitudinal data, clinical supervision, prospective evaluation, and regulatory review make this the weakest near-term student startup candidate despite its compelling headline.

## Framework scores

Scores are provisional judgments out of five, equally weighted. Five means strong evidence or fit; three means plausible but substantially unvalidated; one means weak fit. These scores evaluate the proposed product, not the seriousness of hypertension itself. Differences of one point should not be interpreted as precise measurements.

| Criterion | UgatBP | SleepCause AI | ResponseRx AI |
|---|---:|---:|---:|
| Specific, evidenced problem | 4 | 4 | 4 |
| Pain and consequences | 5 | 4 | 5 |
| AI/technology fit for a student prototype | 4 | 3 | 2 |
| Defined target user | 4 | 4 | 4 |
| Business-model evidence | 2 | 2 | 2 |
| Total | 19/25 | 17/25 | 17/25 |

UgatBP leads because a useful evidence-extraction prototype can be evaluated without pretending to invent a treatment. All three receive low business scores because no local buyer has been interviewed and no willingness to pay has been demonstrated. ResponseRx's potential clinical importance does not compensate for its feasibility and safety constraints.

## Fit with the three-member assignment

These are alternative proposals under the broad problem of difficult-to-control hypertension. They are not three solutions to the identical narrow bottleneck: UgatBP concerns missed hormonal-cause evaluation, SleepCause concerns a sleep-related contributor, and ResponseRx concerns treatment-response decisions.

If the instructor requires one tightly defined problem, obtain agreement on that problem before dividing work. For example, selecting “incomplete evaluation for hormonal hypertension” would require three alternative approaches to that same evaluation gap, rather than submitting sleep screening and medicine selection under a shared disease label. Three modules of UgatBP would also not automatically count as three different solutions.

## Validation and decision gates

First, interview an internist or endocrinologist and the staff member who prepares records. Ask them to describe recent difficult reviews, what they already use, what information is missing, and where patients drop out. Do not begin by asking whether they like AI. Measure the task before proposing time savings.

Second, obtain only appropriately authorized, de-identified examples for development, or use clearly labelled fictional records. Compare manual review, a structured checklist, and AI-assisted review on the same task. Measure field extraction errors, source-link correctness, clinically relevant omissions, correction time, and total review time. A polished summary with incorrect units is a failed result.

Third, test difficult cases deliberately: historical versus current medicines, duplicate reports, unreadable scans, contradictory notes, missing screening results, and records belonging to different patients. The system should abstain or ask for correction when evidence is insufficient. Never use a random split of near-duplicate documents to claim generalization.

Fourth, discuss pricing with the actual budget holder. Interest from a physician is not a purchase commitment. A small, properly scoped paid evaluation is stronger evidence than a hypothetical market-size slide. Include onboarding work and support in the cost calculation.

Finally, separate technical validation from clinical deployment. Any use influencing care requires appropriate clinical governance, privacy protections, and determination of applicable regulatory requirements. The Philippine FDA software guidance located during this assessment is explicitly a 2025 draft for comments; it is not cited as a final binding rule. Calling a product “advisory” does not by itself establish regulatory exemption.[^10]

Proceed with UgatBP only if a clinical partner confirms the review burden, the AI beats simpler alternatives, and flagged patients have a realistic evaluation pathway. If those conditions fail, the honest result is that this hypertension concept should not proceed—not that adding a more sophisticated model will repair its business case.

## Sources

[^1]: Endocrine Society. “Primary Aldosteronism: An Endocrine Society Clinical Practice Guideline.” 14 July 2025. https://www.endocrine.org/clinical-practice-guidelines/primary-aldosteronism-2

[^2]: Endocrine Society. “Endocrine Society guideline calls for increased screening for common cause of high blood pressure.” 14 July 2025. https://www.endocrine.org/news-and-advocacy/news-room/2025/endocrine-society-guideline-calls-for-increased-screening-for-common-cause-of-high-blood-pressure

[^3]: Luardo-Taruc ACN, Echavez ASR, Obrero TMP, Lim ASAL. “Primary Aldosteronism among Adult Filipinos with Resistant Hypertension: A Pilot Study.” Philippine Journal of Internal Medicine 59(3), July–September 2021, pp. 214–217. https://pjim.pcp.org.ph/elib/journal/identifier/2021-59.3-4/pdf

[^4]: Endocrine Society. “AI model identifies patients at risk of underdiagnosed cause of high blood pressure.” 13 June 2026. Conference-research announcement, not a completed implementation trial. https://www.endocrine.org/news-and-advocacy/news-room/2026/lee-press-release-endo-2026

[^5]: “The impact of a primary aldosteronism predictive model in secondary hypertension decision support.” 2024. Indexed article abstract; full PMC page was not accessible during verification. https://pmc.ncbi.nlm.nih.gov/articles/PMC11519043/

[^6]: Russell G, Jia L, et al. “Using electronic clinical decision support in primary care to enhance identification of primary aldosteronism: a protocol for the CONSEP cluster-randomised controlled trial.” Journal of Human Hypertension, 4 September 2026. https://www.nature.com/articles/s41371-026-01207-9

[^7]: Martínez-García MA, et al. “Effect of CPAP on Blood Pressure in Patients With Obstructive Sleep Apnea and Resistant Hypertension: The HIPARCO Randomized Clinical Trial.” JAMA, 2013. https://jamanetwork.com/journals/jama/fullarticle/1788459

[^8]: US Food and Drug Administration. “De Novo Classification Request for Sleep Apnea Feature.” DEN230041, 2024. https://www.accessdata.fda.gov/cdrh_docs/reviews/DEN230041.pdf

[^9]: China National Center for Cardiovascular Diseases. ClinicalTrials.gov NCT06828692, “Implementation of Machine Learning and Hemodynamic Profiles Based Clinical Decision Support Systems for Personalized Guideline Accordant Antihypertensive Regimens in Primary Care: a Pragmatic Cluster Randomized Controlled Trial.” Record last updated 12 February 2026. https://clinicaltrials.gov/study/NCT06828692

[^10]: Philippine Food and Drug Administration. “Draft for Comments: Guidelines on the Regulation of Medical Device Software (MDSW) by the Food and Drug Administration (FDA).” 2025; comment deadline 20 July 2025. Draft status explicitly retained. https://www.fda.gov.ph/draft-for-comments-guidelines-on-the-regulation-of-medical-device-software-mdsw-by-the-food-and-drug-administration-fda/
