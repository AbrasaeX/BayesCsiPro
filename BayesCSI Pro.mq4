//+------------------------------------------------------------------+
//| Weighted CSI (Multiple Timeframes with Base & Quote) pair normalized |
//| Kurtosis, Skewness, and Limited Generative WITH INPUT & COMMENTS |
//+------------------------------------------------------------------+
#property copyright "2023 cognitionocturna"
#property version   "1.2"
#property indicator_separate_window FALSE
#property indicator_buffers 1

// Email Alert Settings
input bool   EnableEmailAlerts = true;    // Enable email alerts
input int    AlertMinutes = 5;            // Minutes between alerts
datetime LastTrendAlertTime = 0;          // Track last alert time
datetime LastMeanRevAlertTime = 0;        // Track last mean reversion alert time

// Validation Settings
input bool   EnableValidation = true;     // Enable historical validation
input int    ValidationLookback = 1000;   // Bars to look back for validation
input int    MinSignalsForValidity = 30;  // Minimum signals needed for probability
input double SignalQualityThreshold = 0.6; // Minimum signal quality score (0-1)

// Market Regime Settings
input int    RegimeAtrPeriod = 14;       // ATR period for regime detection
input int    RegimeAdxPeriod = 14;       // ADX period for regime detection
input int    RegimeVolPeriod = 20;       // Volatility period for regime detection

// Input for selecting the base currency
input string BaseCurrency = "EUR";        // Default base currency is EUR
string chartCurrency = StringSubstr(Symbol(), 3, 3); // This extracts the quote currency

// Arrays and Buffers
double csiBuffer[];
double weights[];            // Array for weights
string pairs[];             // Array to store currency pairs

// Currency Arrays
string validCurrencies[] = {"USD", "EUR", "GBP", "AUD", "CAD", "CHF", "JPY", "NZD"};
string currencies[8] = {"USD", "EUR", "GBP", "AUD", "CAD", "CHF", "JPY", "NZD"};
double overallCSI[8];
double originalCSI[8];       // Array to hold original CSI values
double kurtosisHistory[8];
double skewnessHistory[8];

// State tracking variables
static string prevStrongestCurrency = "";
static string prevWeakestCurrency = "";
static string timeStrongest = "";
static string timeWeakest = "";

// Sample size and period settings
input int sampleSize = 10;
input int LOOKBACK_PERIOD = 20;  // Added for mean reversion calculations

// Add this with your other input variables
input bool   UseGeometricTimeframes = false; // Use geometric timeframe progression
input double MinTimeframeProbability = 0.7;  // Minimum probability for timeframe significance
input double MaxTimeframeUncertainty = 0.3;  // Maximum timeframe uncertainty allowed

// Dynamic Timeframe Settings
input int    MinTimeframe = 1;            // Minimum timeframe to analyze (minutes)
input int    MaxTimeframe = 10080;        // Maximum timeframe to analyze (minutes)
input int    MaxTimeframeCount = 8;       // Maximum number of timeframes to use
input bool   UseStandardTimeframes = true; // Use standard timeframe set

// Timeframe Analysis Structure
struct TimeframeAnalysis {
    int timeframe;              // Timeframe in minutes
    double probability;         // Probability of significance
    double uncertainty;         // Measure of uncertainty
    double strength;           // Overall strength score
    bool isSignificant;        // Whether timeframe is significant
};

// Arrays for timeframe analysis
TimeframeAnalysis timeframeResults[];     // Store timeframe analysis results
double timeframeWeights[];                // Dynamic weights for timeframes

// Thresholds for mean reversion
input double BASE_PROB_THRESHOLD = 0.1;
input double BASE_KURTOSIS_THRESHOLD = 0.5;
input double BASE_SKEWNESS_THRESHOLD = 0.5;

// Structure for Market Regime Detection
struct MarketRegime {
    string symbol;            // Symbol of the market regime
    int timeframe;            // Timeframe of the market regime
    double atr;               // Average True Range
    double adx;               // Trend strength
    double volatility;        // Price volatility
    double correlation;       // Inter-pair correlation
    datetime period;          // Time of regime
    string condition;         // Regime description
};


// Structure for Signal Quality Assessment
struct SignalQuality {
    double probabilityScore;  // From Bayesian analysis
    double regimeScore;       // Based on market conditions
    double strengthScore;     // Signal strength
    double totalScore;        // Combined quality score
    double confidence;        // Confidence level
};

// Enhanced Historical Signal Structure
struct HistoricalSignal {
    datetime time;
    string type;              // "TREND" or "MEANREV"
    string pair;
    string direction;         // "BUY" or "SELL"
    double entryPrice;
    double exitPrice;
    MarketRegime regime;      // Market conditions at signal
    SignalQuality quality;    // Signal quality metrics
    bool wasSuccessful;
    double profit;            // In pips
    int barsToComplete;       // Bars until target/stop
    double settings[];        // Indicator settings at signal time
};

// Performance Metrics Structure
struct PerformanceMetrics {
    int totalSignals;
    int successfulSignals;
    double winRate;
    double expectedValue;
    double averageProfit;
    double averageBarsToComplete;
    double sharpeRatio;
    double maxDrawdown;
};

// Enhanced Pair Analysis Structure
struct PairAnalysis {
    string currency1;
    string currency2;
    double correlation;
    double halfLife;
    double cointegrationScore;
    double probabilityDiff;
    double totalScore;
    string signalType;
    double currentDeviation;
    SignalQuality quality;    // Added signal quality
    MarketRegime regime;      // Added market regime
    bool isValid;             // Signal validity flag
};

// Arrays for historical tracking
HistoricalSignal trendSignals[];
HistoricalSignal meanRevSignals[];
MarketRegime currentRegime;
PerformanceMetrics trendMetrics;
PerformanceMetrics meanRevMetrics;

// Helper function to calculate absolute volatility
double CalculateAbsoluteVolatility(const double &prices[], int period) {
    if (period < 2) return 0.0;
    
    double sum = 0.0;
    for (int i = 1; i < period; i++) {
        sum += MathAbs(prices[i] - prices[i-1]);
    }
    return sum / (period - 1);
}

// Improved half-life calculation with robust volatility checks
double CalculateHalfLifeWithRegime(double &spread[], int period, MarketRegime &regime) {
    if (ArraySize(spread) < period) {
        Print("CalculateHalfLifeWithRegime: Insufficient data points");
        return 0.0;
    }
    
    // Calculate robust volatility metrics
    double absoluteVol = CalculateAbsoluteVolatility(spread, period);
    double mean = CalculateMean(spread, period);
    double stdDev = CalculateStdDev(spread, period, mean);
    double normalizedStdDev = stdDev / MathAbs(mean + 0.000001); // Avoid division by zero
    
    // Calculate trend strength using robust metrics
    double trendStrength = CalculateRobustTrend(spread, period);
    
    // New volatility check using absolute and normalized measures
    double volThreshold = 5.0 * regime.atr; // Adjust this multiplier based on your needs
    if (absoluteVol > volThreshold) {
        Print("High absolute volatility detected: ", absoluteVol);
        return CalculateAdaptiveHalfLife(spread, period, absoluteVol);
    }
    
    // Improved regression calculation
    double sum_y = 0, sum_x = 0, sum_xy = 0, sum_x2 = 0;
    int validPoints = 0;
    
    for (int i = 1; i < period; i++) {
        double y = spread[i] - spread[i-1];
        double x = spread[i-1];
        
        // Robust outlier detection
        if (MathAbs(y) < stdDev * 3 && MathAbs(x - mean) < stdDev * 3) {
            sum_y += y;
            sum_x += x;
            sum_xy += x * y;
            sum_x2 += x * x;
            validPoints++;
        }
    }
    
    if (validPoints < period/2) {
        Print("Insufficient valid points for regression");
        return CalculateAdaptiveHalfLife(spread, period, absoluteVol);
    }
    
    double n = (double)validPoints;
    double denominator = (n * sum_x2 - sum_x * sum_x);
    
    if (MathAbs(denominator) < 0.000001) {
        return CalculateAdaptiveHalfLife(spread, period, absoluteVol);
    }
    
    double slope = (n * sum_xy - sum_x * sum_y) / denominator;
    
    // Improved slope validation
    if (slope >= -0.000001 || slope < -2.0) {
        return CalculateAdaptiveHalfLife(spread, period, absoluteVol);
    }
    
    double halfLife = -MathLog(2) / slope;
    
    // Validate half-life with adaptive thresholds
    double minHalfLife = MathMax(2.0, period * 0.1);
    double maxHalfLife = MathMin(period * 1.5, 100.0);
    
    if (halfLife < minHalfLife || halfLife > maxHalfLife) {
        return CalculateAdaptiveHalfLife(spread, period, absoluteVol);
    }
    
    return halfLife;
}

// New function to calculate robust trend
double CalculateRobustTrend(const double &prices[], int period) {
    if (period < 2) return 0.0;
    
    double upMoves = 0.0;
    double downMoves = 0.0;
    int trendCount = 0;
    
    for (int i = 1; i < period; i++) {
        double diff = prices[i] - prices[i-1];
        if (MathAbs(diff) > 0.000001) {
            if (diff > 0) upMoves++;
            else downMoves++;
            trendCount++;
        }
    }
    
    if (trendCount == 0) return 0.0;
    return MathAbs(upMoves - downMoves) / trendCount;
}

// New adaptive half-life calculation for high volatility periods
double CalculateAdaptiveHalfLife(const double &spread[], int period, double volatility) {
    double baseHalfLife = period / 4.0;
    double volAdjustment = MathLog(volatility + 1) / MathLog(2);
    double adjustedHalfLife = baseHalfLife * (1 + volAdjustment);
    return MathMax(2.0, MathMin(adjustedHalfLife, period * 1.5));
}

// Calculate dynamic threshold based on market volatility
double CalculateDynamicThreshold(const double& baseThreshold, string symbol, int timeframe, int period) {
    // Get average ATR for stability
    double atr = 0;
    for(int i = 0; i < 3; i++) {
        atr += iATR(symbol, timeframe, period, i);
    }
    atr /= 3;
    
    // Use typical price instead of just close
    double typicalPrice = (iHigh(symbol, timeframe, 0) + iLow(symbol, timeframe, 0) + iClose(symbol, timeframe, 0)) / 3;
    
    double normalizedAtr = atr / typicalPrice;
    
    // Cap the maximum threshold multiplication
    return baseThreshold * MathMin(1 + normalizedAtr, 3.0);
}

// Check if the currency is valid
bool IsCurrencyValid(string currency) {
    if(StringLen(currency) != 3) return false;
    
    string upperCurrency = StringToUpper(currency);  // Changed from StringUpper to StringToUpper
    for(int i = 0; i < ArraySize(validCurrencies); i++) {
        if(upperCurrency == validCurrencies[i]) {
            return true;
        }
    }
    return false;
}
// Calculate correlation between two return series
double CalculateCorrelation(const double& returns1[], const double& returns2[]) {
    int size = MathMin(ArraySize(returns1), ArraySize(returns2));
    if(size < 2) return 0.0;
    
    double sum_x = 0, sum_y = 0, sum_xy = 0;
    double sum_x2 = 0, sum_y2 = 0;
    int validPoints = 0;
    
    // Calculate means first for numerical stability
    double mean1 = 0, mean2 = 0;
    for(int corrIdx = 0; corrIdx < size; corrIdx++) {
        if(MathAbs(returns1[corrIdx]) < 100 && MathAbs(returns2[corrIdx]) < 100) {  // Basic validity check
            mean1 += returns1[corrIdx];
            mean2 += returns2[corrIdx];
            validPoints++;
        }
    }
    
    if(validPoints < size/2) return 0.0;  // Not enough valid points
    
    mean1 /= validPoints;
    mean2 /= validPoints;
    
    // Calculate correlation with adjusted values
    validPoints = 0;
    for(int corrIdx2 = 0; corrIdx2 < size; corrIdx2++) {
        if(MathAbs(returns1[corrIdx2]) < 100 && MathAbs(returns2[corrIdx2]) < 100) {
            double x = returns1[corrIdx2] - mean1;
            double y = returns2[corrIdx2] - mean2;
            
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_x2 += x * x;
            sum_y2 += y * y;
            validPoints++;
        }
    }
    
    double denominator = MathSqrt(sum_x2 * sum_y2);
    
    if(MathAbs(denominator) < 0.000001) return 0.0;
    
    double correlation = sum_xy / denominator;
    
    // Ensure correlation is within [-1, 1]
    return MathMax(-1.0, MathMin(1.0, correlation));
}

// Calculate half-life for mean reversion
double CalculateHalfLife(double &spread[], int period = 20) {
    if(ArraySize(spread) < period) {
        Print("CalculateHalfLife: Insufficient data points");
        return 0.0;
    }
    
    // Remove outliers
    double mean = CalculateMean(spread, period);
    double stdDev = CalculateStdDev(spread, period, mean);
    
    double sum_y = 0, sum_x = 0, sum_xy = 0, sum_x2 = 0;
    int validPoints = 0;
    
    for(int i = 1; i < period; i++) {
        double y = spread[i] - spread[i-1];
        double x = spread[i-1];
        
        // Skip outliers (more than 3 standard deviations from mean)
        if(MathAbs(x - mean) > 3 * stdDev) continue;
        
        sum_y += y;
        sum_x += x;
        sum_xy += x * y;
        sum_x2 += x * x;
        validPoints++;
    }
    
    if(validPoints < period/2) {
        Print("CalculateHalfLife: Insufficient valid points");
        return 0.0;
    }
    
    double n = (double)validPoints;
    double denominator = (n * sum_x2 - sum_x * sum_x);
    
    if(MathAbs(denominator) < 0.000001) {
        Print("CalculateHalfLife: Denominator close to zero");
        return 0.0;
    }
    
    double slope = (n * sum_xy - sum_x * sum_y) / denominator;
    
    // Check if mean reversion exists
    if(slope >= 0 || slope < -2.0) {
        Print("CalculateHalfLife: Invalid slope detected: ", slope);
        return 0.0;
    }
    
    double halfLife = -MathLog(2) / slope;
    
    // Validate half-life is within reasonable bounds
    if(halfLife <= 0 || halfLife > 100) {
        Print("CalculateHalfLife: Half-life out of bounds: ", halfLife);
        return 0.0;
    }
    
    return halfLife;
}

// Helper function to detect market regime
MarketRegime DetectMarketRegime(string symbol, int timeframe) {
    MarketRegime regime;
    regime.symbol = symbol;
    regime.timeframe = timeframe;
    
    // Calculate ATR using multiple periods for stability
    regime.atr = 0;
    for(int atrIdx = 0; atrIdx < 3; atrIdx++) {
        regime.atr += iATR(symbol, timeframe, RegimeAtrPeriod, atrIdx);
    }
    regime.atr /= 3;
    
    // Use ADX with price typical for better accuracy
    regime.adx = iADX(symbol, timeframe, RegimeAdxPeriod, PRICE_TYPICAL, MODE_MAIN, 0);
    
    // Calculate volatility with error checking
    double returns[];
    ArrayResize(returns, RegimeVolPeriod);
    int validReturns = 0;
    
    for(int returnIdx = 0; returnIdx < RegimeVolPeriod; returnIdx++) {
        double curr = iClose(symbol, timeframe, returnIdx);
        double prev = iClose(symbol, timeframe, returnIdx+1);
        
        if(prev != 0) {
            returns[returnIdx] = (curr - prev) / prev;
            validReturns++;
        } else {
            returns[returnIdx] = 0;
        }
    }
    
    if(validReturns > RegimeVolPeriod/2) {
        regime.volatility = CalculateStdDev(returns, RegimeVolPeriod, CalculateMean(returns, RegimeVolPeriod));
    } else {
        regime.volatility = regime.atr;  // Fallback to ATR if insufficient valid returns
    }
    
    regime.period = TimeCurrent();
    
    // Enhanced market condition detection
    double trendBaseThreshold = 25.0;
    double volatilityBaseThreshold = 2.0;
    double trendThreshold = CalculateDynamicThreshold(trendBaseThreshold, symbol, timeframe, RegimeAtrPeriod);
    double volatilityThreshold = CalculateDynamicThreshold(volatilityBaseThreshold, symbol, timeframe, RegimeVolPeriod);
    
    // Additional check for trend direction
    double plusDI = iADX(symbol, timeframe, RegimeAdxPeriod, PRICE_TYPICAL, MODE_PLUSDI, 0);
    double minusDI = iADX(symbol, timeframe, RegimeAdxPeriod, PRICE_TYPICAL, MODE_MINUSDI, 0);
    
    if(regime.adx > trendThreshold) {
        if(regime.volatility > regime.atr * volatilityThreshold)
            regime.condition = "VOLATILE_TREND" + (plusDI > minusDI ? "_UP" : "_DOWN");
        else
            regime.condition = "STRONG_TREND" + (plusDI > minusDI ? "_UP" : "_DOWN");
    }
    else if(regime.volatility < regime.atr * 0.5)
        regime.condition = "RANGE_BOUND";
    else
        regime.condition = "MIXED";
    
    return regime;
}



//+------------------------------------------------------------------+
//| Helper Functions                                                   |
//+------------------------------------------------------------------+

string FormatPairName(string currency1, string currency2)
{
    string priority[] = {"EUR", "GBP", "AUD", "NZD", "USD", "CAD", "CHF", "JPY"};
    
    int priority1 = ArraySearch(priority, currency1);
    int priority2 = ArraySearch(priority, currency2);
    
    if(priority1 == -1 || priority2 == -1)
        return currency1 + currency2;
        
    return (priority1 < priority2) ? currency1 + currency2 : currency2 + currency1;
}

int ArraySearch(string &arr[], string value)
{
    for(int i = 0; i < ArraySize(arr); i++)
    {
        if(arr[i] == value) return i;
    }
    return -1;
}
// Custom indicator initialization function
int OnInit() {
    // Initialize indicator buffer
    SetIndexBuffer(0, csiBuffer);
    SetIndexLabel(0, "CSI");
    
    // Validate base currency
    string validCurrency = BaseCurrency;
    if (!IsCurrencyValid(BaseCurrency)) {
        Print("Invalid currency selected. Defaulting to EUR.");
        validCurrency = "EUR";
    }
    
    // Initialize arrays
    ArrayResize(trendSignals, 0);
    ArrayResize(meanRevSignals, 0);
    
    // Initialize performance metrics
    trendMetrics.totalSignals = 0;
    trendMetrics.successfulSignals = 0;
    meanRevMetrics.totalSignals = 0;
    meanRevMetrics.successfulSignals = 0;
    
    // Initialize market regime
    currentRegime = DetectMarketRegime(Symbol(), PERIOD_CURRENT);
    
    // Generate currency pairs
    GeneratePairs();
    
    // Initialize CSI arrays
    for (int i = 0; i < ArraySize(currencies); ++i) {
        overallCSI[i] = 0;
        originalCSI[i] = 0;
        kurtosisHistory[i] = 0;
        skewnessHistory[i] = 0;
    }
    
    // Reset tracking variables
    prevStrongestCurrency = "";
    prevWeakestCurrency = "";
    timeStrongest = "";
    timeWeakest = "";
    
    // Create necessary global variables for tracking
    if(!GlobalVariableCheck("LastUpdateTime"))
        GlobalVariableSet("LastUpdateTime", TimeCurrent());
    if(!GlobalVariableCheck("LastValidationTime"))
        GlobalVariableSet("LastValidationTime", TimeCurrent());
    
    Print("Indicator initialized with validation mode: ", EnableValidation);
    return(INIT_SUCCEEDED);
}
void GeneratePairs() {
    for (int i = 0; i < ArraySize(currencies); ++i) {
        for (int j = i + 1; j < ArraySize(currencies); ++j) {
            string pair = FormatPairName(currencies[i], currencies[j]);

            // Check if the pair exists in the market
            if (SymbolExists(pair)) {
                ArrayResize(pairs, ArraySize(pairs) + 1);
                pairs[ArraySize(pairs) - 1] = pair;
            }
        }
    }
}

bool SymbolExists(string symbol) {
    int existingSymbols = SymbolsTotal(false);
    for (int i = 0; i < existingSymbols; i++) {
        string existingSymbol = SymbolName(i, false);
        if (existingSymbol == symbol) {
            return true;
        }
    }
    return false;
}

// Helper function to test for cointegration
double TestCointegration(const double& prices1[], const double& prices2[], int period = 20) {
    if (ArraySize(prices1) < period || ArraySize(prices2) < period) {
        return 0.0;
    }

    // Calculate spread
    double spread[];
    ArrayResize(spread, period);
    
    for (int coinIdx = 0; coinIdx < period; coinIdx++) {
        spread[coinIdx] = prices1[coinIdx] - prices2[coinIdx];
    }
    
    // Perform Augmented Dickey-Fuller test
    double sum_y = 0, sum_x = 0, sum_xy = 0, sum_x2 = 0;
    
    for (int adfIdx = 1; adfIdx < period; adfIdx++) {
        double y = spread[adfIdx] - spread[adfIdx-1];
        double x = spread[adfIdx-1];
        
        sum_y += y;
        sum_x += x;
        sum_xy += x * y;
        sum_x2 += x * x;
    }
    
    double n = period - 1;
    
    // Check for zero division
    double denominator = (n * sum_x2 - sum_x * sum_x);
    if (MathAbs(denominator) < 0.000001) {
        return 0.0;
    }
    
    double beta = (n * sum_xy - sum_x * sum_y) / denominator;
    double alpha = (sum_y - beta * sum_x) / n;
    
    // Check for zero division in final calculation
    double radicand = 1 - alpha * alpha / n;
    if (radicand <= 0.0) {
        return 0.0;
    }
    
    // Calculate test statistic
    return beta / MathSqrt(radicand);
}

double CalculateWeightedVolumeWeightedCSI(string currency, int Timeframe, double weight) {
    double csiValue = 0.0;
    int tfMinutes = 0;

    switch (Timeframe) {
        case 60:  // H1
            tfMinutes = 60;
            break;
        case 240:  // H4
            tfMinutes = 240;
            break;
        case 1440: // D1
            tfMinutes = 1440;
            break;
        case 10080: // W1
            tfMinutes = 10080;
            break;
    }

    for (int pairIndex = 0; pairIndex < ArraySize(pairs); ++pairIndex) {
        string pair = pairs[pairIndex];
        string base = StringSubstr(pair, 0, 3);
        string quote = StringSubstr(pair, 3, 3);

        if (base == currency || quote == currency) {
            double close = iClose(pair, tfMinutes, 0);
            long tickVolume = iVolume(pair, tfMinutes, 0);
            double factor = (base == currency) ? 1 : -1;
            csiValue += factor * close * tickVolume * weight;
        }
    }
    return csiValue;
}

double CalculateMean(double &arr[], int size) {
    if (size <= 0) {
        return 0.0; // Return 0 or throw error for empty array
    }
    double sum = 0.0;
    for (int meanIndex = 0; meanIndex < size; ++meanIndex) {
        sum += arr[meanIndex];
    }
    return sum / size;
}

double CalculateStdDev(double &arr[], int size, double mean) {
    if (size <= 1) {
        return 0.0; // Cannot calculate std dev with 1 or fewer samples
    }
    double sum = 0.0;
    for (int stdDevIndex = 0; stdDevIndex < size; ++stdDevIndex) {
        sum += MathPow(arr[stdDevIndex] - mean, 2);
    }
    double variance = sum / (size - 1); // Use n-1 for sample standard deviation
    return variance <= 0 ? 0.0 : MathSqrt(variance);
}

// Function to validate historical signals and update performance metrics
void ValidateHistoricalSignal(HistoricalSignal &signal, bool isTrendSignal) {
    if(signal.wasSuccessful) return; // Skip if already validated
    
    int barsToTarget = 0;
    double maxAdverse = 0;
    bool hitTarget = false;
    bool hitStop = false;
    
    double entryPrice = signal.entryPrice;
    double targetPrice = isTrendSignal ? 
        (signal.direction == "BUY" ? entryPrice + 50 * Point : entryPrice - 50 * Point) :
        (signal.direction == "BUY" ? entryPrice + 25 * Point : entryPrice - 25 * Point);
    double stopPrice = signal.direction == "BUY" ? 
        entryPrice - 30 * Point : 
        entryPrice + 30 * Point;
    
    // Look forward from signal time to find outcome
    for(int i = 1; i < 1000; i++) {  // Check up to 1000 bars
        double high = iHigh(signal.pair, PERIOD_CURRENT, i);
        double low = iLow(signal.pair, PERIOD_CURRENT, i);
        
        // Track maximum adverse excursion
        if(signal.direction == "BUY") {
            maxAdverse = MathMax(maxAdverse, entryPrice - low);
        } else {
            maxAdverse = MathMax(maxAdverse, high - entryPrice);
        }
        
        // Check if target or stop was hit
        if(signal.direction == "BUY") {
            if(high >= targetPrice) {
                hitTarget = true;
                barsToTarget = i;
                break;
            }
            if(low <= stopPrice) {
                hitStop = true;
                barsToTarget = i;
                break;
            }
        } else {
            if(low <= targetPrice) {
                hitTarget = true;
                barsToTarget = i;
                break;
            }
            if(high >= stopPrice) {
                hitStop = true;
                barsToTarget = i;
                break;
            }
        }
    }
    
    // Update signal status and performance metrics
    if(hitTarget || hitStop) {
        signal.wasSuccessful = hitTarget;
        signal.barsToComplete = barsToTarget;
        signal.profit = hitTarget ? 
            (signal.direction == "BUY" ? 50 : -50) : 
            (signal.direction == "BUY" ? -30 : 30);
            
        // Update performance metrics
        UpdatePerformanceMetrics(hitTarget, signal.profit, barsToTarget, isTrendSignal);
    }
}
double CalculateKurtosis(double &arr[], int size, double mean, double stdDev) {
    if (size <= 3 || stdDev <= 0) {
        return 0.0; // Kurtosis undefined for small samples or zero std dev
    }
    double sum = 0.0;
    double stdDev4 = MathPow(stdDev, 4);
    if (stdDev4 <= 0) {
        return 0.0;
    }
    
    for (int kurtosisIndex = 0; kurtosisIndex < size; ++kurtosisIndex) {
        sum += MathPow(arr[kurtosisIndex] - mean, 4);
    }
    double fourthMoment = sum / size;
    return (fourthMoment / stdDev4) - 3;
}

double CalculateSkewness(double &arr[], int size, double mean, double stdDev) {
    if (size <= 2 || stdDev <= 0) {
        return 0.0; // Skewness undefined for small samples or zero std dev
    }
    double sum = 0.0;
    double stdDev3 = MathPow(stdDev, 3);
    if (stdDev3 <= 0) {
        return 0.0;
    }
    
    for (int skewnessIndex = 0; skewnessIndex < size; ++skewnessIndex) {
        sum += MathPow(arr[skewnessIndex] - mean, 3);
    }
    double thirdMoment = sum / size;
    return thirdMoment / stdDev3;
}

void CalculateZScores(double &arr[], int size, double mean, double stdDev) {
    int zScoreIndex; // Declare the variable once at the start
    
    if (size <= 0) {
        return; // Nothing to do for empty array
    }
    if (stdDev <= 0) {
        Print("Warning: Standard deviation is zero or negative. Z-scores set to 0.");
        for (zScoreIndex = 0; zScoreIndex < size; ++zScoreIndex) { // Use without 'int'
            arr[zScoreIndex] = 0;
        }
        return;
    }
    
    for (zScoreIndex = 0; zScoreIndex < size; ++zScoreIndex) { // Use without 'int'
        arr[zScoreIndex] = (arr[zScoreIndex] - mean) / stdDev;
    }
}

int ArrayFind(string &arr[], string value) {
    for (int i = 0; i < ArraySize(arr); i++) {
        if (arr[i] == value) {
            return i;
        }
    }
    return -1;  // Value not found
}
// Declare priorProbabilities as a global variable with initialization
double priorProbabilities[8] = {0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125}; // Equal probabilities (1/8)

// Calculate quality score for a signal
SignalQuality CalculateSignalQuality(string type, double probability, double strength, MarketRegime &regime) {
    SignalQuality quality;
    
    // Calculate probability score (0-1)
    quality.probabilityScore = MathMin(probability, 1.0);
    
    // Calculate regime score based on signal type
    if(type == "TREND") {
        quality.regimeScore = (regime.adx > 25) ? 1.0 : regime.adx / 25.0;
    } else {
        quality.regimeScore = (regime.adx < 20) ? 1.0 : (30 - regime.adx) / 10.0;
    }
    
    // Calculate strength score
    quality.strengthScore = MathMin(strength, 1.0);
    
    // Calculate total score with weightings
    quality.totalScore = quality.probabilityScore * 0.4 + 
                        quality.regimeScore * 0.3 + 
                        quality.strengthScore * 0.3;
                        
    quality.confidence = quality.totalScore * MathMin(probability, 1.0);
    
    return quality;
}

// Function to update performance metrics
void UpdatePerformanceMetrics(bool wasSuccessful, double profit, int barsToComplete, bool isTrendSignal) {
    if(isTrendSignal) {
        trendMetrics.totalSignals++;
        if(wasSuccessful) trendMetrics.successfulSignals++;
        trendMetrics.averageProfit = ((trendMetrics.averageProfit * (trendMetrics.totalSignals - 1)) + profit) / trendMetrics.totalSignals;
        trendMetrics.averageBarsToComplete = ((trendMetrics.averageBarsToComplete * (trendMetrics.totalSignals - 1)) + barsToComplete) / trendMetrics.totalSignals;
        trendMetrics.winRate = (double)trendMetrics.successfulSignals / trendMetrics.totalSignals;
        trendMetrics.expectedValue = trendMetrics.winRate * trendMetrics.averageProfit;
    } else {
        meanRevMetrics.totalSignals++;
        if(wasSuccessful) meanRevMetrics.successfulSignals++;
        meanRevMetrics.averageProfit = ((meanRevMetrics.averageProfit * (meanRevMetrics.totalSignals - 1)) + profit) / meanRevMetrics.totalSignals;
        meanRevMetrics.averageBarsToComplete = ((meanRevMetrics.averageBarsToComplete * (meanRevMetrics.totalSignals - 1)) + barsToComplete) / meanRevMetrics.totalSignals;
        meanRevMetrics.winRate = (double)meanRevMetrics.successfulSignals / meanRevMetrics.totalSignals;
        meanRevMetrics.expectedValue = meanRevMetrics.winRate * meanRevMetrics.averageProfit;
    }
}

// Calculate correlation between two return series with period parameter
double CalculateCorrelationEx(const double& returns1[], const double& returns2[], int period) {
    int size = MathMin(MathMin(ArraySize(returns1), ArraySize(returns2)), period);
    if(size < 2) return 0.0;
    
    double sum_x = 0, sum_y = 0, sum_xy = 0;
    double sum_x2 = 0, sum_y2 = 0;
    int validPoints = 0;
    
    // Calculate means first for numerical stability
    double mean1 = 0, mean2 = 0;
    for(int corrIdx = 0; corrIdx < size; corrIdx++) {
        if(MathAbs(returns1[corrIdx]) < 100 && MathAbs(returns2[corrIdx]) < 100) {  // Basic validity check
            mean1 += returns1[corrIdx];
            mean2 += returns2[corrIdx];
            validPoints++;
        }
    }
    
    if(validPoints < size/2) return 0.0;  // Not enough valid points
    
    mean1 /= validPoints;
    mean2 /= validPoints;
    
    // Calculate correlation with adjusted values
    validPoints = 0;
    for(int corrIdx2 = 0; corrIdx2 < size; corrIdx2++) {
        if(MathAbs(returns1[corrIdx2]) < 100 && MathAbs(returns2[corrIdx2]) < 100) {
            double x = returns1[corrIdx2] - mean1;
            double y = returns2[corrIdx2] - mean2;
            
            sum_x += x;
            sum_y += y;
            sum_xy += x * y;
            sum_x2 += x * x;
            sum_y2 += y * y;
            validPoints++;
        }
    }
    
    double denominator = MathSqrt(sum_x2 * sum_y2);
    
    if(MathAbs(denominator) < 0.000001) return 0.0;
    
    double correlation = sum_xy / denominator;
    
    // Ensure correlation is within [-1, 1]
    return MathMax(-1.0, MathMin(1.0, correlation));
}

// Function to add a timeframe result to the analysis array
void AddTimeframeResult(int timeframe) {
    // Create a new TimeframeAnalysis structure
    TimeframeAnalysis tfResult;
    tfResult.timeframe = timeframe;
    // Simulate calculations for probability, uncertainty, and strength
    tfResult.probability = MathRand() / 32768.0;  // Random probability value (0 to 1)
    tfResult.uncertainty = MathRand() / 32768.0;  // Random uncertainty value (0 to 1)
    tfResult.strength = MathRand() / 32768.0;     // Random strength score (0 to 1)
    // Mark as significant if probability meets threshold
    tfResult.isSignificant = (tfResult.probability >= MinTimeframeProbability &&
                              tfResult.uncertainty <= MaxTimeframeUncertainty);
    // Resize array to add the new result
    int size = ArraySize(timeframeResults);
    ArrayResize(timeframeResults, size + 1);
    // Add the new result to the array
    timeframeResults[size] = tfResult;
}

// Calculate signal-to-noise ratio
double CalculateSignalToNoise(const double &prices[], int timeframe) {
    double signal = 0, noise = 0;
    
    for (int i = 1; i < ArraySize(prices); i++) {
        double change = prices[i] - prices[i - 1];
        if (MathAbs(change) > 0) {
            signal += change;
            noise += MathAbs(change);
        }
    }
    
    return noise > 0 ? MathAbs(signal) / noise : 0;
}

// Calculate trend strength
double CalculateTrendStrength(const double &prices[], int timeframe) {
    if (ArraySize(prices) < 2) return 0;
    
    double sumDirectionalChanges = 0;
    double sumChanges = 0;
    
    for (int i = 1; i < ArraySize(prices); i++) {
        double change = prices[i] - prices[i - 1];
        sumDirectionalChanges += change;
        sumChanges += MathAbs(change);
    }
    
    return sumChanges > 0 ? MathAbs(sumDirectionalChanges) / sumChanges : 0;
}



int OnCalculate(
   const int rates_total,
   const int prev_calculated,
   const datetime &time[],
   const double &open[],
   const double &high[],
   const double &low[],
   const double &close[],
   const long &tick_volume[],
   const long &volume[],
   const int &spread[]
) {
   // Validate input parameters
   if(rates_total <= 0) {
       Print("Error: Invalid rates_total parameter");
       return(0);
   }

   // Ensure priorProbabilities are valid (sum to 1)
   double probSum = 0;
   for(int checkIndex = 0; checkIndex < ArraySize(priorProbabilities); checkIndex++) {
       probSum += priorProbabilities[checkIndex];
   }

   // If probabilities don't sum to 1 (within epsilon), reinitialize them
   if(MathAbs(probSum - 1.0) > 0.000001) {
       for(int initIndex = 0; initIndex < ArraySize(priorProbabilities); initIndex++) {
           priorProbabilities[initIndex] = 1.0 / ArraySize(priorProbabilities);
       }
       Print("Prior probabilities reinitialized to uniform distribution");
   }

   // Update market regime
   currentRegime = DetectMarketRegime(Symbol(), PERIOD_CURRENT);
   
// Validate historical signals if enabled
if(EnableValidation && TimeCurrent() >= GlobalVariableGet("LastValidationTime") + 3600) { // Check every hour
    for(int i = ArraySize(trendSignals)-1; i >= 0; i--) {
        if(!trendSignals[i].wasSuccessful) {
            ValidateHistoricalSignal(trendSignals[i], true);
        }
    }
    for(int j = ArraySize(meanRevSignals)-1; j >= 0; j--) {
        if(!meanRevSignals[j].wasSuccessful) {
            ValidateHistoricalSignal(meanRevSignals[j], false);
        }
    }
    GlobalVariableSet("LastValidationTime", TimeCurrent());
}

// Calculate CSI values for each currency
Print("\n=== Initial Dynamic CSI Calculations ===");
for (int r = 0; r < ArraySize(currencies); ++r) {
    double weightedCSI = 0;
    double totalWeight = 0;
    
    Print(currencies[r], ":");
    // Calculate CSI for each significant timeframe
    for(int tf = 0; tf < ArraySize(timeframeResults); tf++) {
        // Remove the reference and access directly
        TimeframeAnalysis currentTf = timeframeResults[tf];
        
        // Calculate weighted CSI for this timeframe
        double tfCSI = CalculateWeightedVolumeWeightedCSI(
            currencies[r], 
            currentTf.timeframe, 
            currentTf.strength * (1 - currentTf.uncertainty)
        );
        
        weightedCSI += tfCSI * currentTf.strength * (1 - currentTf.uncertainty);
        totalWeight += currentTf.strength * (1 - currentTf.uncertainty);
        
        Print("  Timeframe ", currentTf.timeframe, "min CSI: ", DoubleToStr(tfCSI, 6),
              " Weight: ", DoubleToStr(currentTf.strength * (1 - currentTf.uncertainty), 6));
    }
    
    // Normalize by total weight
    if(totalWeight > 0) {
        weightedCSI /= totalWeight;
    }
    
    Print("  Total Weighted CSI: ", DoubleToStr(weightedCSI, 6));
    overallCSI[r] = weightedCSI;
    originalCSI[r] = weightedCSI;
}
   
// Calculate normalization factors with better scaling
double normalizationFactors[8];
ArrayInitialize(normalizationFactors, 0);

// First calculate the sum of absolute CSI values for scaling
double totalCSI = 0;
Print("\n=== CSI Pre-scaling Analysis ===");
for(int sumIdx = 0; sumIdx < ArraySize(currencies); sumIdx++) {
    totalCSI += MathAbs(overallCSI[sumIdx]);
    Print(currencies[sumIdx], " Original CSI: ", DoubleToStr(overallCSI[sumIdx], 6));
}
double scalingCSI = totalCSI / ArraySize(currencies);  // Changed from avgCSI to scalingCSI

Print("\n=== CSI Scaling Parameters ===");
Print("Total CSI: ", DoubleToStr(totalCSI, 6));
Print("Average CSI: ", DoubleToStr(scalingCSI, 6));

// Apply relative scaling
Print("\n=== Applying CSI Scaling ===");
for(int currencyIdx = 0; currencyIdx < ArraySize(currencies); currencyIdx++) {
    Print(currencies[currencyIdx], ":");
    Print("  Before scaling: ", DoubleToStr(overallCSI[currencyIdx], 6));
    
    // Scale relative to average
    double relativeCSI = overallCSI[currencyIdx] / (scalingCSI + 0.001);  // Add small constant to prevent division by zero
    Print("  Relative CSI: ", DoubleToStr(relativeCSI, 6));
    
    // Apply sigmoid transformation to bound values while preserving differences
    overallCSI[currencyIdx] = 2.0 / (1.0 + MathExp(-relativeCSI)) - 1.0;  // Results in [-1, 1] range
    
    Print("  After scaling: ", DoubleToStr(overallCSI[currencyIdx], 6));
}

// Store normalized values for verification
Print("\n=== Final Scaled Values ===");
for(int checkIdx = 0; checkIdx < ArraySize(currencies); checkIdx++) {  // Changed from verifyIdx to checkIdx
    Print(currencies[checkIdx], " Final CSI: ", DoubleToStr(overallCSI[checkIdx], 6));
}
   
// Structure to hold currency analysis data
struct CurrencyAnalysis {
    string currency;
    double zScore;
    double skewness;
    double kurtosis;
    string strength;
};


// Bayesian Update:
// Calculate mean and standard deviation for CSI
double meanCSI = CalculateMean(overallCSI, ArraySize(currencies));
double stdDevCSI = CalculateStdDev(overallCSI, ArraySize(currencies), meanCSI);

Print("Initial CSI Statistics:");
Print("Mean CSI: ", DoubleToStr(meanCSI, 6));
Print("StdDev CSI: ", DoubleToStr(stdDevCSI, 6));

// Dynamic Threshold Adjustments for Skewness and Kurtosis
double skewnessThreshold = 0.1 * stdDevCSI; // Dynamic skewness threshold based on standard deviation
double kurtosisThreshold = 1.0 + stdDevCSI; // Dynamic kurtosis threshold based on standard deviation

// Calculate likelihoods (assuming normal distribution)
double likelihoods[8];
double maxCSI = DBL_MIN;
double minCSI = DBL_MAX;

// First find the range of CSI values
Print("\nCSI Values before scaling:");
for(int rangeIdx = 0; rangeIdx < ArraySize(currencies); rangeIdx++) {
    Print(currencies[rangeIdx], " CSI: ", DoubleToStr(overallCSI[rangeIdx], 6));
    if(overallCSI[rangeIdx] > maxCSI) maxCSI = overallCSI[rangeIdx];
    if(overallCSI[rangeIdx] < minCSI) minCSI = overallCSI[rangeIdx];
}

Print("\nCSI Range:");
Print("Max CSI: ", DoubleToStr(maxCSI, 6));
Print("Min CSI: ", DoubleToStr(minCSI, 6));
Print("Range: ", DoubleToStr(maxCSI - minCSI, 6));

// Calculate scaled likelihoods with better differentiation
Print("\nCalculating Likelihoods:");
double csiRange = maxCSI - minCSI;
double scaleFactor = (csiRange > 0.001) ? csiRange : 1.0;

// Calculate reference values for scaling
double sumCSI = 0;
for(int calcIdx = 0; calcIdx < ArraySize(currencies); calcIdx++) {
    sumCSI += MathAbs(overallCSI[calcIdx]);
}
double avgCSI = sumCSI / ArraySize(currencies);

// Calculate initial likelihoods using relative strength
for(int likelihood_idx = 0; likelihood_idx < ArraySize(currencies); likelihood_idx++) {
    // Use relative strength instead of pure normalization
    double relativeStrength = overallCSI[likelihood_idx] / (avgCSI + 0.001); // Avoid division by zero
    
    // Apply sigmoid-like transformation to maintain differences
    likelihoods[likelihood_idx] = 1.0 / (1.0 + MathExp(-3.0 * relativeStrength));
    
    Print(currencies[likelihood_idx], ":");
    Print("  Original CSI: ", DoubleToStr(overallCSI[likelihood_idx], 6));
    Print("  Relative Strength: ", DoubleToStr(relativeStrength, 6));
    Print("  Initial Likelihood: ", DoubleToStr(likelihoods[likelihood_idx], 6));
}

// Update posterior probabilities with improved scaling
double posteriorProbabilities[8];
double evidence = 0;
double maxLikelihood = DBL_MIN;
double minLikelihood = DBL_MAX;

// Find likelihood range
for(int findRangeIdx = 0; findRangeIdx < ArraySize(currencies); findRangeIdx++) {
    if(likelihoods[findRangeIdx] > maxLikelihood) maxLikelihood = likelihoods[findRangeIdx];
    if(likelihoods[findRangeIdx] < minLikelihood) minLikelihood = likelihoods[findRangeIdx];
}

Print("\nLikelihood Range - Max:", DoubleToStr(maxLikelihood, 6), " Min:", DoubleToStr(minLikelihood, 6));

// Enhance likelihood differences using power scaling
double enhancementFactor = 2.0; // Adjust this to control differentiation
for(int enhanceIdx = 0; enhanceIdx < ArraySize(currencies); enhanceIdx++) {
    double normalizedLikelihood = (likelihoods[enhanceIdx] - minLikelihood) / (maxLikelihood - minLikelihood + 0.001);
    likelihoods[enhanceIdx] = MathPow(normalizedLikelihood, enhancementFactor);
    Print(currencies[enhanceIdx], " Enhanced Likelihood: ", DoubleToStr(likelihoods[enhanceIdx], 6));
}

// Final posterior probability calculations
double totalPosterior = 0;
Print("\nCalculating final posterior probabilities:");
for(int bayesIdx = 0; bayesIdx < ArraySize(currencies); bayesIdx++) {
    posteriorProbabilities[bayesIdx] = (likelihoods[bayesIdx] * priorProbabilities[bayesIdx]) / evidence;
    Print(currencies[bayesIdx], ":");
    Print("  Likelihood: ", DoubleToStr(likelihoods[bayesIdx], 6));
    Print("  Prior: ", DoubleToStr(priorProbabilities[bayesIdx], 6));
    Print("  Posterior: ", DoubleToStr(posteriorProbabilities[bayesIdx], 6));
}

// Final verification and normalization
Print("\nFinal Probability Distribution:");
for(int verifyIdx = 0; verifyIdx < ArraySize(currencies); verifyIdx++) {
    totalPosterior += posteriorProbabilities[verifyIdx];
    Print(currencies[verifyIdx], " Final Posterior: ", DoubleToStr(posteriorProbabilities[verifyIdx], 6));
}
Print("Total posterior probability: ", DoubleToStr(totalPosterior, 6));


   // Calculate Bayesian kurtosis and skewness
   for (int statCalcIndex = 0; statCalcIndex < ArraySize(currencies); statCalcIndex++) {
       // Calculate specific mean and std dev for this currency
       double currencyMean = overallCSI[statCalcIndex];
       double currencyStdDev = 0;
       
       // Calculate currency-specific standard deviation
       for (int stdDevCalcIndex = 0; stdDevCalcIndex < ArraySize(currencies); stdDevCalcIndex++) {
           currencyStdDev += MathPow(overallCSI[stdDevCalcIndex] - currencyMean, 2);
       }
       currencyStdDev = MathSqrt(currencyStdDev / ArraySize(currencies));
       
       // Calculate currency-specific moments
       double kurtSum = 0;
       double skewSum = 0;
       double weightSum = 0;
       
       for (int momentCalcIndex = 0; momentCalcIndex < ArraySize(currencies); momentCalcIndex++) {
           // Calculate scaled difference based on the specific currency
           double scaledDiff = (overallCSI[momentCalcIndex] - currencyMean) / 
                             (currencyStdDev > 0 ? currencyStdDev : 1);
           
           // Weight based on currency strength and posterior probability
           double weight = posteriorProbabilities[momentCalcIndex] * MathAbs(overallCSI[statCalcIndex]);
           
           kurtSum += MathPow(scaledDiff, 4) * weight;
           skewSum += MathPow(scaledDiff, 3) * weight;
           weightSum += weight;
       }
       
       // Store results using currency-specific calculations
       if (weightSum > 0) {
           kurtosisHistory[statCalcIndex] = (kurtSum / weightSum) - 3.0;  // Excess kurtosis
           skewnessHistory[statCalcIndex] = skewSum / weightSum;
       } else {
           kurtosisHistory[statCalcIndex] = 0;
           skewnessHistory[statCalcIndex] = 0;
       }
       
       Print(currencies[statCalcIndex], ": Kurtosis=", DoubleToStr(kurtosisHistory[statCalcIndex], 4),
             " Skewness=", DoubleToStr(skewnessHistory[statCalcIndex], 4),
             " Mean=", DoubleToStr(currencyMean, 4),
             " StdDev=", DoubleToStr(currencyStdDev, 4));
   }

    // Calculate individual currency metrics
    double chosenCurrencyKurtosis = kurtosisHistory[ArrayFind(currencies, BaseCurrency)];
    double chosenCurrencySkewness = skewnessHistory[ArrayFind(currencies, BaseCurrency)];
    int chartCurrencyIndex = ArrayFind(currencies, chartCurrency);
    double chartCurrencyKurtosis = kurtosisHistory[chartCurrencyIndex];
    double chartCurrencySkewness = skewnessHistory[chartCurrencyIndex];
    double chosenCurrencyDifference = chosenCurrencyKurtosis - chosenCurrencySkewness;
    double chartCurrencyDifference = chartCurrencyKurtosis - chartCurrencySkewness;



// Generate interpretations for skewness with Bayesian perspective
string skewnessInterpretation = "";
if (chosenCurrencySkewness > skewnessThreshold) { // Dynamic threshold for Bayesian skewness
    skewnessInterpretation = "Strong Bayesian Evidence (Bullish) for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nSkewness Value: " + DoubleToStr(chosenCurrencySkewness, 4) + 
                            "\nInterpretation: High probability of continued upward momentum" +
                            "\nConfidence Level: Strong (>" + DoubleToStr(skewnessThreshold, 4) + " threshold)";
} else if (chosenCurrencySkewness < -skewnessThreshold) {
    skewnessInterpretation = "Strong Bayesian Evidence (Bearish) for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nSkewness Value: " + DoubleToStr(chosenCurrencySkewness, 4) + 
                            "\nInterpretation: High probability of continued downward momentum" +
                            "\nConfidence Level: Strong (>" + DoubleToStr(skewnessThreshold, 4) + " threshold)";
} else {
    skewnessInterpretation = "Uncertain Bayesian Evidence for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nSkewness Value: " + DoubleToStr(chosenCurrencySkewness, 4) + 
                            "\nInterpretation: Insufficient evidence for directional bias" +
                            "\nConfidence Level: Low (<" + DoubleToStr(skewnessThreshold, 4) + " threshold)";
}

// Generate interpretations for kurtosis with Bayesian perspective
string kurtosisInterpretation = "";
if (chosenCurrencyKurtosis > kurtosisThreshold) { // Dynamic threshold for Bayesian kurtosis
    kurtosisInterpretation = "High Volatility Probability for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nKurtosis Value: " + DoubleToStr(chosenCurrencyKurtosis, 4) + 
                            "\nInterpretation: Strong evidence of potential significant moves" +
                            "\nConfidence Level: High (>" + DoubleToStr(kurtosisThreshold, 4) + " threshold)";
} else if (chosenCurrencyKurtosis < -kurtosisThreshold) {
    kurtosisInterpretation = "Low Volatility Probability for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nKurtosis Value: " + DoubleToStr(chosenCurrencyKurtosis, 4) + 
                            "\nInterpretation: Strong evidence of stable movement" +
                            "\nConfidence Level: High (>" + DoubleToStr(kurtosisThreshold, 4) + " threshold)";
} else {
    kurtosisInterpretation = "Normal Volatility Profile for " + BaseCurrency + 
                            "\nPosterior Probability: " + DoubleToStr(posteriorProbabilities[ArrayFind(currencies, BaseCurrency)], 4) + 
                            "\nKurtosis Value: " + DoubleToStr(chosenCurrencyKurtosis, 4) + 
                            "\nInterpretation: Insufficient evidence for volatility bias" +
                            "\nConfidence Level: Low (<" + DoubleToStr(kurtosisThreshold, 4) + " threshold)";
}

// Generate Bayesian difference interpretations
string kurtosisDiffInterpretation = "";
double kurtosisProbDiff = posteriorProbabilities[ArrayFind(currencies, BaseCurrency)] - posteriorProbabilities[chartCurrencyIndex];

if (MathAbs(kurtosisProbDiff) > 0.1) { // Significant probability difference threshold
    if (chosenCurrencyKurtosis > chartCurrencyKurtosis) {
        kurtosisDiffInterpretation = "Significant Bayesian Evidence (" + BaseCurrency + " > " + chartCurrency + "):\n";
        kurtosisDiffInterpretation += "Probability Differential: " + DoubleToStr(kurtosisProbDiff, 4) + "\n";
        kurtosisDiffInterpretation += "Interpretation: Strong evidence that " + BaseCurrency + " has higher volatility potential\n";
        kurtosisDiffInterpretation += "Confidence: High (>" + DoubleToStr(kurtosisThreshold, 4) + " threshold)\n";
    } else {
        kurtosisDiffInterpretation = "Significant Bayesian Evidence (" + BaseCurrency + " < " + chartCurrency + "):\n";
        kurtosisDiffInterpretation += "Probability Differential: " + DoubleToStr(kurtosisProbDiff, 4) + "\n";
        kurtosisDiffInterpretation += "Interpretation: Strong evidence that " + chartCurrency + " has higher volatility potential\n";
        kurtosisDiffInterpretation += "Confidence: High (>" + DoubleToStr(kurtosisThreshold, 4) + " threshold)\n";
    }
} else {
    kurtosisDiffInterpretation = "Insufficient Bayesian Evidence:\n";
    kurtosisDiffInterpretation += "Probability Differential: " + DoubleToStr(kurtosisProbDiff, 4) + "\n";
    kurtosisDiffInterpretation += "Interpretation: No significant difference in volatility probabilities\n";
}

string skewnessDiffInterpretation = "";
double skewnessProbDiff = posteriorProbabilities[ArrayFind(currencies, BaseCurrency)] - posteriorProbabilities[chartCurrencyIndex];

if (MathAbs(skewnessProbDiff) > 0.1) {
    if (chosenCurrencySkewness > chartCurrencySkewness) {
        skewnessDiffInterpretation = "Significant Bayesian Evidence (" + BaseCurrency + " > " + chartCurrency + "):\n";
        skewnessDiffInterpretation += "Probability Differential: " + DoubleToStr(skewnessProbDiff, 4) + "\n";
        skewnessDiffInterpretation += "Interpretation: Strong evidence for " + BaseCurrency + " bullish trend\n";
    } else {
        skewnessDiffInterpretation = "Significant Bayesian Evidence (" + BaseCurrency + " < " + chartCurrency + "):\n";
        skewnessDiffInterpretation += "Probability Differential: " + DoubleToStr(skewnessProbDiff, 4) + "\n";
        skewnessDiffInterpretation += "Interpretation: Strong evidence for " + chartCurrency + " bullish trend\n";
    }
} else {
    skewnessDiffInterpretation = "Insufficient Bayesian Evidence:\n";
    skewnessDiffInterpretation += "Probability Differential: " + DoubleToStr(skewnessProbDiff, 4) + "\n";
}


// Calculate Z-scores and populate analysis array
CurrencyAnalysis currencyAnalysis[8];
double allZScores[8];
double zScoreMean = CalculateMean(overallCSI, ArraySize(currencies));
double zScoreStdDev = CalculateStdDev(overallCSI, ArraySize(currencies), zScoreMean);

for (int currencyIndex = 0; currencyIndex < ArraySize(currencies); currencyIndex++) {
    allZScores[currencyIndex] = (overallCSI[currencyIndex] - zScoreMean) / zScoreStdDev;
    currencyAnalysis[currencyIndex].currency = currencies[currencyIndex];
    currencyAnalysis[currencyIndex].zScore = allZScores[currencyIndex];
    currencyAnalysis[currencyIndex].skewness = skewnessHistory[currencyIndex];
    currencyAnalysis[currencyIndex].kurtosis = kurtosisHistory[currencyIndex];
    // Add Bayesian probability for strength
    currencyAnalysis[currencyIndex].strength = DoubleToStr(posteriorProbabilities[currencyIndex], 4); // Assuming you want 4 decimal places
}

// Sort currencies by posterior probability rather than Z-score
string sortedCurrencies[8];
double sortedPosteriorProbabilities[8];
ArrayCopy(sortedCurrencies, currencies);
ArrayCopy(sortedPosteriorProbabilities, posteriorProbabilities);

// Bubble sort for Bayesian probabilities
for (int s = 0; s < ArraySize(sortedCurrencies) - 1; s++) {
    for (int t = 0; t < ArraySize(sortedCurrencies) - s - 1; t++) {
        if (sortedPosteriorProbabilities[t] < sortedPosteriorProbabilities[t + 1]) {
            // Swap probabilities
            double tempProbability = sortedPosteriorProbabilities[t];
            sortedPosteriorProbabilities[t] = sortedPosteriorProbabilities[t + 1];
            sortedPosteriorProbabilities[t + 1] = tempProbability;
            
            // Swap currency names
            string tempCurrency = sortedCurrencies[t];
            sortedCurrencies[t] = sortedCurrencies[t + 1];
            sortedCurrencies[t + 1] = tempCurrency;
            
            // Swap analysis structures
            CurrencyAnalysis tempAnalysis = currencyAnalysis[t];
            currencyAnalysis[t] = currencyAnalysis[t + 1];
            currencyAnalysis[t + 1] = tempAnalysis;
        }
    }
}

// Build currency strength ranking string using Bayesian probabilities
string currencyRanking = "\nCurrency Strength Ranking (Posterior Probabilities):\n";
currencyRanking = currencyRanking + "----------------------------------------\n";
for (int k = 0; k < ArraySize(sortedCurrencies); k++) {
    currencyRanking = currencyRanking + StringFormat("%d. %s: %.4f\n", k + 1, sortedCurrencies[k], sortedPosteriorProbabilities[k]);
}
currencyRanking = currencyRanking + "----------------------------------------\n";

// Example of how the alert and display logic should be synchronized
bool foundOpportunity = false;
string trendOpportunities = "\nPotential Trend Opportunities Based on Bayesian Analysis:\n";
trendOpportunities = trendOpportunities + "----------------------------------------\n";

// Add debug flag for alert sends
bool alertWasSent = false;

// Check top 3 strongest by probability
for (int x = 0; x < 3; x++) {
    for (int y = ArraySize(currencyAnalysis) - 3; y < ArraySize(currencyAnalysis); y++) {
        double probDiff = sortedPosteriorProbabilities[x] - sortedPosteriorProbabilities[y];
        
        if (MathAbs(probDiff) >= 0.1) {
            bool strongSkewnessAligned = (currencyAnalysis[x].skewness > 0);
            bool weakSkewnessAligned = (currencyAnalysis[y].skewness < 0);
            
            if (strongSkewnessAligned && weakSkewnessAligned) {
                foundOpportunity = true;
                string firstCurrency = sortedCurrencies[x];
                string secondCurrency = sortedCurrencies[y];
                
                // Format pair and determine direction
                string pairFormat = FormatPairName(firstCurrency, secondCurrency);
                string tradeDirection = "BUY";

                // Determine direction based on formatted pair
                if (StringSubstr(pairFormat, 0, 3) != firstCurrency) {
                    tradeDirection = "SELL";
                }
                
                // Store the trend information BEFORE sending alert
                trendOpportunities = trendOpportunities + StringFormat("High Probability Trend: %s\n", pairFormat);
                trendOpportunities = trendOpportunities + StringFormat("SIGNAL: %s %s\n", tradeDirection, pairFormat);
                trendOpportunities = trendOpportunities + StringFormat("Probability Differential: %.4f\n", probDiff);
                trendOpportunities = trendOpportunities + StringFormat("Skewness Values: %.4f / %.4f\n", 
                    currencyAnalysis[x].skewness, currencyAnalysis[y].skewness);
                trendOpportunities = trendOpportunities + "----------------------------------------\n";
                
                // Send email alert if enabled and enough time has passed
                if(EnableEmailAlerts && TimeCurrent() >= LastTrendAlertTime + AlertMinutes * 60) {
                    string trendAlertMessage = StringFormat(
                        "Trend Signal Alert\n" +
                        "Pair: %s\n" +
                        "Signal: %s\n" +
                        "Probability Diff: %.4f\n" +
                        "Time: %s",
                        pairFormat,
                        tradeDirection,
                        probDiff,
                        TimeToString(TimeCurrent())
                    );
                    
                    if(SendMail("Trend Signal Alert", trendAlertMessage)) {
                        LastTrendAlertTime = TimeCurrent();
                        alertWasSent = true;
                        Print("Debug: Alert sent and trend info stored: ", pairFormat);
                        
                        // Store this in a global variable to track
                        GlobalVariableSet("LastAlertTime", TimeCurrent());
                        GlobalVariableSet("TrendDisplayNeeded", 1);
                    }
                }
            }
        }
    }
}

// Important: Update trend opportunities if alert was sent
if (foundOpportunity || GlobalVariableGet("TrendDisplayNeeded") == 1) {
    datetime lastAlert = (datetime)GlobalVariableGet("LastAlertTime");
    
    // Keep tracking for a certain period after alert
    if (TimeCurrent() - lastAlert < PeriodSeconds(PERIOD_H1)) {
        if (!foundOpportunity) {  // If no new opportunity, keep existing signals visible
            Print("Debug: Maintaining existing trend signals");
        } else {
            Print("Debug: New trend opportunity found and active");
        }
    } else {
        GlobalVariableSet("TrendDisplayNeeded", 0);  // Reset after display window expires
        trendOpportunities = "No active trend signals.\n";
        trendOpportunities = trendOpportunities + "----------------------------------------\n";
        Print("Debug: Signal display period expired");
    }
} else {
    if (!GlobalVariableGet("TrendDisplayNeeded")) {
        trendOpportunities = "No high-probability trends found based on Bayesian analysis.\n";
        trendOpportunities = trendOpportunities + "Current market conditions suggest consolidation or unclear trends.\n";
        trendOpportunities = trendOpportunities + "----------------------------------------\n";
    }
}

// Debug output
Print("Debug: Alert sent: ", alertWasSent, " Found opportunity: ", foundOpportunity, 
      " Display needed: ", GlobalVariableGet("TrendDisplayNeeded"));


// Declarations for strongest/weakest currencies
double strongestProbability = sortedPosteriorProbabilities[0];
double weakestProbability = sortedPosteriorProbabilities[ArraySize(sortedPosteriorProbabilities)-1];
string strongestCurrency = sortedCurrencies[0];
string weakestCurrency = sortedCurrencies[ArraySize(sortedCurrencies)-1];

// Validation check
if (strongestCurrency == "" || weakestCurrency == "") {
    Print("Warning: Unable to determine strongest/weakest currencies");
    return(0);
}

// Generate mean reversion pairs section
string meanReversionPairs = "\nBest Pairs for Mean Reversion:\n";
meanReversionPairs += "----------------------------------------\n";

// Add global tracking for mean reversion signals
bool meanRevSignalFound = false;
datetime lastMeanRevTime = (datetime)GlobalVariableGet("LastMeanRevTime");

// Create array to store pair analysis results
PairAnalysis pairAnalyses[];
int pairCount = 0;

// Get price histories for all currencies
double currencyPrices[8][20];  // Assuming 20 periods of history
for(int priceIdx = 0; priceIdx < ArraySize(sortedCurrencies); priceIdx++) {
    // Skip if it's USD since we're using USD as the base
    if(sortedCurrencies[priceIdx] == "USD") {
        for(int usdLoop = 0; usdLoop < LOOKBACK_PERIOD; usdLoop++) {
            currencyPrices[priceIdx][usdLoop] = 0;  // Base currency has zero return
        }
        Print("Debug: USD Base currency set to zero returns");
        continue;
    }
    
    // Get the symbol and determine format
    string currentPair = "";
    bool isInverse = false;
    
    if(SymbolExists(sortedCurrencies[priceIdx] + "USD")) {
        currentPair = sortedCurrencies[priceIdx] + "USD";
        isInverse = false;
    } else if(SymbolExists("USD" + sortedCurrencies[priceIdx])) {
        currentPair = "USD" + sortedCurrencies[priceIdx];
        isInverse = true;
    }
    
    if(currentPair == "") {
        Print("Warning: No valid pair found for ", sortedCurrencies[priceIdx]);
        GlobalVariableSet("LastValidPair_" + sortedCurrencies[priceIdx], 0); // Track invalid pairs
        continue;
    }
    
    // Store the last valid pair format for this currency
    GlobalVariableSet("LastValidPair_" + sortedCurrencies[priceIdx], StringToTime(currentPair));
    
    // Get initial benchmark price
    double prices[21];  // One extra for calculating first return
    for(int prIdx = 0; prIdx <= LOOKBACK_PERIOD; prIdx++) {
        prices[prIdx] = iClose(currentPair, PERIOD_H1, prIdx);
        if(isInverse && prices[prIdx] > 0) {
            prices[prIdx] = 1.0 / prices[prIdx];
        }
    }
    
    // Calculate returns relative to previous period
    double returns[20] = {0};
    int validCount = 0; // Renamed from validReturns to avoid conflict

    for(int returnIdx = 0; returnIdx < LOOKBACK_PERIOD; returnIdx++) {
        if(prices[returnIdx] > 0 && prices[returnIdx + 1] > 0) {
            returns[returnIdx] = (prices[returnIdx] - prices[returnIdx + 1]) / prices[returnIdx + 1];
            validCount++;
        }
    }

    // Store the valid return count for debugging
    GlobalVariableSet("ValidReturns_" + sortedCurrencies[priceIdx], validCount);

    // Normalize returns
    if(validCount > 0) {
        double meanReturn = CalculateMean(returns, validCount);
        double stdDev = CalculateStdDev(returns, validCount, meanReturn);
        
        // Store these metrics for persistence and debugging
        GlobalVariableSet("MeanReturn_" + sortedCurrencies[priceIdx], meanReturn);
        GlobalVariableSet("StdDev_" + sortedCurrencies[priceIdx], stdDev);
        
        if(stdDev > 0) {
            for(int normIdx = 0; normIdx < LOOKBACK_PERIOD; normIdx++) {
                currencyPrices[priceIdx][normIdx] = (returns[normIdx] - meanReturn) / stdDev;
            }
        }
    }

    // Enhanced debug output
    Print("Debug: ", sortedCurrencies[priceIdx], 
          " Pair=", currentPair,
          " Returns: Mean=", CalculateMean(returns, validCount),
          " StdDev=", CalculateStdDev(returns, validCount, CalculateMean(returns, validCount)),
          " ValidCount=", validCount,
          " Time=", TimeToString(TimeCurrent()));
}

// Store the time of last price history update
GlobalVariableSet("LastPriceHistoryUpdate", TimeCurrent());

// Calculate and store dynamic thresholds based on market volatility
double dynProbThreshold = CalculateDynamicThreshold(BASE_PROB_THRESHOLD, Symbol(), Period(), 20);
double dynKurtosisThreshold = CalculateDynamicThreshold(BASE_KURTOSIS_THRESHOLD, Symbol(), Period(), 20);
double dynSkewnessThreshold = CalculateDynamicThreshold(BASE_SKEWNESS_THRESHOLD, Symbol(), Period(), 20);

// Store thresholds for persistence and monitoring
GlobalVariableSet("DynProbThreshold", dynProbThreshold);
GlobalVariableSet("DynKurtosisThreshold", dynKurtosisThreshold);
GlobalVariableSet("DynSkewnessThreshold", dynSkewnessThreshold);

// Debug thresholds
Print("Debug: Dynamic Thresholds - Prob:", dynProbThreshold, 
      " Kurtosis:", dynKurtosisThreshold, 
      " Skewness:", dynSkewnessThreshold,
      " Time:", TimeToString(TimeCurrent()));



// Loop through all currency pairs
for (int m = 0; m < ArraySize(sortedCurrencies) - 1; m++) {
    for (int n = m + 1; n < ArraySize(sortedCurrencies); n++) {
        string formattedPair = FormatPairName(sortedCurrencies[m], sortedCurrencies[n]);
        string pairKey = formattedPair;  // Use formatted pair for key
        
        // Get indices in original arrays
        int firstIndex = ArrayFind(currencies, sortedCurrencies[m]);
        int secondIndex = ArrayFind(currencies, sortedCurrencies[n]);
        
        // Validate indices
        if(firstIndex == -1 || secondIndex == -1) {
            Print("Debug: Invalid indices for pair ", formattedPair);
            GlobalVariableSet("InvalidPair_" + pairKey, 1);
            continue;
        }
        
        // Create temporary arrays for the normalized returns
        double returns1[];
        double returns2[];
        ArrayResize(returns1, LOOKBACK_PERIOD);
        ArrayResize(returns2, LOOKBACK_PERIOD);
        
        // Fill the returns arrays and validate data
        bool validReturns = true;
        for(int tempPriceIdx = 0; tempPriceIdx < LOOKBACK_PERIOD; tempPriceIdx++) {
            returns1[tempPriceIdx] = currencyPrices[firstIndex][tempPriceIdx];
            returns2[tempPriceIdx] = currencyPrices[secondIndex][tempPriceIdx];
            
            if(MathAbs(returns1[tempPriceIdx]) < 0.000001 && MathAbs(returns2[tempPriceIdx]) < 0.000001) {
                validReturns = false;
                break;
            }
        }
        
        if(!validReturns) {
    Print("Debug: Invalid returns for pair ", formattedPair);
    GlobalVariableSet("InvalidReturns_" + pairKey, 1);
    continue;
}

// Calculate and store statistical measures
double correlation = CalculateCorrelation(returns1, returns2);
GlobalVariableSet("Correlation_" + pairKey, correlation);

if(MathAbs(correlation) <= 0.000001) {
    Print("Debug: Low correlation for pair ", formattedPair, ": ", correlation);
    continue;
}

double cointegrationScore = TestCointegration(returns1, returns2);
GlobalVariableSet("Cointegration_" + pairKey, cointegrationScore);

if(MathAbs(cointegrationScore) <= 0.000001) {
    Print("Debug: Poor cointegration for pair ", formattedPair, ": ", cointegrationScore);
    continue;
}

// Calculate and store spread metrics
double pairSpread[];
ArrayResize(pairSpread, LOOKBACK_PERIOD);
for(int spreadIdx = 0; spreadIdx < LOOKBACK_PERIOD; spreadIdx++) {
    pairSpread[spreadIdx] = returns1[spreadIdx] - returns2[spreadIdx];
}

double halfLife = CalculateHalfLife(pairSpread);
GlobalVariableSet("HalfLife_" + pairKey, halfLife);

if(halfLife <= 0 || halfLife > 100) {
    Print("Debug: Invalid half-life for pair ", formattedPair, ": ", halfLife);
    continue;
}

// Calculate and store differences
double probabilityDifference = MathAbs(sortedPosteriorProbabilities[m] - sortedPosteriorProbabilities[n]);
double kurtosisDiff = MathAbs(kurtosisHistory[firstIndex] - kurtosisHistory[secondIndex]);
double skewnessDiff = MathAbs(skewnessHistory[firstIndex] - skewnessHistory[secondIndex]);

GlobalVariableSet("ProbDiff_" + pairKey, probabilityDifference);
GlobalVariableSet("KurtosisDiff_" + pairKey, kurtosisDiff);
GlobalVariableSet("SkewnessDiff_" + pairKey, skewnessDiff);

// Debug statistics
Print("Debug: Analyzing pair ", formattedPair);
Print("Debug: Metrics - Corr:", correlation, " Coint:", cointegrationScore, " HL:", halfLife, " ProbDiff:", probabilityDifference);
Print("Debug: Thresholds - ProbThresh:", dynProbThreshold, " KurtThresh:", dynKurtosisThreshold, " SkewThresh:", dynSkewnessThreshold);

// Check pair criteria and store signal information
if (probabilityDifference < dynProbThreshold &&
    kurtosisDiff < dynKurtosisThreshold &&
    skewnessDiff < dynSkewnessThreshold &&
    correlation > 0.7 &&
    halfLife > 1 && halfLife < 20 &&
    cointegrationScore < -2.5) {
    
    Print("Debug: Mean reversion criteria met for pair ", formattedPair);
    meanRevSignalFound = true;
    GlobalVariableSet("LastMeanRevTime", TimeCurrent());
    GlobalVariableSet("MeanRevDisplayNeeded", 1);
    Print("Debug: Mean reversion display flags set");
    
    // Calculate and store weighted score
    double totalScore = (probabilityDifference * 2.0) +
                      (kurtosisDiff / 2.0) +
                      (skewnessDiff / 2.0) +
                      ((1.0 - correlation) * 1.5) +
                      (halfLife / 20.0) +
                      (MathAbs(cointegrationScore) / 5.0);
    
    GlobalVariableSet("TotalScore_" + pairKey, totalScore);
    Print("Debug: Total score calculated:", totalScore);
    
    // Calculate and store z-score
    double spreadMean = CalculateMean(pairSpread, LOOKBACK_PERIOD);
    double spreadStdDev = CalculateStdDev(pairSpread, LOOKBACK_PERIOD, spreadMean);
    double zScore = spreadStdDev > 0 ? (pairSpread[0] - spreadMean) / spreadStdDev : 0;
    
    GlobalVariableSet("ZScore_" + pairKey, zScore);
    GlobalVariableSet("SpreadMean_" + pairKey, spreadMean);
    GlobalVariableSet("SpreadStdDev_" + pairKey, spreadStdDev);
    Print("Debug: Z-Score calculated:", zScore);
    
    // Determine and store signal
    string signal = "NO SIGNAL";
    if(MathAbs(zScore) >= 2.0) {
        signal = (zScore > 0) ? 
            "SELL " + formattedPair :
            "BUY " + formattedPair;
        
        Print("Debug: Trade signal generated:", signal);
        
        // Store signal information
        GlobalVariableSet("LastMeanRevPair1", StringToDouble(sortedCurrencies[m]));
        GlobalVariableSet("LastMeanRevPair2", StringToDouble(sortedCurrencies[n]));
        GlobalVariableSet("LastMeanRevSignal", StringToTime(signal));
        GlobalVariableSet("LastMeanRevZScore", zScore);
        GlobalVariableSet("LastMeanRevTotalScore", totalScore);
        Print("Debug: Signal information stored in global variables");
                
 // Handle alerts
                if(EnableEmailAlerts && TimeCurrent() >= LastMeanRevAlertTime + AlertMinutes * 60) {
                    string meanRevAlertMessage = StringFormat(
                        "Mean Reversion Signal Alert\n" +
                        "Pair: %s\n" +
                        "Signal: %s\n" +
                        "Z-Score: %.4f\n" +
                        "Correlation: %.4f\n" +
                        "Half-Life: %.2f\n" +
                        "Total Score: %.4f\n" +
                        "Time: %s",
                        formattedPair,
                        signal,
                        zScore,
                        correlation,
                        halfLife,
                        totalScore,
                        TimeToString(TimeCurrent())
                    );
                    
                    if(SendMail("Mean Reversion Signal Alert", meanRevAlertMessage)) {
                        LastMeanRevAlertTime = TimeCurrent();
                        GlobalVariableSet("LastMeanRevAlertTime", LastMeanRevAlertTime);
                        Print("Debug: Mean reversion email alert sent successfully");
                    }
                }
            }
            
            GlobalVariableSet("Signal_" + pairKey, StringToTime(signal));
            
            // Debug qualified pair
            Print("Debug: Qualified pair complete processing");
            Print("Debug: Pair=", formattedPair,
                  " Score=", totalScore,
                  " Signal=", signal,
                  " Time=", TimeToString(TimeCurrent()));
            
            // Add to analysis array
            ArrayResize(pairAnalyses, pairCount + 1);
            pairAnalyses[pairCount].currency1 = sortedCurrencies[m];
            pairAnalyses[pairCount].currency2 = sortedCurrencies[n];
            pairAnalyses[pairCount].correlation = correlation;
            pairAnalyses[pairCount].halfLife = halfLife;
            pairAnalyses[pairCount].cointegrationScore = cointegrationScore;
            pairAnalyses[pairCount].probabilityDiff = probabilityDifference;
            pairAnalyses[pairCount].totalScore = totalScore;
            pairAnalyses[pairCount].signalType = signal;
            pairAnalyses[pairCount].currentDeviation = zScore;
            pairCount++;
            Print("Debug: Added to analysis array, current pair count:", pairCount);
        }
    }
}
// Sort pairs by total score - this part is correct, no changes needed
bool sortedPairsExist = false;
if(pairCount > 0) {
    sortedPairsExist = true;
    for(int sortI = 0; sortI < pairCount - 1; sortI++) {
        for(int sortJ = 0; sortJ < pairCount - sortI - 1; sortJ++) {
            if(pairAnalyses[sortJ].totalScore > pairAnalyses[sortJ+1].totalScore) {
                PairAnalysis temp = pairAnalyses[sortJ];
                pairAnalyses[sortJ] = pairAnalyses[sortJ+1];
                pairAnalyses[sortJ+1] = temp;
            }
        }
    }
}

// Prepare mean reversion display
string meanReversionDisplay = "\nBest Pairs for Mean Reversion:\n";
meanReversionDisplay = meanReversionDisplay + "----------------------------------------\n";

// Check for persistent signals first
bool persistentSignalExists = (GlobalVariableGet("MeanRevDisplayNeeded") == 1);
Print("Debug: Mean Rev Display Needed:", persistentSignalExists);

if(persistentSignalExists || meanRevSignalFound) {
    datetime lastSignal = (datetime)GlobalVariableGet("LastMeanRevTime");
    Print("Debug: Last Mean Rev Signal Time:", TimeToString(lastSignal));
    Print("Debug: Current Time:", TimeToString(TimeCurrent()));
    
    if(TimeCurrent() - lastSignal < PeriodSeconds(PERIOD_H1)) {  // Keep showing for 1 hour
        meanReversionDisplay = meanReversionDisplay + "\nActive Mean Reversion Signals:\n";
        string storedPair1 = DoubleToString(GlobalVariableGet("LastMeanRevPair1"));
        string storedPair2 = DoubleToString(GlobalVariableGet("LastMeanRevPair2"));
        
        // Update this section to use FormatPairName
        string formattedStoredPair = FormatPairName(storedPair1, storedPair2);
        Print("Debug: Displaying signal for pair:", formattedStoredPair);
        
        meanReversionDisplay = meanReversionDisplay + StringFormat(
            "===========================================\n" +
            "ACTIVE SIGNAL ALERT\n" +
            "===========================================\n" +
            "Pair: %s\n" +
            "Signal Time: %s\n" +
            "Z-Score: %.4f\n" +
            "Total Score: %.4f\n" +
            "===========================================\n",
            formattedStoredPair,
            TimeToString(lastSignal),
            GlobalVariableGet("LastMeanRevZScore"),
            GlobalVariableGet("LastMeanRevTotalScore")
        );
        Print("Debug: Signal display constructed");
    } else {
        GlobalVariableSet("MeanRevDisplayNeeded", 0);
        GlobalVariableSet("LastMeanRevPair1", 0);
        GlobalVariableSet("LastMeanRevPair2", 0);
        Print("Debug: Signal display period expired - resetting globals");
    }
}

// Output current top 3 pairs if any found
if(sortedPairsExist) {
    meanReversionDisplay = meanReversionDisplay + "\nCurrent Top Mean Reversion Pairs:\n";
    for(int outputIdx = 0; outputIdx < MathMin(3, pairCount); outputIdx++) {
        // Store top pairs for persistence
        string topPairKey = "TopPair_" + IntegerToString(outputIdx);
        GlobalVariableSet(topPairKey + "_Currency1", StringToTime(pairAnalyses[outputIdx].currency1));
        GlobalVariableSet(topPairKey + "_Currency2", StringToTime(pairAnalyses[outputIdx].currency2));
        GlobalVariableSet(topPairKey + "_Score", pairAnalyses[outputIdx].totalScore);
        GlobalVariableSet(topPairKey + "_Signal", StringToTime(pairAnalyses[outputIdx].signalType));
        
        string formattedAnalysisPair = FormatPairName(pairAnalyses[outputIdx].currency1, pairAnalyses[outputIdx].currency2);
        
        meanReversionDisplay = meanReversionDisplay + StringFormat(
            "\n%d. %s\n" +
            "Correlation: %.4f\n" +
            "Half-life: %.2f periods\n" +
            "Cointegration Score: %.4f\n" +
            "Probability Difference: %.4f\n" +
            "Current Deviation: %.2f std\n" +
            "Signal: %s\n" +
            "Total Score: %.4f\n" +
            "Time: %s\n" +
            "----------------------------------------\n",
            outputIdx+1,
            formattedAnalysisPair,
            pairAnalyses[outputIdx].correlation,
            pairAnalyses[outputIdx].halfLife,
            pairAnalyses[outputIdx].cointegrationScore,
            pairAnalyses[outputIdx].probabilityDiff,
            pairAnalyses[outputIdx].currentDeviation,
            pairAnalyses[outputIdx].signalType,
            pairAnalyses[outputIdx].totalScore,
            TimeToString(TimeCurrent())
        );
    }
} else if(!persistentSignalExists) {
    meanReversionDisplay = meanReversionDisplay + "\nNo suitable pairs for mean reversion found.\n";
    meanReversionDisplay = meanReversionDisplay + "Current market conditions do not meet mean reversion criteria.\n";
    meanReversionDisplay = meanReversionDisplay + "----------------------------------------\n";
}
meanReversionPairs = meanReversionDisplay;

// Update Comment with all information
string displayText = StringFormat(
    "\nCurrency Strength Analysis:\n" +
    "========================================\n" +
    "Strongest Currency: %s (Probability: %.4f)\n" +
    "Weakest Currency: %s (Probability: %.4f)\n" +
    "========================================\n\n" +
    "%s\n" +  // Currency Ranking
    "%s\n" +  // Trend Opportunities
    "%s\n" +  // Mean Reversion Pairs
    "Selected Currency Analysis:\n" +
    "========================================\n" +
    "Base Currency: %s\n\n" +
    "Interpretations for %s:\n" +
    "----------------------------------------\n" +
    "%s\n\n" +  // Skewness Interpretation
    "%s\n",      // Kurtosis Interpretation
    strongestCurrency, strongestProbability,
    weakestCurrency, weakestProbability,
    currencyRanking,
    trendOpportunities,
    meanReversionPairs,
    BaseCurrency,
    BaseCurrency,
    skewnessInterpretation,
    kurtosisInterpretation
);

// Add chart currency analysis if different from base
if(BaseCurrency != chartCurrency) {
    displayText += StringFormat(
        "\nPair Analysis:\n" +
        "========================================\n" +
        "Interpretations for %s:\n" +
        "----------------------------------------\n" +
        "%s\n\n" +  // Chart Currency Skewness
        "%s\n\n" +  // Chart Currency Kurtosis
        "Comparative Analysis:\n" +
        "----------------------------------------\n" +
        "%s\n\n" +  // Kurtosis Diff
        "%s\n",      // Skewness Diff
        chartCurrency,
        chartCurrencySkewnessInterpretation,
        chartCurrencyKurtosisInterpretation,
        kurtosisDiffInterpretation,
        skewnessDiffInterpretation
    );
} else {
    displayText += "\nSame currency selected - no additional analysis needed\n";
}

// Add tracking information
displayText += StringFormat(
    "\n========================================\n" +
    "Tracking Information:\n" +
    "----------------------------------------\n" +
    "Strongest Currency Since: %s\n" +
    "Weakest Currency Since: %s\n" +
    "Last Update: %s\n" +
    "========================================\n",
    timeStrongest,
    timeWeakest,
    TimeToString(TimeCurrent())
);

Comment(displayText);

// Store last update time
GlobalVariableSet("LastUpdateTime", TimeCurrent());

return(0);
}  // Closing brace for OnCalculate function
