********************************************************************************
*** Generate a pack of auxiliary files to cleanse Orbis data
********************************************************************************
*** Main inputs: API_NY.GDP.DEFL.ZS_DS2_en_csv_v2_2252266.csv, API_NY.GDP.MKTP.CD_DS2_en_csv_v2_2445719.csv,
*API_NE.GDI.TOTL.CD_DS2_en_csv_v2_2597372.csv
*** Additional inputs: Finan_"${countrycode}"_USD_clean, 
*** Output: country_deflator.dta
*** Aditional output: 
*** Author: Nicolas Oviedo
*** Original: 08/12/2021
*** Code: 
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
log using "$temp/Orbis_aux.txt", replace

di "We start building auxiliary files for ${country}" 

********************************************************************************	
* -------------      Set country and directories       -------------------------
********************************************************************************
*Set country name and code
*global country = ""
*global ccode   = ""
//Check full table in pathdata_raw/LC/step1/country_list_name_USD.dta

*Create country directories
cd "$figures"
mkdir $country, public

cd "$output_data"
mkdir $country, public
global output_data "$pathinit/outputs/microdata/surveys/${country}"

cd "$aux"

********************************************************************************	
*** Country deflators
********************************************************************************
*Find correspondence between Orbis and World Bank country codes
import excel using country_list.xlsx, clear
ren A country
ren B code
ren C wbcode
ren D iso
keep if code == "$ccode"
global wbcode = wbcode[1]

*Import and clean World Bank data
import delimited using API_NY.GDP.DEFL.ZS_DS2_en_csv_v2_2252266.csv, clear
drop in 1/2
foreach var of varlist _all{
	local value = `var'[1]
    local vname = strtoname(`"`value'"')
    rename `var' date`vname'
    label var date`vname' `"`value'"'
}
drop in 1
drop dateIndicator_Code dateIndicator_Name
ren dateCountry_Name country
ren dateCountry_Code countrycode
drop if countrycode ~= "$wbcode"
reshape long date,  i(countrycode) j(year,string)
drop in 1
ren date deflator
replace year = substr(year, 2, 4)
destring(year), replace

*Generate a deflator index
sort year
tset year
drop if year < 1981
gen deflator_idx = deflator/100

*Generate 2005 base deflator
preserve
keep if year == 2005
local def = deflator[1]
restore
gen deflator2005 = deflator/`def'

save "$output_data/${country}_deflator", replace

********************************************************************************	
*** GDP
********************************************************************************
*Get nominal GDP in USD by World Bank
import delimited using API_NY.GDP.MKTP.CD_DS2_en_csv_v2_2445719.csv, clear
drop in 1/2
foreach var of varlist _all{
	local value = `var'[1]
    local vname = strtoname(`"`value'"')
    rename `var' date`vname'
    label var date`vname' `"`value'"'
}
drop in 1
drop dateIndicator_Code dateIndicator_Name
ren dateCountry_Name country
ren dateCountry_Code countrycode
drop if countrycode ~= "$wbcode"
reshape long date,  i(countrycode) j(year,string)
drop in 1
ren date gdp
replace year = substr(year, 2, 4)
destring(year), replace

*Convert to Euros using PWT exchange rate
merge 1:1 countrycode year using "$pwt/pwt100", keepusing(xr)
drop if _merge == 1 | _merge == 2
drop _merge
drop if year < 1999
gen gdp_euro = gdp*xr

*Deflate
merge 1:1 countrycode year using "$output_data/${country}_deflator.dta", keepusing(deflator_idx)
capture drop if _merge == 2
drop _merge
gen gdp_real = gdp_euro/deflator_idx
label var gdp "GDP in current USD"
label var gdp_euro "GDP in current EUR"
label var deflator "GDP deflator"
label var gdp_real "GDP in 2015 euros"
save "$output_data/${country}_gdp", replace

*Real GDP in USD
gen gdp_real_usd = gdp/deflator_idx
lab var gdp_real_usd "GDP in 2015 USD"
save "$output_data/${country}_gdp", replace

********************************************************************************	
*** Investment - national accounts
********************************************************************************
*Create tempfile for merge
tempfile investes
save `investes', emptyok

*Get World Bank Data in current dollars (gross capital formation)
import delimited using API_NE.GDI.TOTL.CD_DS2_en_csv_v2_2597372.csv, clear
drop in 1/2
foreach var of varlist _all{
	local value = `var'[1]
    local vname = strtoname(`"`value'"')
    rename `var' date`vname'
    label var date`vname' `"`value'"'
}
drop in 1
drop dateIndicator_Code dateIndicator_Name
ren dateCountry_Name country
ren dateCountry_Code countrycode
drop if countrycode ~= "$wbcode"
reshape long date,  i(countrycode) j(year,string)
drop in 1
ren date invest
replace year = substr(year, 2, 4)
destring(year), replace

*Deflate
merge 1:1 countrycode year using "$output_data/${country}_deflator.dta", keepusing(deflator_idx)
capture drop if _merge == 2
drop _merge
gen inv_real_usd = invest/deflator_idx
ren invest invest_usd
lab var invest_usd "Investment in current dollars"
lab var inv_real_usd "Real investment in constant 2015 dollars"
save `investes', replace

*Add to GDP data
use "$output_data/${country}_gdp", clear
merge 1:1 countrycode year using `investes', keepusing(invest_usd inv_real_usd)
drop if _merge == 2
drop _merge
gen irate_usd = invest_usd/gdp
lab var irate_usd "Investment rate using data in USD"

save "$output_data/${country}_gdp", replace
********************************************************************************	
*** EUR-USD exchange rate by Statista
********************************************************************************
import excel using statistic_id606660_media-anual-de-la-tasa-de-cambio-de-euro-a-dolar-estadounidense-1999-2019.xlsx, sheet("Datos") clear
drop in 1/3
ren B year
ren C exchange_rate
lab var exchange_rate "EUR/USD by Statista"
destring year exchange_rate, replace
save "$output_data/eur_usd_xr", replace

di "We finish building auxiliary files for ${country}" 