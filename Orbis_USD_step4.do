********************************************************************************
*** Cross-checks for Orbis data
********************************************************************************
*** Main inputs: nama_10_gdp_1_Data.csv, nama_10_pe_1_Data.csv
*** Additional inputs: ${country}_master_usd.dta, Finan_${ccode}_USD_clean.dta
*** Output: various .png, .tex, ${country}_eur.dta
*** Author: Nicolas Oviedo
*** Original: 08/17/2021
*** Code: This code compares country data with respect to Eurostat
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
		global sep="/"
}

if "$who" == "A"  {
	
		global pathinit "/Users/jablanco/Dropbox (University of Michigan)/papers_new/LumpyTaxes/Data"
 		global pathdata_raw "/Users/jablanco/Dropbox (University of Michigan)/papers_new/LumpyTaxes/Data"	
		global sep="/"
}

if "$who" == "N"  {
global input_data "$pathinit\inputs\microdata\amadeus\step2"
global output_data "$pathinit/outputs"
global figures "$pathinit/figures/${country}"
global temp "$pathinit/temp"
global aux "$pathinit\inputs\aux_files\Eurostat"
global pwt "C:\Users\Ovi\Desktop\R.A\Data\inputs" //Penn World Table location
}

if "$who" == "A"  {
global input_data "${pathinit}${sep}inputs${sep}microdata${sep}amadeus${sep}step2"
global output_data "$pathinit${sep}outputs"
global figures "${pathinit}${sep}figures"
global temp "${pathinit}${sep}Temp"
global aux "${pathinit}${sep}inputs${sep}microdata${sep}amadeus${sep}aux_files"
global pwt "${pathinit}${sep}inputs${sep}PWT"
}

capture log close
log using "${temp}${sep}Orbis_step_4.txt", append

cd "$output_data"

di "We start step 4 for ${country}" 

********************************************************************************	
* -------------      Set country and directories       -------------------------
********************************************************************************
*Set country name and code
*global country = ""
*global ccode   = ""
//Check full table in pathdata_raw/LC/step1/country_list_name_USD.dta

*Set country directories
cd "$figures"
capture mkdir eurostat_check, public
global figures "${pathinit}${sep}figures${sep}${country}${sep}eurostat_check"

global output_data "${pathinit}${sep}outputs${sep}microdata${sep}surveys${sep}${country}"
cd "$output_data"

*******************************************************************************
*** Eurostat country data
*******************************************************************************
*Aggregate wage bill and GDP
insheet using "${aux}${sep}nama_10_gdp_1_Data.csv", clear
keep if geo == "$ccode"
sort  na_item time
drop if value == ":"

split value, parse(,) 
drop value2 
destring value1, replace

preserve
keep if na_item == "Compensation of employees"
replace value1 = value1*1000000000
ren value1 wage_eurostat
drop na_item value flagandfootnotes
save ${country}_eurostat, replace
restore

preserve
tempfile eurosave
save `eurosave', emptyok
keep if na_item == "Gross domestic product at market prices"
replace value1 = value1*1000000000
ren value1 gdp_eurostat
save `eurosave', replace
use ${country}_eurostat, clear
merge 1:1 time using `eurosave', keepusing(gdp_eurostat) nogenerate
save ${country}_eurostat, replace
restore

*Employment
tempfile eurowork
save `eurowork', emptyok
insheet using "$aux/nama_10_pe_1_Data.csv", clear
keep if geo == "$ccode"
split value, parse(,) 
drop value2 
destring value1, replace
replace value1 = value1*1000000
ren value1 employees_eurostat
save `eurowork', replace

use ${country}_eurostat, clear
merge 1:1 time using `eurowork', keepusing(employees_eurostat) nogenerate
drop unit
ren time year
compress
save ${country}_eurostat, replace

*******************************************************************************
*** Variables in current Euros
*******************************************************************************
use ${country}_master_usd, clear

*Fetch operating revenue to use it as gross output
ren id_firm id
merge m:m id year using Finan_${ccode}_USD_clean, keepusing(addedvalue) nogenerate
ren id id_firm
ren addedvalue grossoutput
merge m:1 year using "$output_data/${country}_deflator", keepusing(deflator_idx) nogenerate
drop if year < 1999 | year > 2018

*Convert variables into current euros
merge m:1 year using eur_usd_xr, keepusing(exchange_rate) nogenerate
foreach var in wage_bill sales capital_f inv_total grossoutput{
	replace `var' = `var'*deflator_idx
	replace `var' = `var'*exchange_rate
}

save ${country}_eur, replace

********************************************************************************	
*** Compare with Eurostat
********************************************************************************
*** 1. Full sample ***
use ${country}_eur, clear

collapse (sum) wage_bill grossoutput labor, by(year)
merge 1:1 year using ${country}_eurostat, keepusing(wage_eurostat gdp_eurostat employees_eurostat) nogenerate
drop if year > 2017
gen coverage_wages		= wage_bill/wage_eurostat
gen coverage_output     = grossoutput/gdp_eurostat
gen coverage_employment = labor/employees_eurostat

*Export table
eststo  clear
estpost tabstat coverage_wages coverage_output coverage_employment, by(year)
esttab . using ${ccode}_USD_Eurostat_full.tex, cells("coverage_wages(fmt(2) label(Wages)) coverage_output(label(Output)) coverage_employment(label(Employment))") nonum noobs nomtitle nonumber tex replace

*Plot
foreach var in wage_bill wage_eurostat grossoutput gdp_eurostat{
	gen l_`var' = log(`var')
	scalar define b`var' = l_`var'[1]
	replace l_`var' = l_`var'/b`var'
}

lab var l_wage_bill 	"Wage bill (log)"
lab var l_wage_eurostat "Wage bill Eurostat (log)"
lab var l_grossoutput 	"Gross ouput (log)"
lab var l_gdp_eurostat 	"GDP by Eurostat (log)"
lab var labor           "Orbis"
lab var employees_eurostat "Eurostat"

line l_wage_bill l_wage_eurostat year, lpattern(dash) lcolor(black)
gr export "$figures/wage_bill_eurostat_${country}.png", replace

line l_grossoutput l_gdp_eurostat year, lpattern(dash solid) lcolor(blue red)
gr export "$figures/output_eurostat_${country}.png", replace

line labor employees_eurostat year, lpattern(dash solid) lcolor(purple orange) ytitle("Employment")
gr export "$figures/employment_eurostat_${country}.png", replace

*** 2. Winsorized data ***
use ${country}_eur, clear

*Winsorize and collapse
winsor2 wage_bill grossoutput labor, replace cuts(1, 99)
collapse (sum) wage_bill grossoutput labor, by(year)
merge 1:1 year using ${country}_eurostat, keepusing(wage_eurostat gdp_eurostat employees_eurostat) nogenerate
drop if year > 2017
gen coverage_wages		= wage_bill/wage_eurostat
gen coverage_output     = grossoutput/gdp_eurostat
gen coverage_employment = labor/employees_eurostat

*Coverage table
eststo  clear
estpost tabstat coverage_wages coverage_output coverage_employment, by(year)
esttab . using ${ccode}_USD_Eurostat_winsor.tex, cells("coverage_wages(fmt(2) label(Wages)) coverage_output(label(Output)) coverage_employment(label(Employment))") nonum noobs nomtitle nonumber tex replace

*Plot
foreach var in wage_bill wage_eurostat grossoutput gdp_eurostat{
	gen l_`var' = log(`var')
	scalar define b`var' = l_`var'[1]
	replace l_`var' = l_`var'/b`var'
}

lab var l_wage_bill 	"Wage bill (log)"
lab var l_wage_eurostat "Wage bill Eurostat (log)"
lab var l_grossoutput 	"Gross ouput (log)"
lab var l_gdp_eurostat 	"GDP by Eurostat (log)"
lab var labor           "Orbis"
lab var employees_eurostat "Eurostat"

line l_wage_bill l_wage_eurostat year, lpattern(dash) lcolor(black)
gr export "$figures/wage_bill_eurostat_winsor_${country}.png", replace

line l_grossoutput l_gdp_eurostat year, lpattern(dash solid) lcolor(blue red)
gr export "$figures/output_eurostat_winsor_${country}.png", replace

line labor employees_eurostat year, lpattern(dash solid) lcolor(purple orange) ytitle("Employment")
gr export "$figures/employment_eurostat_winsor_${country}.png", replace

*** 3. Dropping outliers at p1 y p99 ***
use ${country}_eur, clear

*Drop outliers
egen wp1 = pctile(wage_bill),   p(1)
egen o1  = pctile(grossoutput), p(1)
egen wp99= pctile(wage_bill),   p(99)
egen o99 = pctile(grossoutput), p(99) 
drop if wage_bill < wp1
drop if grossoutput < o1
drop if wage_bill > wp99 //Also drops missing values
drop if grossoutput > o99 //Also drops missing values

collapse (sum) wage_bill grossoutput labor, by(year)
merge 1:1 year using ${country}_eurostat, keepusing(wage_eurostat gdp_eurostat employees_eurostat) nogenerate
drop if year > 2017
gen coverage_wages = wage_bill/wage_eurostat
gen coverage_output = grossoutput/gdp_eurostat
gen coverage_employment = labor/employees_eurostat

*Coverage table
eststo  clear
estpost tabstat coverage_wages coverage_output coverage_employment, by(year)
esttab . using ${ccode}_USD_Eurostat_outlier.tex, cells("coverage_wages(fmt(2) label(Wages)) coverage_output(label(Output)) coverage_employment(label(Employment))") nonum noobs nomtitle nonumber tex replace

*Plot
foreach var in wage_bill wage_eurostat grossoutput gdp_eurostat{
	gen l_`var' = log(`var')
	scalar define b`var' = l_`var'[1]
	replace l_`var' = l_`var'/b`var'
}

lab var l_wage_bill 	"Wage bill (log)"
lab var l_wage_eurostat "Wage bill Eurostat (log)"
lab var l_grossoutput 	"Gross ouput (log)"
lab var l_gdp_eurostat 	"GDP by Eurostat (log)"
lab var labor           "Orbis"
lab var employees_eurostat "Eurostat"

line l_wage_bill l_wage_eurostat year, lpattern(dash) lcolor(black)
gr export "$figures/wage_bill_eurostat_p1p99_${country}.png", replace

line l_grossoutput l_gdp_eurostat year, lpattern(dash solid) lcolor(blue red)
gr export "$figures/output_eurostat_p1p99_${country}.png", replace

line labor employees_eurostat year, lpattern(dash solid) lcolor(purple orange) ytitle("Employment")
gr export "$figures/employment_eurostat_p1p99_${country}.png", replace

********************************************************************************	
*** A note on gross output
********************************************************************************
*Diez et al. 2021 uses operating revenue as gross output. What happens if we do the same thing?
use Finan_${ccode}_USD_clean, clear
keep year operatingrevenueturnover
collapse (sum) operatingrevenueturnover, by(year)
merge m:1 year using eur_usd_xr, keepusing(exchange_rate) nogenerate
merge m:1 year using "$output_data/${country}_deflator", keepusing(deflator_idx deflator2005) nogenerate
drop if year > 2017 | year < 1999
replace operatingrevenueturnover = operatingrevenueturnover*deflator_idx
replace operatingrevenueturnover = operatingrevenueturnover*exchange_rate
merge 1:1 year using ${country}_eurostat, keepusing(gdp_eurostat) nogenerate

line gdp_eurostat operatingrevenueturnover year
gr export "$figures/operatingrevenue_full.png", replace

//Dropping outliers
use Finan_${ccode}_USD_clean, clear
keep year operatingrevenueturnover
egen p2 = pctile(operatingrevenueturnover), p(2)
egen p98 = pctile(operatingrevenueturnover), p(98)
drop if operatingrevenueturnover < p2
drop if operatingrevenueturnover > p98

collapse (sum) operatingrevenueturnover, by(year)
merge m:1 year using eur_usd_xr, keepusing(exchange_rate) nogenerate
merge m:1 year using "$output_data/${country}_deflator", keepusing(deflator_idx deflator2005) nogenerate
drop if year > 2017 | year < 1999
replace operatingrevenueturnover = operatingrevenueturnover*deflator_idx
replace operatingrevenueturnover = operatingrevenueturnover*exchange_rate
merge 1:1 year using ${country}_eurostat, keepusing(gdp_eurostat) nogenerate

line gdp_eurostat operatingrevenueturnover year
gr export "$figures/operatingrevenue_outliers.png", replace

