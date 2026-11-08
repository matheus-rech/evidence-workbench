import Foundation

public enum CoreFields {
    // App-specific extraction defaults informed by PRISMA 2020 items 9–13, 17–20
    // and Cochrane Handbook chapter 5. These are not an official checklist or certification.
    private static let legacyDefaults: [VariableDefinition] = {
        let specs: [(String, String, String, FieldType, FieldScope, String)] = [
            ("title", "Article title", "Full title exactly as reported.", .text, .study, ""),
            ("authors", "Authors", "Author list and corresponding author, if reported.", .text, .study, ""),
            ("year", "Publication year", "Year of this report, not recruitment year.", .integer, .study, "year"),
            ("journal", "Journal", "Journal name as reported.", .text, .study, ""),
            ("doi", "DOI / report identifier", "DOI, PMID, or other report identifier. Do not fabricate.", .text, .study, ""),
            ("registration", "Study registration", "Trial/register identifiers to help link multiple reports of the same study.", .text, .study, ""),
            ("design", "Study design", "Design and allocation methods; distinguish randomized, observational, diagnostic, qualitative and other designs.", .text, .study, ""),
            ("setting", "Country and setting", "Countries, number/type of centers, care setting and recruitment dates.", .text, .study, ""),
            ("population", "Population and eligibility", "Population, condition, diagnostic criteria and inclusion/exclusion criteria.", .text, .population, ""),
            ("intervention", "Intervention / exposure", "Interventions, exposures or index tests, dose, duration and co-interventions. Preserve each arm.", .text, .arm, ""),
            ("comparator", "Comparator / reference", "Comparator, control, reference standard or explicitly not applicable.", .text, .comparison, ""),
            ("outcome_definition", "Outcome definition", "Outcome domain, exact operational definition, instrument, scale direction and ascertainment.", .text, .outcome, ""),
            ("timing", "Follow-up and assessment timing", "Follow-up duration and each reported assessment time point; retain units.", .text, .outcome, ""),
            ("n", "Sample size", "Number recruited/randomized and analyzed per arm, time point and analysis; use separate observations.", .integer, .arm, "participants"),
            ("age_mean", "Age — mean", "Reported arithmetic mean only. Never copy a median or calculate a conversion without a separate justified derivation.", .number, .population, "years"),
            ("age_sd", "Age — SD", "Standard deviation of age; do not confuse with SE, IQR or range.", .number, .population, "years"),
            ("age_median", "Age — median", "Reported median age only; preserve group labels.", .number, .population, "years"),
            ("age_spread", "Age — IQR / range", "Specify whether the reported spread is IQR or range, and its units.", .text, .population, ""),
            ("sex_gender", "Sex and gender", "Categories, counts, denominators and percentages as reported; do not conflate sex and gender.", .text, .population, ""),
            ("baseline", "Baseline characteristics", "Relevant disease severity, comorbidities, socioeconomic and other demographics, preserving arms and units.", .text, .population, ""),
            ("events", "Outcome event count", "Number with the defined binary outcome, matched to arm, denominator and time point. Zero only when explicitly reported.", .integer, .outcome, "events"),
            ("outcome_mean", "Outcome — mean", "Reported outcome mean on the named instrument, with arm and time point. Keep change scores separate from final values.", .number, .outcome, "as reported"),
            ("outcome_sd", "Outcome — SD", "Reported outcome SD, matched to its mean, sample, scale and time point. Do not substitute SE.", .number, .outcome, "as reported"),
            ("effect_measure", "Effect measure", "RR, OR, HR, risk difference, mean difference, standardized mean difference, prevalence, diagnostic accuracy or other reported measure.", .text, .comparison, ""),
            ("effect_estimate", "Effect estimate", "Point estimate with comparison, outcome, time point and analysis context. Preserve adjusted/unadjusted status.", .number, .comparison, "as reported"),
            ("ci_lower", "Confidence interval — lower", "Lower bound matched to the estimate and its interval level; retain interval level in analysis context.", .number, .comparison, "as reported"),
            ("ci_upper", "Confidence interval — upper", "Upper bound matched to the estimate and its interval level.", .number, .comparison, "as reported"),
            ("precision", "Other precision / uncertainty", "SE, variance, credible intervals, p-values and confidence level, clearly labeled. Do not convert implicitly.", .text, .comparison, ""),
            ("analysis", "Analysis methods and confounding", "Analysis population, adjustment variables, missing-data methods, cluster/crossover design and effect modifiers.", .text, .study, ""),
            ("attrition", "Attrition and missing outcomes", "Withdrawals, losses to follow-up and missing outcomes with reasons, denominators and time points.", .text, .arm, ""),
            ("harms", "Adverse events / harms", "Harms, definitions, counts and denominators per arm and time point.", .text, .outcome, ""),
            ("rob_evidence", "Risk-of-bias supporting evidence", "Reported methods relevant to the prespecified tool. Extract evidence, not an automatic final risk-of-bias judgment.", .text, .riskOfBias, ""),
            ("funding", "Funding", "Reported funders and their roles.", .text, .study, ""),
            ("conflicts", "Conflicts of interest", "Author disclosures and sponsor involvement as reported.", .text, .study, ""),
            ("qualitative", "Qualitative / other findings", "For non-numeric research, extract themes, findings and supporting quotations; otherwise mark not applicable.", .text, .outcome, "")
        ]
        return specs.map { VariableDefinition(id: $0.0, label: $0.1, definition: $0.2, type: $0.3, scope: $0.4, unit: $0.5, core: true) }
    }()
    public static let supplementalResults: [VariableDefinition] = [
        .init(id: "outcome_proportion", label: "Outcome — proportion / percentage", definition: "Directly reported outcome proportion or percentage for each arm and time point. Preserve the printed scale (fraction or percent) in analysis context. Never derive counts or differences.", type: .number, scope: .outcome, unit: "as reported", core: true),
        .init(id: "outcome_rate", label: "Outcome — rate", definition: "Directly reported outcome incidence/event rate, with its original denominator unit (e.g. per 1,000 participants or person-years) in analysis context. Never treat a rate as an event count.", type: .number, scope: .outcome, unit: "as reported", core: true)
    ]
    public static let defaults = legacyDefaults + supplementalResults
    // Older approved plans remain valid; adding the new fields requires a documented amendment.
    public static let requiredIDs = Set(legacyDefaults.map(\.id))
}
