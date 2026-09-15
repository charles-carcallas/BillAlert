# Hypertension Exercise Technology: Startup Opportunity Assessment

The most defensible new direction is technology that helps patients perform a clinician-prescribed exercise intervention at home. This is a candidate for further development, not a validated business or a proven treatment product. The proposed lead concept, GalawRx, would help a provider deliver a structured home exercise service by recording completed activity, guiding selected movements, and surfacing sessions that require review.

The initial target is insufficiently active adults with diagnosed hypertension who have been assessed as suitable for home exercise by a clinician. A small private rehabilitation or multidisciplinary clinic is the proposed first customer. National prevalence establishes relevance; it does not establish that this segment will pay, that its needs are unmet, or that the proposed software will lower blood pressure.

This assessment assumes a three-person Philippine CS team developing a prototype with optional simple hardware. It evaluates three alternative interventions for the same problem: difficulty completing an appropriate, sustained exercise program alongside usual hypertension care. The alternatives require different levels of clinical and engineering support.

## Evidence and its limits

The Philippines has a substantial hypertension burden. WHO's 2025 country profile estimates 16.8 million adults aged 30–79 with hypertension, with 19% controlled. These are population estimates and must not be presented as a count of potential customers. The reasons for uncontrolled hypertension include multiple clinical, social, and service factors; inactivity is one possible contributor, not an explanation for all uncontrolled cases.[^1]

DOST-FNRI's 2024 annual report describes an analysis of the 2021 Expanded National Nutrition Survey in which 36.1% of adults were insufficiently physically active. Those data concern the pandemic period and all adults in the analysis, not specifically today's hypertensive patients. They support national relevance but cannot establish a current local purchasing opportunity.[^2]

The following studies support investigating exercise delivery while placing clear limits on claims:

| Evidence | Finding | What it permits us to conclude |
|---|---|---|
| EnRicH randomized trial, Portugal, published 2021 | A supervised aerobic exercise intervention added to usual care reduced 24-hour systolic BP by 7.1 mmHg relative to control after 12 weeks | Exercise can have a clinically meaningful effect in selected patients; an unsupervised student app cannot inherit the result |
| HERB-DH1 randomized trial, Japan, 390 participants, 2021 | A comprehensive digital lifestyle intervention achieved a 2.4 mmHg greater reduction in 24-hour systolic BP than standard lifestyle advice at 12 weeks | Software-supported treatment can be studied rigorously; the result is for the entire intervention, not exercise alone |
| AI-assisted telerehabilitation trial, China, 62 participants, 2026 | Reported improved exercise capacity and a secondary systolic BP benefit after eight weeks | A similar product category already exists; clinician contact and other intervention components prevent attributing the benefit to AI alone |
| ENLIGHTEN, two Manila barangays, 2021 publication | Diet and activity education was associated with a larger BP reduction than the comparison program | Philippine implementation is plausible, but allocation by two barangays and a combined intervention limit causal and product-specific conclusions |

Sources: EnRicH,[^3] HERB-DH1,[^4] telerehabilitation trial,[^5] ENLIGHTEN.[^6] These effects are from different populations and protocols; they should not be ranked as if they came from a head-to-head trial. None establishes reduced mortality for the proposed product.

## The shared problem for the assignment

Provisional statement: “Some insufficiently active adults with hypertension who are cleared for exercise struggle to complete their prescribed home program, while their providers have limited visibility into the activity actually performed and the difficulties encountered.”

This statement must be checked with patients and providers. An app is useful only if feedback, execution, or supervision is a material barrier. If the dominant obstacle is an unaffordable clinical assessment, unsuitable housing, physical disability requiring in-person care, or lack of interest in exercise, the software may not be the appropriate intervention.

The three solutions below are alternative approaches. They should not be combined into an oversized first product. None proposes stopping medication or substitutes for clinical assessment.

## Alternative 1: GalawRx — a prescribed home exercise service

GalawRx is the preferred software candidate. A clinician selects a plan and its permitted activities. The patient receives a guided session with instructions, timing, and limited feedback. The system records activity and reports uncertainty rather than treating an open app as proof of exercise. A provider reviews reported difficulties and adjusts the plan.

A practical prototype would support only two or three movements selected by the clinical partner. It could estimate repetitions, movement duration, or cadence using a phone camera or motion sensor, depending on the task. A therapist would compare those estimates against human observations. Camera processing should stay on the device where feasible; uploading raw home video should not be the default.

The system would show when an exercise could not be measured because the camera was obstructed, lighting was poor, or the movement was outside the validated range. It would collect perceived effort and symptoms using the provider's chosen workflow. Clinical rules for holding a session or referring a concern must come from the clinical partner. A phone camera cannot certify cardiovascular safety or reliably measure blood pressure.

The provider would see a compact review queue: completed sessions, uncertain measurements, reported difficulties, and cases awaiting plan review. A session report should distinguish sensor-observed activity from patient-reported activity. Heart rate, if included, does not replace assessment of symptoms or establish a universally safe exercise intensity.

The CS contribution is measurable: activity recognition, measurement confidence, operation on inexpensive phones, intermittent synchronization, and efficient provider review. AI is warranted only if recognition improves the chosen task relative to simpler sensors or rules. Program selection and progression need not use generative AI.

### Buyer and value proposition

The initial buyer would be a clinic already providing rehabilitation, exercise counseling, or a related paid service. Patients could pay the clinic for assessment and supervised follow-up; the clinic would pay the startup for software. A hypertension diagnosis does not automatically make someone eligible for a reimbursed cardiac rehabilitation program.

The proposed benefit is less manual review and more reliable information about home sessions. Providers must confirm that these benefits matter enough to pay for. Do not assume employers, HMOs, or PhilHealth will purchase or reimburse the service.

For an illustrative business experiment, test a fee of PHP150 per active patient-month. With 40 active patients, that generates PHP6,000 monthly revenue. If variable support and infrastructure cost PHP50 per active patient, contribution is PHP4,000 before development, clinical content, regulatory work, customer acquisition, tax, and fixed costs. All figures are assumptions, not market quotes or forecasts. Human supervision is a separate cost and cannot be treated as free.

### Differentiation and competition

Physitrack already sells exercise prescription, patient progress tracking, and telehealth capabilities to providers; its patient app is free to patients. CureApp HT is a prescription hypertension treatment-support application in Japan. The 2026 Chinese trial includes camera-based movement feedback and provider follow-up.[^5][^7][^8]

Consequently, “AI exercise coaching for hypertension” is not a new category. A defensible local proposition would need demonstrated advantages such as accurate measurement of a narrow exercise set on affordable phones, operation during poor connectivity, appropriate Filipino-language instructions, and materially lower provider review time. These are hypotheses requiring tests, not established unique features.

The decisive comparison is against the clinic's current method and an available platform such as Physitrack. If existing software does the job adequately at an acceptable price, a new platform has little reason to exist.

## Alternative 2: GripGuide — measured handgrip training

GripGuide would combine a force-sensing handgrip with software that guides a professionally selected exercise protocol. Its screen could show whether the measured effort falls within a target band and record force stability, duration, rests, and interruptions. The student demonstration would focus on force measurement and reliable feedback.

The potential advantage over an ordinary gripper is knowing the actual force-time pattern. However, that advantage must matter in practice: a more expensive sensor is not automatically better value than simple equipment and instruction.

Handgrip evidence is mixed. A 2018 randomized trial found improvement in office BP with supervised training but not the home training arm, and no significant ambulatory BP effect. A more recent small Thai study reported favorable office BP results with inexpensive fixed-resistance equipment, but acknowledged small-sample and measurement limitations.[^9][^10] These findings argue for testing the additional value of guidance; they do not prove that a smart grip solves hypertension.

Zona Plus already measures grip strength, guides effort with visual and audio feedback, and stores session performance. Its website listed a US price of USD599.99 when checked for this report. That is an advertised foreign price, not a landed Philippine price or proof of Filipino willingness to pay.[^11]

The proposed customer is a rehabilitation clinic lending equipment to assessed patients, or a patient buying a clinically supported package. Revenue could come from a device sale, rental, and service. Differentiation must involve verified affordability, maintainability, or clinical workflow rather than claiming to invent guided grip exercise. Hardware cost, force accuracy, durability, hygiene, product rights, and clinical validation make this harder than GalawRx.

## Alternative 3: HingaFit — inspiratory resistance training support

HingaFit would guide and record a professionally selected inspiratory muscle training program using a suitable resistance device. This means breathing against a measured resistance; it is different from an animation that simply encourages slow breathing.

A 2021 sham-controlled pilot studied 36 adults aged 50–79 with above-normal systolic BP over six weeks and reported favorable results from high-resistance inspiratory muscle training. The sample was small and the intervention specific.[^12] It cannot establish that generic breathing exercises, arbitrary resistance settings, or a homemade device produce the same effect.

The CS contribution could be measuring accepted breaths against the required pressure profile, identifying incomplete attempts, recording session quality, and supporting provider review. A product would require appropriate sensing, calibration, and clinical selection. The initial prototype should use a simulated pressure stream or an appropriate existing device rather than a patient treatment experiment.

POWERbreathe already manufactures inspiratory training equipment and discusses blood-pressure research.[^13] A new venture would need to demonstrate a meaningful improvement in delivered cost, measured session quality, or provider usability. Clinical partners would also need to determine eligible patients and the appropriate intended use.

This is the most technically demanding option and has the least established local commercial case. It should be presented as an exploratory research concept, not the default recommendation for a CS team.

## Comparative screening

Scores below use the original five criteria, each out of ten. They are ordinal research judgments, not measured probabilities or clinical-effect scores. High scores for the disease's importance do not compensate for weak commercial evidence.

| Criterion | GalawRx | GripGuide | HingaFit |
|---|---:|---:|---:|
| Specific problem evidence | 7 | 6 | 5 |
| Pain and relevance | 8 | 8 | 7 |
| Technology fit | 8 | 9 | 8 |
| Target-user clarity | 8 | 8 | 7 |
| Business model evidence | 5 | 4 | 4 |
| Total /50 | 36 | 35 | 31 |

GalawRx has the best balance of clinical rationale and student feasibility. GripGuide offers a tangible demonstration but faces an established near-direct competitor. HingaFit needs more medical-device expertise and local demand evidence. None currently merits a “validated startup” label.

## Prototype, validation, and decision gates

For GalawRx, a reviewable first prototype comprises a clinician plan screen, a guided patient session, activity measurement with confidence reporting, an interruption workflow, and a concise provider summary. Show the complete sequence using synthetic records. Avoid coding a comprehensive medical record system.

The first technical question is whether the activity measurements are sufficiently accurate for the chosen use. Test against human annotation across the intended movements, phone positions, lighting conditions, and participant range. Report missed and falsely detected activity, not only average accuracy. Establish requirements with the clinical partner before testing.

The next question is whether it reduces work. Compare provider time and information quality when reviewing ordinary diaries versus the prototype's summaries. A dashboard that generates more alerts and review work than it removes is a failure even if users enjoy the interface.

Interview at least two relevant providers and several potential patients. Ask providers to show their current home-exercise workflow, how much time it takes, their existing software, and whether they charge for ongoing care. Ask patients what happened during their last prescribed home program, which barriers stopped them, and what they already pay for. Avoid hypothetical questions such as “Would you like an AI health app?”

A pilot purchase or concrete budget discussion is stronger evidence than compliments. Do not collect payment for an unapproved treatment claim. Clinical outcome research requires appropriate supervision, ethics review, and an agreed protocol. Record changes in medication and other treatment because BP improvement cannot automatically be attributed to the app.

The Philippine FDA has published a draft specifically addressing medical-device software, while Administrative Order 2018-0002 provides an existing regulatory foundation.[^14] The draft must not be represented as final law. Determine applicable requirements from the proposed intended use before deployment; this report does not establish a product classification or approval pathway.

Continue only if a provider identifies a real gap, the prototype improves the selected task over the current method, patients can use it, and the buyer can explain why it is worth paying for. If it is only an exercise video library with reminders, or if existing tools are adequate, stop or change the concept. The clinical promise of exercise cannot rescue an unnecessary product.

## Presentation-ready concept

Problem: Suitable adults with hypertension struggle to complete prescribed exercise at home, and providers have limited visibility into execution.

Solution: GalawRx guides selected clinician-prescribed activities, records measurable completion and uncertainty, and organizes cases requiring review.

Feature differentiation: Demonstrated operation on the target phones and connectivity conditions, measurement of a narrow validated movement set, and reduced provider review time compared with existing methods.

Business model: A provider pays for software used within a paid clinical service. Patient demand, provider economics, and applicable approvals remain to be established.

The group's three alternative proposals are guided whole-body exercise, measured handgrip training, and inspiratory resistance training support. Each addresses execution of a physical intervention for selected people with hypertension. They represent separate concepts to compare, with GalawRx the recommended first investigation.

## Sources

[^1]: WHO. *Global report on hypertension 2025: country profiles*, Philippines profile, 2025. https://cdn.who.int/media/docs/default-source/country-profiles/hypertension/hypertension_country_profiles_2025.pdf?sfvrsn=30246b6e_1
[^2]: DOST-FNRI. *Annual Report 2024*, “Sitting Too Long may be Stealing Your Sleep,” p. 102; analysis of 2021 ENNS. https://fnri.dost.gov.ph/images/sources/AnnualReports/AR2024.pdf
[^3]: Lopes et al. *Effect of Exercise Training on Ambulatory Blood Pressure Among Patients With Resistant Hypertension: A Randomized Clinical Trial*, 2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC8340008/
[^4]: Kario et al. *Efficacy of a digital therapeutics system in the management of essential hypertension: the HERB-DH1 pivotal trial*, 2021. https://pmc.ncbi.nlm.nih.gov/articles/8530534/
[^5]: Yao et al. *Effects of Artificial Intelligence Recognition–Based Telerehabilitation on Exercise Capacity in Patients With Hypertension: Randomized Controlled Trial*, January 13, 2026. https://www.jmir.org/2026/1/e81400/
[^6]: *The EffectiveNess of LIfestyle with Diet and Physical Activity Education ProGram Among Prehypertensives and Stage 1 HyperTENsives in an Urban Community Setting (ENLIGHTEN) Study*, 2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC8061291/
[^7]: Physitrack. *How much does Physitrack cost my patients?*, updated September 2, 2025. https://support.physitrack.com/article/160-how-much-does-physitrack-cost-my-patients ; product pricing varies by geography: https://support.physitrack.com/article/159-how-much-does-physitrack-cost
[^8]: CureApp. *CureApp HT product information*, checked September 12, 2026. Japanese product claims and authorization do not establish Philippine authorization. https://cureapp.co.jp/productsite/ht/
[^9]: *Supervised, but Not Home-Based, Isometric Training Improves Brachial and Central Blood Pressure in Medicated Hypertensive Patients: A Randomized Controlled Trial*, 2018. https://pmc.ncbi.nlm.nih.gov/articles/PMC6065303/
[^10]: *Effect of home-based isometric handgrip exercise with a commercially available device on blood pressure in older adults with hypertension: A randomized controlled trial*, article available in 2026; study conducted in 2020–2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC12959700/
[^11]: Zona. *The Zona Plus*, product features and advertised US price checked September 12, 2026. https://www.zona.com/pages/the-zona-plus
[^12]: Craighead et al. *Time-Efficient Inspiratory Muscle Strength Training Lowers Blood Pressure and Improves Endothelial Function, NO Bioavailability, and Oxidative Stress in Midlife/Older Adults With Above-Normal Blood Pressure*, 2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC8403283/ ; authors' subsequent discussion of the trial: https://pmc.ncbi.nlm.nih.gov/articles/PMC9150656/
[^13]: POWERbreathe. *Health*, manufacturer product information checked September 12, 2026; used to establish competition, not independent proof of efficacy. https://www.powerbreathe.com/us/health/
[^14]: Philippine FDA. *Draft for Comments: Guidelines on the Regulation of Medical Device Software*, 2025. https://www.fda.gov.ph/draft-for-comments-guidelines-on-the-regulation-of-medical-device-software-mdsw-by-the-food-and-drug-administration-fda/ ; *Administrative Order No. 2018-0002*: https://www.fda.gov.ph/wp-content/uploads/2021/05/Administrative-Order-No.-2018-002.pdf
