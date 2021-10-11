********************************************************************************
*** Plots, cross-checks and robustness for Orbis USD data
********************************************************************************
*** Main inputs: `country'_master_usd, Finan_`ccode'_USD_clean
*** Additional inputs: `country'_gdp, `country'_delta
*** Output: various .png files
*** Author: Nicolas Oviedo
*** Original: 08/13/2021
*** Code: This code goes through Orbis cleaned data, producing main plots, 
*robustness and consistency checks.
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
global output_data "$pathinit/outputs"
global figures "$pathinit/figures"
global temp "$pathinit/temp"
global aux "$pathinit\inputs\aux_files"
global pwt "C:\Users\Ovi\Desktop\R.A\Data\inputs" //Penn World Table location
}

capture log close
log using "$temp/Orbis_step3.txt", append

cd "$output_data"

di "We start step 3 for ${country}" 

********************************************************************************	
* -------------      Set country and directories       -------------------------
********************************************************************************
*Set country name and code
*global country = ""
*global ccode   = ""
//Check full table in pathdata_raw/LC/step1/country_list_name_USD.dta

*Set country directories
cd "$figures/$country"
global figures "$pathinit/figures/${country}"
capture mkdir assettypes, public
capture mkdir robustness, public

global output_data "$pathinit/outputs/microdata/surveys/${country}"
cd "$output_data"

********************************************************************************	
*** Depreciation rate auxiliary file
********************************************************************************
use Finan_${ccode}_USD_clean, clear
keep id year tangiblefixedassets depreciation
sort id year
drop if depreciation ==. | tangiblefixedassets == .
capture collapse (sum) depreciation tangiblefixedassets, by(year)
gen delta_usd = depreciation/tangiblefixedassets

save "$output_data/${country}_delta", replace

********************************************************************************	
*** Main plots
********************************************************************************
use ${country}_master_usd, clear

ds year country, not
*Number of observations with non missing values per variable
foreach var in `r(varlist)'{
	gen n_`var' = .
	replace n_`var' = 1 if `var' ~= .
}

collapse(sum) labor wage_bill sales capital_f inv_total n_*, by(year)
lab var n_id_firm "Number of firms"
lab var n_labor "Total labor"

//Firms per year
twoway bar n_id_firm year
gr export "$figures/${ccode}_firms.png", replace

//Labor
twoway bar labor year
gr export "$figures/${ccode}_totallabor.png", replace

drop if year == 2018 //Few number of firms

//Capital, investment, salaries and sales per firm
foreach var in labor wage_bill sales capital_f inv_total{
	gen c_`var' = log(`var'/n_`var')
}
lab var c_labor "Workers per firm"
lab var c_wage_bill "Average salary per firm"
lab var c_sales 	"Average sales per firm"
lab var c_capital_f "Capital EOY"
lab var c_inv_total "Average investment per firm"

lab var n_labor "Firms reporting employment"
lab var n_wage_bill "Firms reporting salary"
lab var n_sales "Firms reporting sales"
lab var n_capital_f "Firms with non-missing capital"
lab var n_inv_total "Firms with non-missing investment"

local varlist "labor wage_bill sales capital_f inv_total"
local colores "olive navy maroon teal cyan orange"
forvalues t = 1/5{
	 local color = word("`colores'", `t')
	 local var = word("`varlist'", `t')
	 #delim;
	 twoway bar n_`var' year,
	 color(`color') yaxis(1) ||
	 line c_`var' year, 
	 yaxis(2) legend(size(vsmall))
	 name(`var', replace);
	 #delim cr
	 gr export "$figures/${ccode}_`var'.png", replace
}

********************************************************************************	
*** Consistency checks
********************************************************************************
use ${country}_master_usd, clear

****1. Construct inputted capital using fixed depreciation rates****
//Set fixed depreciation rate
local rate_mch = 0.11
	*local rate_off= 0.11 
	*local rate_bd = 0.03
	*local rate_car = 0.15
sort id_firm year

//Inputted investment
by id_firm: gen inv_inputted = capital_f - capital_f[_n-1] + `rate_mch'*capital_f[_n-1] if _n > 1
capture corr inv_total inv_inputted

//Inputted capital
gen kapital = capital_f
by id_firm: replace kapital = (1-`rate_mch')*kapital[_n-1] + inv_total if _n > 1
capture corr kapital capital_f

//Plot: log scale with 0 in 2000
gen number = 1
ds year country, not
foreach var in `r(varlist)'{
	gen n_`var' = .
	replace n_`var' = 1 if `var' ~= .
}
collapse (sum) inv_total inv_inputted kapital capital_f n_*, by(year)
drop if year == 1999 //Because investment = 0
foreach var in inv_total inv_inputted kapital capital_f{
	gen `var'_idx = `var'/n_`var'
	replace `var'_idx = `var'_idx/`var'_idx[1]
	replace `var'_idx = log(`var'_idx)
}
lab var inv_total_idx    "Log of investment per firm"
lab var inv_inputted_idx "Log of inputted investment per firm"
lab var kapital_idx      "Log of inputted capital per firm"
lab var capital_f_idx	 "Log of capital per firm"

#delim ;
line capital_f_idx kapital_idx year, 
lpattern(solid dash) lwidth(vthin vthin) lcolor(red black)
name(ftotal,replace) 
legend(ring(0) col(1) bmargin(10 0 21 0)  region(lpattern(blank)))  
xscale(range(2000 2020)) 
yscale(range(0 30)) 
xlabel(2000(4)2020) 
ylabel(0(5)30);
#delim cr
gr export "$figures/${ccode}_capital_consistency_total.png", replace

#delim ;
line inv_total_idx inv_inputted_idx year, 
lpattern(solid dash) lwidth(vthin vthin) lcolor(red black)
name(itotal,replace) 
legend(ring(0) col(1) bmargin(10 0 21 0)  region(lpattern(blank)))  
xscale(range(2000 2020)) 
yscale(range(0 30)) 
xlabel(2000(4)2020) 
ylabel(0(5)30);
#delim cr
gr export "$figures/${ccode}_invest_consistency_total.png", replace

****2. Payments due****
//We try to identify anomalies by looking at firms with low investment volatility
/*
use ${country}_master_USD, clear
bysort id: egen inv_avg = mean(inv_total)
bysort id: egen inv_sd = sd(inv_total)
gen inv_cv = abs(inv_sd/inv_avg)
br id year inv_total inv_avg inv_sd inv_cv if inv_cv < 0.03001
drop inv_cv inv_avg inv_sd
*/

****3. GDP****
*Get value added and real GDP
use ${country}_master_USD, clear
ren id_firm id
merge 1:1 id year using Finan_${ccode}_USD_clean.dta, keepusing(operatingrevenueturnover materialcosts addedvalue plforperiodnetincome)
drop _merge
merge m:1 year using ${country}_gdp, keepusing(gdp_real_usd)
drop if _merge == 2
drop _merge

*Generate value added
gen number = 1
collapse (sum) sales operatingrevenueturnover materialcosts addedvalue plforperiodnetincome gdp_real_usd number, by(year)
replace gdp_real_usd = gdp_real_usd/number
gen va = operatingrevenueturnover - materialcosts
foreach var in sales va addedvalue plforperiodnetincome gdp_real_usd{
	gen log_`var' = log(`var')
}

drop if year == 2018
line log_* year
gr export "$figures/value_added_${ccode}.png", replace

****4. Check value added per firm****
use ${country}_master_USD, clear
ren id_firm id
merge 1:1 id year using Finan_${ccode}_USD_clean.dta, keepusing(plforperiodnetincome) nogenerate
drop if plforperiodnetincome == .
gen n_pl = 1
collapse (sum) plforperiodnetincome n_pl, by(year)
lab var n_pl "Firms reporting net income"
gen log_va = log(plforperiodnetincome/n_pl)
lab var log_va "Real value added per firm (log scale)"
drop if year == 2018

#delim ;
     twoway bar n_pl year,
	 color(purple) yaxis(1) ||
	 line log_va year, 
	 yaxis(2) legend(size(vsmall))
	 name(l, replace);
#delim cr

gr export "$figures/${ccode}_va_firms.png", replace

****5. Investment rate****
use ${country}_master_USD, clear
ren id_firm id
drop labor wage_bill sales capital_f country
merge 1:1 id year using Finan_${ccode}_USD_clean.dta, keepusing(grossprofit) nogenerate
drop if grossprofit == . | inv_total == .
capture collapse (sum) grossprofit inv_total, by(year)
gen irate_orbis = inv_total/grossprofit
merge m:1 year using ${country}_gdp.dta, keepusing(irate_usd) nogenerate
sort year
lab var irate_usd "Investment rate national accounts"
lab var irate_orbis "Investment rate Orbis"
drop if year > 2017
line irate_usd irate_orbis year
gr export "$figures/irate.png", replace

********************************************************************************	
*** Robustness
********************************************************************************
use ${country}_master_USD, clear
estpost tabstat id_firm year labor wage_bill sales capital_f inv_total,  statistics(count mean sd min max) columns(statistics)
esttab . using ${ccode}_USD.tex, cells("count mean sd min max") nonum noobs label replace addnotes("Summary statistics for ${country} master")

****1. Accounting practice ****
use Finan_${ccode}_USD_clean, clear
//Define criteria. Set ACC for accounting practice, FIL for filing type
local robust = "FIL"
if "`robust'" == "ACC" {
	drop if accountingpractice == "IFRS"
}
if "`robust'" == "FIL"{
	drop if filingtype == "Annual report"
}
gen capital_f = tangiblefixedassets + intangiblefixedassets
keep id year capital_f sales
estpost tabstat capital_f sales, statistics(count mean sd min max) columns(statistics)
esttab . using `robust'.tex, cells("count mean sd min max") nonum noobs label replace addnotes("Summary statistics for `robust'")
gen n_capital_f = 1 if capital_f ~= .
gen n_sales = 1 if sales ~= .
collapse (sum) sales capital_f n_*, by(year)
gen log_sales = log(sales/n_sales)
gen log_capital_f = log(capital_f/n_capital_f)
line log_* year, name(`robust', replace)
gr export "$figures/robustness/robustness_${ccode}_`robust'.png", replace

****2. Log of capital ****
*We have plotted log of total capital. Try instead with sum of log of capital
use ${country}_master_USD, clear
replace capital_f = log(capital_f)
gen n_capital_f = 1 if capital_f ~= .
collapse (sum) capital_f n_*, by(year)
gen c_capital_f = capital_f/n_capital_f
lab var c_capital_f "Sum of log of capital per firm"
#delim;
twoway line c_capital_f year,
lpattern(dash) lcolor(black)
name(sumlogcapital, replace);
#delim cr
gr export "$figures/robustness/robustness_${ccode}_logcapital.png", replace

********************************************************************************	
*** Tackling selection
********************************************************************************
**** 1. Firms +10yr ****
use ${country}_master_USD, clear
bysort id_firm: gen life = year[_N] - year[1] + 1
keep if life > 9 //Keeps 68% of full sample

//Number of observations with non missing values per variable
ds year country, not
foreach var in `r(varlist)'{
	gen n_`var' = .
	replace n_`var' = 1 if `var' ~= .
}

capture collapse(sum) labor wage_bill sales capital_f inv_total n_*, by(year)
drop if year == 2018
lab var n_id_firm "Number of firms"
lab var labor "Total labor"

//Firms per year
twoway bar n_id_firm year, color(blue)
gr export "$figures/robustness/${ccode}_firms.png", replace

//Labor
twoway bar labor year, color(gray)
gr export "$figures/robustness/${ccode}_totallabor.png", replace

//Capital, investment, salaries and sales per firm
foreach var in labor wage_bill sales capital_f inv_total{
	gen c_`var' = log(`var'/n_`var')
}
lab var c_labor "Workers per firm"
lab var c_wage_bill "Average salary per firm"
lab var c_sales 	"Average sales per firm"
lab var c_capital_f "Capital EOY"
lab var c_inv_total "Average investment per firm"

local varlist "labor wage_bill sales capital_f inv_total"
local colores "olive navy maroon teal cyan orange"
forvalues t = 1/5{
	 local color = word("`colores'", `t')
	 local var = word("`varlist'", `t')
	 #delim;
	 twoway line c_`var' year,
	 lwidth(thick) lcolor(`color') lpattern(dash)
	 name(`var', replace);
	 #delim cr
	 gr export "$figures/robustness/${ccode}_`var'.png",replace
}

**** 2. Firms born in 1999 ***
use ${country}_master_USD, clear

gen born = 1 if year == 1999
sort id_firm year
by id_firm (year): replace born = 1 if born[1] == 1
drop if born ~= 1

gen n_capital = 1 if capital_f ~= .
gen n_sales = 1 if sales ~= .
capture collapse (sum) capital_f sales n_capital n_sales, by(year)

gen log_capital = log(capital_f/n_capital)
lab var log_capital "Log of capital per firm"
lab var n_capital "Firms with non-missing capital"
gen log_sales = log(sales/n_sales)
lab var log_sales "Log of sales per firm"
lab var n_sales "Firms with non-missing sales"
drop if year == 2018

#delim;
twoway bar n_capital year,
color(gray) yaxis(1) ||
line log_capital year,
lcolor(blue) lpattern(dash) yaxis(2) legend(size(vsmall))
name(capital, replace);
#delim cr

gr export "$figures/${ccode}_firms_1999.png", replace

#delim;
twoway bar n_capital year,
color(gray) yaxis(1) ||
line log_sales year,
lcolor(red) lpattern(dash) yaxis(2) legend(size(vsmall))
name(capital, replace);
#delim cr

gr export "$figures/${ccode}_firms_1999.png", replace

*** 3. Firms born in 2005***
use ${country}_master_USD, clear

sort id_firm year
by id_firm: gen exist = 1 if year[1] == 2005
by id_firm: egen sumexist = total(exist)
drop if sumexist == 0

gen n_capital = 1 if capital_f ~= .
gen n_sales = 1 if sales ~= .
capture collapse (sum) capital_f sales n_capital n_sales, by(year)

gen log_capital = log(capital_f/n_capital)
lab var log_capital "Log of capital per firm"
lab var n_capital "Firms with non-missing capital"
gen log_sales = log(sales/n_sales)
lab var log_sales "Log of sales per firm"
lab var n_sales "Firms with non-missing sales"
drop if year == 2018

#delim;
twoway bar n_capital year,
color(bluishgray) yaxis(1) ||
line log_capital year,
lcolor(midblue) lpattern(longdash_dot) yaxis(2) legend(size(vsmall))
name(capital, replace);
#delim cr

gr export "$figures/${ccode}_firms_2005.png", replace

#delim;
twoway bar n_sales year,
color(dimgray) yaxis(1) ||
line log_sales year,
lcolor(orange_red) lpattern(longdash_dot) yaxis(2) legend(size(vsmall))
name(sales, replace);
#delim cr

gr export "$figures/${ccode}_firms_2005.png", replace

*** 4. Drop discontinuous firms***
use Finan_${ccode}_USD_clean, clear

ren id id_firm
sort id_firm year
by id_firm (year): gen gapyear = year[_n] - year[_n-1]
by id_firm: egen maxgap = max(gapyear)
replace maxgap = 0 if maxgap == .
drop if maxgap > 1

ren numberofemployees labor
ren costsofemployees wage_bill
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
ren depreciationamortization depreciation
order id_firm year labor wage_bill sales capital_f country
drop consolidationcode - maxgap

gen n_capital = 1 if capital_f ~= .
gen n_sales = 1 if sales ~= .
collapse (sum) capital_f sales n_capital n_sales, by(year)

gen log_capital = log(capital_f/n_capital)
lab var log_capital "Log of capital per firm"
lab var n_capital "Firms with non-missing capital"
gen log_sales = log(sales/n_sales)
lab var log_sales "Log of sales per firm"
lab var n_sales "Firms with non-missing sales"
drop if year == 2018

//Capital
#delim;
twoway bar n_capital year,
color(khaki) yaxis(1) ||
line log_capital year,
lcolor(edkblue) lpattern(longdash_dot) yaxis(2) legend(size(vsmall))
name(capital, replace);
#delim cr

gr export "$figures/${ccode}_capital_continuous.png", replace

//Sales
#delim;
twoway bar n_sales year,
color(gs13) yaxis(1) ||
line log_sales year,
lcolor(pink) lpattern(longdash_dot) yaxis(2) legend(size(vsmall))
name(sales, replace);
#delim cr

gr export "$figures/${ccode}_sales_continuous.png", replace

********************************************************************************	
*** Alternative measures of capital stock
********************************************************************************
****1. Capital stock by Gal (2013)****
/*K_t = K_{t-1} (1-delta) + I_t
	where I = KBV_t - KBV_{t-1} + DEPR
		KBV:book value of tangible fixed assets
*/
use Finan_${ccode}_USD_clean, clear
keep id year *assets depreciation
sort id year
by id: gen I = tangiblefixedassets[_n] - tangiblefixedassets[_n-1] + depreciation if _n > 1
gen capital_gal = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
merge m:1 year using ${country}_delta, keepusing(delta_usd) nogenerate // Recover estimated depreciation rate
bysort id (year): replace capital_gal = capital_gal[_n-1]*(1-delta_usd[_n]) + I[_n] if _n > 1
gen firms = 1 if capital_gal ~=.

collapse(sum) capital_gal firms, by(year)
gen c_capital_gal = log(capital_gal/firms)
lab var c_capital_gal "Log of capital_gal per firm"
drop if year == 2018
#delim;
twoway line c_capital_gal year,
lwidth(thick) lcolor(purple) lpattern(dash)
name(capitalgal, replace)
caption("Capital following Gal 2013");
#delim cr
gr export "$figures/robustness/${ccode}_capital_gal.png",replace

****2. Excluding firms with huge capital jumps****
use Finan_${ccode}_USD_clean, clear

//Exclude firms
keep id year *assets depreciation
sort id year
by id: gen capfall = tangiblefixedassets[_n]/tangiblefixedassets[_n-1] if _n > 1
bysort id (year): egen tokeep = min(capfall)
drop if tokeep < 0.8 // Deletes 68% of sample approx.

//Capital by Gopinath
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
gen number	  = 1 if capital_f ~=. // Firms with non missing value

//Capital by Gal
sort id year
by id: gen I 	= tangiblefixedassets[_n] - tangiblefixedassets[_n-1] + depreciation if _n > 1
gen capital_gal = tangiblefixedassets + intangiblefixedassets
merge m:1 year using ${country}_delta, keepusing(delta) nogenerate
bysort id (year): replace capital_gal = capital_gal[_n-1]*(1-delta[_n]) + I if _n > 1
gen firms = 1 if capital_gal ~=.

//Collapse to plot
collapse (sum) capital_f number capital_gal firms, by(year)
gen c_capital_f = log(capital_f/number)
lab var c_capital_f "Log of capital_f per firm"
gen c_capital_gal = log(capital_gal/firms)
lab var c_capital_gal "Log of capital_gal per firm"
drop if year == 2018

#delim;
twoway line c_capital_f year,
lwidth(thick) lcolor(yellow) lpattern(dash)
name(capitalf, replace)
caption("Capital following Gopinath 2017, excluding firms with +20% YoY falls");
#delim cr
gr export "$figures/robustness/${ccode}_capital_gopinath_smooth.png",replace

#delim;
twoway line c_capital_gal year,
lwidth(thick) lcolor(orange) lpattern(dash)
name(capitalgal, replace)
caption("Capital following Gal 2013, excluding firms with +20% YoY falls");
#delim cr
gr export "$figures/robustness/${ccode}_capital_gal_smooth.png",replace

****3. Use only depreciation rate****
/* Variable depreciation contains plenty of missing values. We construct capital following Gal 2013
but using depreciation rate from sample to estimate investment.*/

use Finan_${ccode}_USD_clean, clear
keep id year *assets
merge m:1 year using ${country}_delta, keepusing(delta_usd) nogenerate // Recover estimated depreciation rate
sort id year
by id: gen I = (1+delta_usd[_n])*tangiblefixedassets[_n] - tangiblefixedassets[_n-1] if _n > 1
gen capital_gal = tangiblefixedassets + intangiblefixedassets
bysort id (year): replace capital_gal = capital_gal[_n-1]*(1-delta_usd[_n]) + I[_n] if _n > 1
gen firms = 1 if capital_gal ~=.

collapse(sum) capital_gal firms I, by(year)
gen c_capital_gal = log(capital_gal/firms)
lab var c_capital_gal "Log of capital_gal per firm"
drop if year == 2018

#delim;
twoway line c_capital_gal year,
lwidth(thick) lcolor(red) lpattern(dash)
name(capitalf, replace)
caption("Capital following Gal 2013 using sample depreciation rate");
#delim cr
gr export "$figures/robustness/${ccode}_capital_gal_delta.png",replace

**** 4. Tangible and intangible assets****
use Finan_${ccode}_USD_clean, clear
keep id country year *assets
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017

//Number of observations with non missing values per variable
ds year country, not
foreach var in `r(varlist)'{
	gen n_`var' = .
	replace n_`var'= 1 if `var' ~= .
}
ds id year country, not
capture collapse(sum) `r(varlist)', by(year)
drop if year == 2018

local varlist "fixedassets intangiblefixedassets tangiblefixedassets otherfixedassets currentassets othercurrentassets totalassets netcurrentassets capital_f"
foreach var in `varlist' {
	gen c_`var' = log(`var'/n_`var')
}
local varlist "fixedassets intangiblefixedassets tangiblefixedassets otherfixedassets currentassets othercurrentassets totalassets netcurrentassets capital_f"
local colores "olive navy maroon teal cyan orange blue gray red"
forvalues t = 1/9{
	 local color = word("`colores'", `t')
	 local var = word("`varlist'", `t')
	 #delim;
	 twoway line c_`var' year,
	 lwidth(thick) lcolor(`color') lpattern(dash)
	 name(`var', replace);
	 #delim cr
	 gr export "$figures/assettypes/${ccode}_`var'.png",replace
}

********************************************************************************	
*** Investment histogram
********************************************************************************
**** 1. Full sample****
/*K_t = K_{t-1} (1-delta) + I_t
	where I = KBV_t - KBV_{t-1} + DEPR
		KBV:book value of tangible fixed assets
*/
use Finan_${ccode}_USD_clean, clear
keep id year *assets
sort id year
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
merge m:1 year using ${country}_delta, keepusing(delta_usd) nogenerate // Recover estimated depreciation rate

bysort id (year): gen I = tangiblefixedassets[_n] - tangiblefixedassets[_n-1] + delta_usd[_n]*tangiblefixedassets[_n-1]
gen firms = 1 if capital_f ~=.
gen irate = I/capital_f
drop if irate ==.
egen p98 = pctile(irate), p(98)
egen p2 = pctile(irate), p(2)
drop if irate > p98 | irate < p2

capture histogram irate, bin(10) percent
capture gr export "$figures/hist_gal_full_${ccode}.png", replace

//Plot investment per firm
gen firmsinv = 1 if I ~=.
capture collapse (sum) I firmsinv, by(year)
drop if year == 2018
gen log_inv = log(I/firmsinv)
lab var firmsinv "Firms with non-missing investment"
lab var log_inv "Log of investment per firm"

#delim;
twoway bar firmsinv year,
color(ebblue) yaxis(1) ||
line log_inv year, 
yaxis(2) legend(size(vsmall))
name(I, replace);
#delim cr

gr export "$figures/${ccode}_inv_delta.png", replace

**** 2. Permanent sample****
use Finan_${ccode}_USD_clean, clear
keep id year *assets
sort id year
by id (year): gen life = year[_N] - year[1] + 1
keep if life > 9

capture{
gen capital_f = tangiblefixedassets + intangiblefixedassets // Capital stock as in Gopinath et al. 2017
merge m:1 year using ${country}_delta, keepusing(delta_usd) nogenerate // Recover estimated depreciation rate
bysort id (year): gen I = tangiblefixedassets[_n] - tangiblefixedassets[_n-1] + delta_usd[_n]*tangiblefixedassets[_n-1]

gen irate = I/capital_f
gen firms = 1 if capital_f ~=.
drop if irate ==.
egen p98 = pctile(irate), p(98)
egen p2 = pctile(irate), p(2)
drop if irate > p98 | irate < p2

histogram irate, bin(10) percent fcolor(blue)
gr export "$figures/hist_perma_${ccode}.png"
}
di "We finish step 3 for ${country}" 
