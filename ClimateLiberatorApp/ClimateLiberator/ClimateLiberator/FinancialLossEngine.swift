import Foundation

struct FinancialLossLayer: Hashable {
    let gul: Double
    let il: Double
    let ri: Double
}

enum FinancialLossEngine {
    static func computeLoss(tiv: Double,
                            burnProbability: Double,
                            vulnerabilityRatio: Double,
                            deductiblePct: Double,
                            limitPct: Double) -> FinancialLossLayer {
        let boundedTIV = max(tiv, 0)
        let boundedBurnProbability = clampUnit(burnProbability)
        let boundedVulnerability = clampUnit(vulnerabilityRatio)
        let boundedDeductible = clampUnit(deductiblePct)
        let boundedLimit = clampUnit(limitPct)

        let gul = boundedTIV * boundedBurnProbability * boundedVulnerability
        let deductibleAmount = boundedTIV * boundedDeductible
        let postDeductible = max(0, gul - deductibleAmount)
        let il = min(postDeductible, boundedTIV * boundedLimit)

        return FinancialLossLayer(gul: gul, il: il, ri: 0)
    }

    static func normalizePercentInput(_ rawValue: Double?) -> Double? {
        guard let rawValue else { return nil }
        if rawValue > 1 {
            return clampUnit(rawValue / 100.0)
        }
        return clampUnit(rawValue)
    }

    private static func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
