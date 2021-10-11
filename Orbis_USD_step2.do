********************************************************************************
*** Clean Orbis country data in USD
********************************************************************************
*** Main inputs: Finan_`country code'_USD.dta
*** Additional inputs: API_NY.GDP.DEFL.ZS_DS2_en_csv_v2_2252266.csv
*** Output: `country'_master_usd, DataDescription`country code'_USD.xlsx, Finan_`country code'_USD_clean.dta
*** Aditional output: `country'_deflator.dta
*** Author: Nicolas Oviedo
*** Original: 08/12/2021
*** Code: This code cleanses Orbis country data in USD
********************************************************************************
*** Set up
********************************************************************************
cls
query memory
set more off
********************
*User Settings
********************
*User: andres
*global who = "A" 

*User: Isaac
//global who = "I" 

*User: Nicolas
global who = "N" 

********************************************************************************	
* -------------         Paths and Logs            ------------------------------
********************************************************************************
if "$who" == "N"  {
		global pathinit "D:\Data"
 		global pathdata_raw "D:\Data\inputs\microdata\amadeus"
}

if "$who" == "N"  {
global input_data "$pathinit\inputs\microdata\amadeus\step2"
global output_data "$pathinit/outputs/microdata/surveys"
global figures "$pathinit/figures"
global temp "$pathinit/temp"
global aux "$pathinit\inputs\aux_files"
}

capture log close
log using "$temp/Orbis_step2.txt", replace

di "We start step 2 for ${country}" 
********************************************************************************	
* -------------      Set country and directories       -------------------------
********************************************************************************
*Set country name and code
*global country = ""
*global ccode   = ""
//Check full table in pathdata_raw/step1/country_list_name_USD.dta

*Create country directories
cd "$output_data"
capture mkdir $country, public
global output_data "$pathinit/outputs/microdata/surveys/${country}"

cd "$figures"
capture mkdir $country, public

cd "$input_data"

********************************************************************************	
*** Load and compress
********************************************************************************
use Finan_${ccode}_USD.dta, clear
compress

********************************************************************************	
*** Create Excel to keep track of deleted observations
********************************************************************************
putexcel set "$output_data/DataDescription${ccode}_USD.xlsx", sheet("${ccode}") replace

qui putexcel A2 =("Observations")
global obs = _N
qui putexcel B2 = $obs

********************************************************************************	
*** Year
********************************************************************************
drop if closingdate == .
//Generate actual year based on closing date. If report is before June, observation is imputted to previous year
gen year = int(closingdate/10000)
gen closingmonth = floor(mod(closingdate, 10000)/100)
replace year = year - 1 if closingmonth < 6
drop closingmonth
order year, before(consolidationcode)

//Description of time period, number of firms and number of observations
qui putexcel A3 =("Start year")
qui	sum year
local  Start_date=r(min)
qui putexcel B3=(`r(min)') //
qui putexcel A4 =("End year")
local  End_date=r(max)
qui putexcel B4=(`r(max)') //
by id, sort: gen nvals = _n == 1
count if nvals
qui putexcel A5=("Number of firms")
qui putexcel B5=(`r(N)')
qui putexcel A6 =("Number of observations")
qui putexcel B6 = _N

//Drop observations before 1999 to obtain unbiased sample
drop if year < 1999
qui putexcel A9 = ("Observations before 1999")
qui putexcel B9 = (`r(N_drop)')
count if nvals
qui putexcel A10=("Firms since 1999")
qui putexcel B10 = (`r(N)')

drop nvals

********************************************************************************	
*** Consolidation codes
********************************************************************************
/*	C2: consolidated account of hq + all subsidiaries, hq reports unconsolidated
	C1: consolidated of group, hq does not report unconsolidated
	U2: unconsolidated of company with companion consolidated account
	U1: unconsolidated account of company with no consolidation
	C2 = U2 */

//Compute number of firm-year obs with duplicate accounts
duplicates report id year
qui putexcel A12=("Unique firm year observations")
qui putexcel B12=(`r(unique_value)')

//Now identify under which consolidation code do firm ids repeat
sort id year
gen repeticion = "."
bysort id year : replace repeticion = consolidationcode if (_n == 1)
bysort id year : replace repeticion = repeticion[_n-1] + "&" + consolidationcode if _n > 1
bysort id year : replace repeticion = repeticion[_N]
by id: gen miss = 1 if (sales == . | numberofemployees == .)
gen codemiss = consolidationcode if miss == 1
foreach code in C1 C2{
	bysort id consolidationcode: egen tmiss_`code' = sum(miss)
	by id consolidationcode: gen count_`code' = _N if consolidationcode == "`code'"
	bysort id: egen mean_`code' = mean(count_`code')
	replace count_`code' = mean_`code' if count_`code' == .
}

//Delete duplicates with same id, year and consolidation code
*duplicates report id year consolidationcode
duplicates tag id year consolidationcode, gen(dup_id)
gsort id year consolidationcode -dup_id -miss numberofmonths // Criteria: missing critical variable, if not with less months reported
by id year consolidationcode: drop if (dup_id == 1 & _n == 1)
by id year consolidationcode: drop if (dup_id == 2 & _n == 1 | _n==2)

//Keep consolidated accounts to avoid duplication (C >> U)
bysort id year : drop if consolidationcode == "U2" & strpos(repeticion,"U2")>0 & strpos(repeticion,"C2")>0
bysort id year : drop if consolidationcode == "U1" & strpos(repeticion,"U1")>0 & strpos(repeticion,"C1")>0

bysort id year : drop if consolidationcode == "U2" & strpos(repeticion,"U2")>0 & strpos(repeticion,"C1")>0
bysort id year : drop if consolidationcode == "U1" & strpos(repeticion,"U1")>0 & strpos(repeticion,"C2")>0

//If there are C1 and C2 entries, keep the one with less critical missing values or the longest time series
bysort id year: drop if consolidationcode == "C1" & strpos(repeticion,"C1")>0 & strpos(repeticion,"C2")>0 & (tmiss_C1 > tmiss_C2 | count_C2 > count_C1)
bysort id year: drop if consolidationcode == "C2" & strpos(repeticion,"C2")>0 & strpos(repeticion,"C1")>0 & (tmiss_C2 > tmiss_C1 | count_C1 > count_C2)
bysort id year: drop if consolidationcode == "C1" & strpos(repeticion,"C1")>0 & strpos(repeticion,"C2")>0 & (tmiss_C1 == tmiss_C2 | count_C2 == count_C1)
// Tie break: keep C2

//Should there coexist U2 and U1, drop U2 -> unlikely because U2 = C2
bysort id year : drop if consolidationcode == "U2" & strpos(repeticion,"U2")>0 & strpos(repeticion,"U1")>0

//Check if there is any duplicate left
by id year: drop if _n > 1
*duplicates report id year

//To maximize info, we are allowing a given id to have different consolidation codes in different years
drop repeticion-dup_id

********************************************************************************	
*** Units of measure
********************************************************************************
//Check if there is any currency other than euro
drop if originalcurrency == "." 
qui putexcel A14 =("Observations without currency")
qui putexcel B14 = `r(N_drop)'
count if originalcurrency ~= "EUR"
/*by id: drop if originalcurrency ~= "EUR"
qui putexcel A14 =("Observations without currency")
qui putexcel B14 = `r(N_drop)'*/

//Check if there are discrete jumps in units of measures and drop inconsistencies
bysort id year: gen unitjump = 1 if originalunits ~= originalunits[_n - 1] & _n ~= 1
count if unitjump == 1
sort id
by id: gen jump = totalassets/totalassets[_n-1] if unitjump == 1
by id: gen assetgrowth = totalassets/totalassets[_n-1] if unitjump == 1
*by id: egen salto = sum(unitjump)

// Flag asset variation much higher than implied by change of units
gen flag = .
//Units <> Thousands
replace flag = 1 if unitjump == 1 & originalunits == "units" & originalunits[_n-1] == "thousands" & assetgrowth > 0.002
replace flag = 1 if unitjump == 1 & originalunits == "thousands" & originalunits[_n-1] == "units" & assetgrowth > 2000
//Units <> Millions
replace flag = 1 if unitjump == 1 & originalunits == "units" & originalunits[_n-1] == "millions" & assetgrowth > 0.000002
replace flag = 1 if unitjump == 1 & originalunits == "millions" & originalunits[_n-1] == "units" & assetgrowth > 2000000
//Millions <> Thousands
replace flag = 1 if unitjump == 1 & originalunits == "thousands" & originalunits[_n-1] == "millions" & assetgrowth > 0.002
replace flag = 1 if unitjump == 1 & originalunits == "millions" & originalunits[_n-1] == "thousands" & assetgrowth > 2000

replace flag = 1 if flag > 0 & flag ~= .
local flagship = sum(flag)
qui putexcel A20 =("Firms with units inconsistencies")
qui putexcel B20 = `flagship'

//Drop flagged firms
bysort id (year) : drop if flag == 1

capture drop unitjump-flag

********************************************************************************	
*** Convert to real dollars
********************************************************************************
//Import country deflator
merge m:1 year using "$output_data/${country}_deflator", keepusing(deflator_idx)
capture drop if _merge == 2
drop _merge

//Deflate all financial variables
preserve
drop id - exchangeratefromoriginalcurrency
ds, has(type double long)
restore
foreach var of varlist `r(varlist)'{
	replace `var' = `var'/deflator_idx
}
drop deflator_idx

compress
save "$output_data/Finan_${ccode}_USD_clean", replace

********************************************************************************	
*** Drop observations missing key data
********************************************************************************
putexcel set "$output_data/DataDescription${ccode}_USD.xlsx", sheet("$ccode") modify
use "$output_data/Finan_${ccode}_USD_clean", clear
drop if totalassets == . & operatingrevenue == . & sales == . & numberofemployees == .
qui putexcel A17 =("Obs. missing key data")
qui putexcel B17 = `r(N_drop)'

sort id
by id: drop if totalassets < 0
qui putexcel A18 =("Obs. with negative assets")
qui putexcel B18 = `r(N_drop)'

by id: drop if numberofemployees < 0
qui putexcel A19 =("Obs. with negative labor")
qui putexcel B19 = `r(N_drop)'

by id: drop if numberofemployees > 2000000 & numberofemployees ~= . //Drop firms with more employees than Wal-Mart and missing values
//We are keeping firms with missing values in labor
qui putexcel A15 =("Firms with more labor than Wal-Mart")
qui putexcel B15 = `r(N_drop)'

by id: drop if sales < 0
qui putexcel A21 =("Obs. with negative sales")
qui putexcel B21 = `r(N_drop)'

scalar define a = 0
foreach var in totalassets sales{
	gen `var'm = `var'/1000000
	gen emp`var'm = numberofemployees/`var'
	replace emp`var'm = 0 if emp`var'm == .
	egen ip99`var' = pctile(emp`var'm), p(99.9)
	by id: drop if emp`var'm > ip99`var' & emp`var'm ~=.
	scalar define a = a + `r(N_drop)'
}
di a
qui putexcel A22 = ("Employment outliers")
qui putexcel B22 = a

gen salestoassets = sales/totalassets
replace salestoassets = 0 if salestoassets == .
egen ip99salestoassets = pctile(salestoassets), p(99.9)
by id: drop if salestoassets > ip99salestoassets
qui putexcel A23 =("Obs. with sales to assets in 99.9 percentile")
qui putexcel B23 = `r(N_drop)'

by id: drop if tangiblefixedassets < 0
qui putexcel A24 =("Obs. with negative tangible assets")
qui putexcel B24 = `r(N_drop)'

drop totalassetsm-ip99salestoassets

compress
save "$output_data/Finan_${ccode}_USD_clean", replace

********************************************************************************	
*** Gopinath et al. 2017
********************************************************************************
putexcel set "$output_data/DataDescription${ccode}_USD.xlsx", sheet("$ccode") modify
use "$output_data/Finan_${ccode}_USD_clean", clear

//Cleaning of basic reporting mistakes
*drop if numberofemployees ~= .
drop if operatingrevenueturnover <= 0
*drop if operatingrevenueturnover == .
qui putexcel A26 =("Gopinath et al. 2017")
qui putexcel A27 = ("Negative operating revenue")
qui putexcel B27 = `r(N_drop)'

drop if totalassets == .  
qui putexcel A28 = ("Missing total assets")
qui putexcel B28 = `r(N_drop)'

drop if materialcosts <= 0
*drop if materialcosts == .
qui putexcel A29 = ("Missing or negative material costs")
qui putexcel B29 = `r(N_drop)'

//Internal consistency of balance sheet information
gen ratio1 = (intangiblefixedassets + tangiblefixedassets + otherfixedassets)/fixedassets
gen ratio2 = (stock + debtors + othercurrentassets)/currentassets
gen ratio3 = (fixedassets + currentassets)/totalassets
gen ratio4 = (capital + othershareholdersfunds)/shareholdersfunds
gen ratio5 = (longtermdebt + othernoncurrentliabilities)/noncurrentliabilities
gen ratio6 = (loans + creditors + othercurrentliabilities)/currentliabilities
gen ratio7 = (noncurrentliabilities + currentliabilities + shareholdersfunds)/totalsharehfundsliab

scalar define b = 0
foreach rat in ratio1 ratio2 ratio3 ratio4 ratio5 ratio6 ratio7{
	egen `rat'_p99 = pctile(`rat'), p(99.9)
	egen `rat'_p1  = pctile(`rat'), p(0.1)
	drop if (`rat' > `rat'_p99 |`rat' < `rat'_p1 ) & `rat'~= .
	scalar define b = b + `r(N_drop)'
}
di b
qui putexcel A30 = ("Ratio outliers")
qui putexcel B30 = b

drop ratio*
save "$output_data/Finan_${ccode}_USD_clean", replace

//Further quality checks
putexcel set "$output_data/DataDescription${ccode}_USD.xlsx", sheet("$ccode") modify
use "$output_data/Finan_${ccode}_USD_clean", clear

gen liab = totalsharehfundsliab - shareholdersfunds
drop if liab <= 0
qui putexcel A31 = ("Negative inputted liabilities")
qui putexcel B31 = `r(N_drop)'

gen liab_ratio = liab/(currentliabilities + noncurrentliabilities)
drop if (liab_ratio > 1.1 | liab_ratio < 0.9) & liab_ratio ~=.
qui putexcel A32 = ("Inconsistent liabilities")
qui putexcel B32 = `r(N_drop)'

drop if currentliabilities < 0 | noncurrentliabilities < 0 | currentassets < 0 | loans < 0 | creditors < 0 | longtermdebt < 0
qui putexcel A33 = ("Negative assets or liabilities")
qui putexcel B33 = `r(N_drop)'

drop if longtermdebt > (currentliabilities + noncurrentliabilities) & longtermdebt ~=. & currentliabilities ~= . & noncurrentliabilities ~=.
qui putexcel A34 = ("Long term debt inconsistencies")
qui putexcel B34 = `r(N_drop)'

save "$output_data/Finan_${ccode}_USD_clean", replace

/*
gen networth = totalassets - (currentliabilities + noncurrentliabilities)
drop if networth ~= shareholdersfunds & (shareholdersfunds ~= . | networth ~=.)
qui putexcel A35 = ("Net worth inconsistencies")
qui putexcel B35 = `r(N_drop)'
*/
putexcel set "$output_data/DataDescription${ccode}_USD.xlsx", sheet("$ccode") modify
use "$output_data/Finan_${ccode}_USD_clean", clear

drop if intangiblefixedassets < 0
qui putexcel A36 = ("Negative intangible fixed assets")
qui putexcel B36 = `r(N_drop)'

gen asset_ratio = tangiblefixedassets/totalassets
drop if asset_ratio > 1 & asset_ratio ~= .
qui putexcel A37 = ("Share of tangible assets > 100%")
qui putexcel B37 = `r(N_drop)'

drop if depreciationamortization < 0
qui putexcel A38 = ("Negative depreciation")
qui putexcel B38 = `r(N_drop)'

gen capital_f = tangiblefixedassets + intangiblefixedassets
gen cap_ratio = capital_f/costsofemployees
egen cap_ratio_p1  = pctile(cap_ratio), p(0.01)
egen cap_ratio_p99 = pctile(cap_ratio), p(99.9)
drop if (cap_ratio < cap_ratio_p1 | cap_ratio > cap_ratio_p99) & cap_ratio ~= .
qui putexcel A39 = ("Capital-Labor outliers")
qui putexcel B39 = `r(N_drop)'

drop if shareholdersfunds < 0
qui putexcel A40 = ("Negative shareholders funds")
qui putexcel B40 = `r(N_drop)'

gen  equity     = shareholdersfunds/totalassets
egen equity_p1  = pctile(cap_ratio), p(0.01)
drop if equity < equity_p1
qui putexcel A41 = ("Equity outliers")
qui putexcel B41 = `r(N_drop)'

save "$output_data/Finan_${ccode}_USD_clean", replace

gen leverage1	= tangiblefixedassets/shareholdersfunds
gen leverage2	= totalassets/shareholdersfunds
scalar define c = 0
foreach lev in leverage1 leverage2{
	egen `lev'_p99 = pctile(`lev'), p(99.9)
	egen `lev'_p1  = pctile(`lev'), p(0.1)
	drop if (`lev' > `lev'_p99 |`lev' < `lev'_p1 ) & `lev'~= .
	scalar define c = c + `r(N_drop)'	
}
di c
qui putexcel A42 = ("Leverage outliers")
qui putexcel B42 = c

gen va = operatingrevenueturnover - materialcosts
drop if va < 0
qui putexcel A43 = ("Negative value added")
qui putexcel B43 = `r(N_drop)'

gen va_wage = costsofemployees/va
egen va_wage_p99 = pctile(va_wage), p(99)
egen va_wage_p1  = pctile(va_wage), p(1)
drop if (va_wage > va_wage_p99 | va_wage < va_wage_p1) & va_wage ~=.
qui putexcel A44 = ("Wage to value added outliers")
qui putexcel B44 = `r(N_drop)'

drop if va_wage > 1.1 & va_wage ~=.
qui putexcel A45 = ("Wages exceeding value added")
qui putexcel B45 = `r(N_drop)'

drop if costsofemployees < 0
qui putexcel A46 = ("Negative wages")
qui putexcel B46 = `r(N_drop)'

drop liab liab_ratio asset_ratio capital_f cap_ratio_* equity equity_p1 leverage* va va_wage*

count
qui putexcel A48 =("Remaining observations")
qui putexcel B48 = `r(N)'

save "$output_data/Finan_${ccode}_USD_clean", replace

********************************************************************************	
*** Winsorization
********************************************************************************
/*
gen liabilities = noncurrentliabilities + othernoncurrentliabilities + currentliabilities + othercurrentliabilities
winsor2 addedvalue tangiblefixedassets costsofemployees operatingrevenueturnover materialcosts, replace cuts(1, 99)
winsor2 totalassets shareholdersfunds fixedassets otherfixedassets  liabilities, replace cuts(1, 99)
drop liabilities
*/
********************************************************************************	
*** Country master
********************************************************************************
use "$output_data/Finan_${ccode}_USD_clean", clear

ren id id_firm
ren numberofemployees labor
ren costsofemployees wage_bill
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
ren depreciationamortization depreciation

//Gen investment
sort id_firm year
by id_firm: gen inv_total = capital_f - capital_f[_n-1] + depreciation[_n-1] if _n > 1
*winsor2 capital_f, replace cuts(1, 99)
by id_firm: gen gapyear = year - year[_n-1] if _n > 1
replace inv_total = inv_total/gapyear

order id_firm year labor wage_bill sales capital_f inv_total country
drop consolidationcode - gapyear
compress
save "$output_data/${country}_master_usd", replace

di "We finish step 2 for ${country}" 
